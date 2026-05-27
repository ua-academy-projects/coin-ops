package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"regexp"
	"strconv"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	amqp "github.com/rabbitmq/amqp091-go"
	"github.com/redis/go-redis/v9"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
	"gopkg.in/yaml.v3"
	secretmanager "cloud.google.com/go/secretmanager/apiv1"
	"cloud.google.com/go/secretmanager/apiv1/secretmanagerpb"
)

const (
	gammaBaseURL = "https://gamma-api.polymarket.com"
	dataBaseURL  = "https://data-api.polymarket.com"
	queueName    = "market_events"
)

const (
	// Binance public ticker — no API key, generous rate limits.
	// Returns: [{"symbol":"BTCUSDT","price":"...","priceChangePercent":"..."},...]
	binanceURL   = "https://api.binance.com/api/v3/ticker/24hr?symbols=[%22BTCUSDT%22,%22ETHUSDT%22]"
	nbuURL       = "https://bank.gov.ua/NBUStatService/v1/statdirectory/exchange?valcode=USD&json"
)

var httpClient = &http.Client{Timeout: 10 * time.Second}

// validSID accepts alphanumeric, hyphens, underscores: 8–128 chars (UUID format).
var validSID = regexp.MustCompile(`^[a-zA-Z0-9_-]{8,128}$`)

// ---- Gamma API raw types ----

type GammaMarket struct {
	Question      string          `json:"question"`
	Slug          string          `json:"slug"`
	OutcomePrices json.RawMessage `json:"outcomePrices"` // stringified JSON array OR proper array
	Volume24hr    interface{}     `json:"volume24hr"`    // string or float64
	EndDateIso    string          `json:"endDateIso"`
	Category      string          `json:"category"`
}

// ---- Data API raw types ----

type LeaderboardEntry struct {
	ProxyWallet string  `json:"proxyWallet"`
	UserName    string  `json:"userName"`
	Pnl         float64 `json:"pnl"`
	Vol         float64 `json:"vol"`
	Rank        string  `json:"rank"` // API returns "1", "2", ... as strings
}

type PositionEntry struct {
	Title        string  `json:"title"`
	Slug         string  `json:"slug"` // already present in response
	Outcome      string  `json:"outcome"`
	CurrentValue float64 `json:"currentValue"`
	Size         float64 `json:"size"`
	CurPrice     float64 `json:"curPrice"`
}

// ---- Output / wire types ----

type MarketSnapshot struct {
	Slug      string    `json:"slug"`
	Question  string    `json:"question"`
	YesPrice  float64   `json:"yes_price"`
	NoPrice   float64   `json:"no_price"`
	Volume24h float64   `json:"volume_24h"`
	Category  string    `json:"category"`
	EndDate   string    `json:"end_date"`
	FetchedAt time.Time `json:"fetched_at"`
}

type WhalePosition struct {
	Market       string  `json:"market"`
	Slug         string  `json:"slug,omitempty"`
	Outcome      string  `json:"outcome"`
	CurrentValue float64 `json:"current_value"`
	Size         float64 `json:"size"`
	AvgPrice     float64 `json:"avg_price"`
}

type Whale struct {
	Pseudonym string          `json:"pseudonym"`
	Address   string          `json:"address"`
	Pnl       float64         `json:"pnl"`
	Volume    float64         `json:"volume"`
	Rank      int             `json:"rank"`
	Positions []WhalePosition `json:"positions"`
}

// ---- Price API raw types ----

// binanceTicker represents one symbol from the Binance 24hr ticker response.
type binanceTicker struct {
	Symbol             string `json:"symbol"`
	LastPrice          string `json:"lastPrice"`
	PriceChangePercent string `json:"priceChangePercent"`
}

type nbuEntry struct {
	Rate float64 `json:"rate"`
}

// ---- Prices wire type ----

type Prices struct {
	BtcUsd       float64   `json:"btc_usd"`
	EthUsd       float64   `json:"eth_usd"`
	Btc24hChange float64   `json:"btc_24h_change"`
	Eth24hChange float64   `json:"eth_24h_change"`
	UsdUah       float64   `json:"usd_uah"`
	FetchedAt    time.Time `json:"fetched_at"`
}

// PriceEvent is the message published to market_events for each coin.
type PriceEvent struct {
	Type      string  `json:"type"`
	Coin      string  `json:"coin"`
	PriceUsd  float64 `json:"price_usd"`
	Change24h float64 `json:"change_24h"`
	FetchedAt string  `json:"fetched_at"`
}

// ---- Server ----

type Server struct {
	ch      *amqp.Channel
	chMu    sync.Mutex
	rdb     *redis.Client
	db      stateDB
	backend string
	state   StateStore
	cache   struct {
		sync.RWMutex
		markets []MarketSnapshot
		whales  []Whale
		prices  Prices
		lastNBU time.Time
	}
}

// ---- RabbitMQ ----

func connectRabbitMQ(url string) *amqp.Connection {
	for {
		conn, err := amqp.Dial(url)
		if err == nil {
			log.Println("Connected to RabbitMQ")
			return conn
		}
		log.Printf("RabbitMQ unavailable: %v — retrying in 5s", err)
		time.Sleep(5 * time.Second)
	}
}

func (s *Server) pgEnqueue(body []byte) error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_, err := s.db.Exec(ctx, "SELECT runtime.enqueue_event($1::jsonb)", body)
	return err
}

func (s *Server) publishPriceEvent(coin string, priceUsd, change24h float64, fetchedAt time.Time) error {
	evt := PriceEvent{
		Type:      "price",
		Coin:      coin,
		PriceUsd:  priceUsd,
		Change24h: change24h,
		FetchedAt: fetchedAt.Format(time.RFC3339),
	}
	body, err := json.Marshal(evt)
	if err != nil {
		return err
	}

	if s.backend == "postgres" {
		return s.pgEnqueue(body)
	}

	s.chMu.Lock()
	defer s.chMu.Unlock()
	return s.ch.Publish("", queueName, false, false, amqp.Publishing{
		DeliveryMode: amqp.Persistent,
		ContentType:  "application/json",
		Body:         body,
	})
}

func (s *Server) publish(snap MarketSnapshot) error {
	body, err := json.Marshal(snap)
	if err != nil {
		return err
	}

	if s.backend == "postgres" {
		return s.pgEnqueue(body)
	}

	s.chMu.Lock()
	defer s.chMu.Unlock()
	return s.ch.Publish("", queueName, false, false, amqp.Publishing{
		DeliveryMode: amqp.Persistent,
		ContentType:  "application/json",
		Body:         body,
	})
}

// ---- Helpers ----

func toFloat(v interface{}) float64 {
	switch x := v.(type) {
	case float64:
		return x
	case string:
		f, _ := strconv.ParseFloat(x, 64)
		return f
	case json.Number:
		f, _ := x.Float64()
		return f
	}
	return 0
}

// outcomePrices arrives as either a JSON array of strings or a stringified JSON array.
func parseOutcomePrices(raw json.RawMessage) (yes, no float64) {
	// Try direct array of strings: ["0.62","0.38"]
	var prices []string
	if err := json.Unmarshal(raw, &prices); err == nil {
		if len(prices) > 0 {
			yes, _ = strconv.ParseFloat(prices[0], 64)
		}
		if len(prices) > 1 {
			no, _ = strconv.ParseFloat(prices[1], 64)
		}
		return
	}
	// Try stringified: "[\"0.62\",\"0.38\"]"
	var s string
	if err := json.Unmarshal(raw, &s); err == nil {
		var inner []string
		if err := json.Unmarshal([]byte(s), &inner); err == nil {
			if len(inner) > 0 {
				yes, _ = strconv.ParseFloat(inner[0], 64)
			}
			if len(inner) > 1 {
				no, _ = strconv.ParseFloat(inner[1], 64)
			}
		}
	}
	return
}

func fetchJSON(url string, out interface{}) error {
	resp, err := httpClient.Get(url)
	if err != nil {
		return fmt.Errorf("GET %s: %w", url, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("HTTP error %d from %s", resp.StatusCode, url)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("read body %s: %w", url, err)
	}
	if err := json.Unmarshal(body, out); err != nil {
		return fmt.Errorf("decode %s: %w", url, err)
	}
	return nil
}

// ---- Gamma API ----

func fetchMarkets() ([]GammaMarket, error) {
	url := gammaBaseURL + "/markets?limit=20&active=true&closed=false&order=volume24hr&ascending=false"
	var markets []GammaMarket
	return markets, fetchJSON(url, &markets)
}

func normalizeMarket(m GammaMarket, fetchedAt time.Time) MarketSnapshot {
	yes, no := parseOutcomePrices(m.OutcomePrices)
	return MarketSnapshot{
		Slug:      m.Slug,
		Question:  m.Question,
		YesPrice:  yes,
		NoPrice:   no,
		Volume24h: toFloat(m.Volume24hr),
		Category:  m.Category,
		EndDate:   m.EndDateIso,
		FetchedAt: fetchedAt,
	}
}

// ---- Data API ----

func fetchLeaderboard() ([]LeaderboardEntry, error) {
	url := dataBaseURL + "/v1/leaderboard?limit=20&timePeriod=MONTH&category=OVERALL&orderBy=PNL"
	body, err := httpClient.Get(url)
	if err != nil {
		return nil, fmt.Errorf("GET leaderboard: %w", err)
	}
	defer body.Body.Close()
	raw, err := io.ReadAll(body.Body)
	if err != nil {
		return nil, err
	}

	// Try direct array first
	var entries []LeaderboardEntry
	if err := json.Unmarshal(raw, &entries); err == nil {
		return entries, nil
	}
	// Try wrapped {"data": [...]}
	var wrapped struct {
		Data []LeaderboardEntry `json:"data"`
	}
	if err := json.Unmarshal(raw, &wrapped); err != nil {
		return nil, fmt.Errorf("decode leaderboard: %w", err)
	}
	return wrapped.Data, nil
}

func fetchPositions(address string) ([]WhalePosition, error) {
	url := fmt.Sprintf(
		"%s/positions?user=%s&limit=50&sizeThreshold=1&sortBy=CURRENT&sortDirection=DESC",
		dataBaseURL, address,
	)
	var raw []PositionEntry
	if err := fetchJSON(url, &raw); err != nil {
		return nil, err
	}
	positions := make([]WhalePosition, 0, len(raw))
	for _, p := range raw {
		positions = append(positions, WhalePosition{
			Market:       p.Title,
			Slug:         p.Slug,
			Outcome:      p.Outcome,
			CurrentValue: p.CurrentValue,
			Size:         p.Size,
			AvgPrice:     p.CurPrice,
		})
	}
	return positions, nil
}

// ---- Price APIs ----

func fetchBinance() (btc, eth float64, btc24h, eth24h float64, err error) {
	var tickers []binanceTicker
	if err = fetchJSON(binanceURL, &tickers); err != nil {
		return
	}
	for _, t := range tickers {
		price, _ := strconv.ParseFloat(t.LastPrice, 64)
		pct, _ := strconv.ParseFloat(t.PriceChangePercent, 64)
		switch t.Symbol {
		case "BTCUSDT":
			btc, btc24h = price, pct
		case "ETHUSDT":
			eth, eth24h = price, pct
		}
	}
	if btc <= 0 || eth <= 0 {
		err = fmt.Errorf("binance: incomplete ticker data (btc=%.0f eth=%.0f)", btc, eth)
	}
	return
}

func fetchNBU() (float64, error) {
	var entries []nbuEntry
	if err := fetchJSON(nbuURL, &entries); err != nil {
		return 0, err
	}
	if len(entries) == 0 {
		return 0, fmt.Errorf("NBU returned empty response")
	}
	return entries[0].Rate, nil
}

// ---- Background refresh loops ----

func (s *Server) fetchAndUpdateMarkets() {
	markets, err := fetchMarkets()
	if err != nil {
		log.Printf("Market update: fetch failed: %v", err)
		return
	}

	fetchedAt := time.Now().UTC()
	snapshots := make([]MarketSnapshot, 0, len(markets))
	for _, m := range markets {
		snap := normalizeMarket(m, fetchedAt)
		if err := s.publish(snap); err != nil {
			log.Printf("Market update: publish failed for %s: %v", snap.Slug, err)
		}
		snapshots = append(snapshots, snap)
	}

	s.cache.Lock()
	s.cache.markets = snapshots
	s.cache.Unlock()
	log.Printf("Market cache updated: %d markets", len(snapshots))
}

func (s *Server) fetchAndUpdateCache() {
	leaderboard, err := fetchLeaderboard()
	if err != nil {
		log.Printf("Cache update: leaderboard fetch failed: %v", err)
		return
	}

	whales := make([]Whale, 0, len(leaderboard))
	for i, entry := range leaderboard {
		positions, err := fetchPositions(entry.ProxyWallet)
		if err != nil {
			log.Printf("Cache update: positions fetch failed for %s: %v", entry.ProxyWallet, err)
			positions = []WhalePosition{}
		}
		whales = append(whales, Whale{
			Pseudonym: entry.UserName,
			Address:   entry.ProxyWallet,
			Pnl:       entry.Pnl,
			Volume:    entry.Vol,
			Rank:      i + 1,
			Positions: positions,
		})
	}

	s.cache.Lock()
	s.cache.whales = whales
	s.cache.Unlock()
	log.Printf("Whale cache updated: %d whales", len(whales))
}

func (s *Server) fetchAndUpdatePrices() {
	now := time.Now().UTC()

	s.cache.RLock()
	oldPrices := s.cache.prices
	lastNBU := s.cache.lastNBU
	s.cache.RUnlock()

	uah := oldPrices.UsdUah

	// Fetch NBU only if uah is 0 or it's been more than an hour
	if uah == 0 || now.Sub(lastNBU) > time.Hour {
		newUAH, err := fetchNBU()
		if err != nil {
			log.Printf("Price update: NBU fetch failed: %v", err)
			lastNBU = now // Prevent retrying every cycle on failure
		} else if newUAH > 0 {
			uah = newUAH
			lastNBU = now
		}
	}

	btcUsd, ethUsd, btc24h, eth24h, errBin := fetchBinance()
	var publishCrypto bool
	if errBin != nil {
		log.Printf("Price update: Binance fetch failed: %v", errBin)
		// Keep stale values in cache; don't publish stale prices
		btcUsd, ethUsd = oldPrices.BtcUsd, oldPrices.EthUsd
		btc24h, eth24h = oldPrices.Btc24hChange, oldPrices.Eth24hChange
	} else {
		publishCrypto = true
	}

	prices := Prices{
		BtcUsd:       btcUsd,
		EthUsd:       ethUsd,
		Btc24hChange: btc24h,
		Eth24hChange: eth24h,
		UsdUah:       uah,
		FetchedAt:    now,
	}

	s.cache.Lock()
	s.cache.prices = prices
	s.cache.lastNBU = lastNBU
	s.cache.Unlock()

	// Publish price events to queue for persistence in PostgreSQL
	if publishCrypto {
		if err := s.publishPriceEvent("bitcoin", btcUsd, btc24h, now); err != nil {
			log.Printf("Price publish failed (bitcoin): %v", err)
		}
		if err := s.publishPriceEvent("ethereum", ethUsd, eth24h, now); err != nil {
			log.Printf("Price publish failed (ethereum): %v", err)
		}
	}
	if uah > 0 && lastNBU == now { // Only publish NBU when freshly fetched
		if err := s.publishPriceEvent("usd_uah", uah, 0, now); err != nil {
			log.Printf("Price publish failed (usd_uah): %v", err)
		}
	}

	log.Printf("Price cache updated: BTC=$%.0f ETH=$%.0f UAH=%.2f", btcUsd, ethUsd, uah)
}

// ---- HTTP handlers ----

func setNoStoreHeaders(w http.ResponseWriter) {
	w.Header().Set("Cache-Control", "no-store, no-cache, must-revalidate, proxy-revalidate")
	w.Header().Set("Pragma", "no-cache")
	w.Header().Set("Expires", "0")
}

func corsMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		setNoStoreHeaders(w)
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next(w, r)
	}
}

func corsMiddlewareWithPost(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		setNoStoreHeaders(w)
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next(w, r)
	}
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status":          "ok",
		"runtime_backend": s.backend,
	})
}

func (s *Server) handleCurrent(w http.ResponseWriter, r *http.Request) {
	s.cache.RLock()
	snapshots := append([]MarketSnapshot(nil), s.cache.markets...)
	s.cache.RUnlock()

	if len(snapshots) == 0 {
		s.fetchAndUpdateMarkets()
		s.cache.RLock()
		snapshots = append([]MarketSnapshot(nil), s.cache.markets...)
		s.cache.RUnlock()
		if len(snapshots) == 0 {
			http.Error(w, "market cache unavailable", http.StatusBadGateway)
			return
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(snapshots)
}

func (s *Server) handleWhales(w http.ResponseWriter, r *http.Request) {
	s.cache.RLock()
	whales := s.cache.whales
	s.cache.RUnlock()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(whales)
}

func (s *Server) handlePrices(w http.ResponseWriter, r *http.Request) {
	s.cache.RLock()
	prices := s.cache.prices
	s.cache.RUnlock()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(prices)
}

func (s *Server) handleGetState(w http.ResponseWriter, r *http.Request) {
	sid := r.URL.Query().Get("sid")
	if sid == "" {
		http.Error(w, "missing sid parameter", http.StatusBadRequest)
		return
	}
	if !validSID.MatchString(sid) {
		http.Error(w, "invalid sid", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()

	val, err := s.state.GetState(ctx, sid)
	if errors.Is(err, ErrStateNotFound) {
		// No state stored yet for this session — return empty object so
		// callers don't need to special-case 404 vs. empty state.
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte("{}"))
		return
	}
	if err != nil {
		http.Error(w, "state unavailable", http.StatusServiceUnavailable)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Write(val)
}

func (s *Server) handlePostState(w http.ResponseWriter, r *http.Request) {
	sid := r.URL.Query().Get("sid")
	if sid == "" {
		http.Error(w, "missing sid parameter", http.StatusBadRequest)
		return
	}
	if !validSID.MatchString(sid) {
		http.Error(w, "invalid sid", http.StatusBadRequest)
		return
	}

	body, err := io.ReadAll(io.LimitReader(r.Body, 4096))
	if err != nil {
		http.Error(w, "read body failed", http.StatusBadRequest)
		return
	}

	if !json.Valid(body) {
		http.Error(w, "body must be valid JSON", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()

	if err := s.state.SetState(ctx, sid, body); err != nil {
		http.Error(w, "state unavailable", http.StatusServiceUnavailable)
		return
	}
}

func (s *Server) handleState(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		s.handleGetState(w, r)
	case http.MethodPost:
		s.handlePostState(w, r)
	default:
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

// ---- Config types ----

type Config struct {
	App struct {
		RuntimeBackend string `yaml:"runtime_backend"`
		Port           int    `yaml:"port"`
	} `yaml:"app"`
	RabbitMQ struct {
		DefaultUser string `yaml:"default_user"`
	} `yaml:"rabbitmq"`
	Redis struct {
		URL string `yaml:"url"`
	} `yaml:"redis"`
}

type Secrets struct {
	DatabaseURL string `json:"DATABASE_URL"`
	RabbitMQURL string `json:"RABBITMQ_URL"`
}

func loadConfig(path string) (*Config, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	var cfg Config
	decoder := yaml.NewDecoder(file)
	if err := decoder.Decode(&cfg); err != nil {
		return nil, err
	}
	return &cfg, nil
}

func fetchSecretsAWS(ctx context.Context, secretName, region string) (*Secrets, error) {
	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion(region))
	if err != nil {
		return nil, err
	}

	client := secretsmanager.NewFromConfig(cfg)
	result, err := client.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
		SecretId: &secretName,
	})
	if err != nil {
		return nil, err
	}

	var secrets Secrets
	if err := json.Unmarshal([]byte(*result.SecretString), &secrets); err != nil {
		return nil, err
	}

	return &secrets, nil
}

func fetchSecretsGCP(ctx context.Context, projectID, secretID string) (*Secrets, error) {
	client, err := secretmanager.NewClient(ctx)
	if err != nil {
		return nil, err
	}
	defer client.Close()

	name := fmt.Sprintf("projects/%s/secrets/%s/versions/latest", projectID, secretID)
	req := &secretmanagerpb.AccessSecretVersionRequest{
		Name: name,
	}

	result, err := client.AccessSecretVersion(ctx, req)
	if err != nil {
		return nil, err
	}

	var secrets Secrets
	if err := json.Unmarshal(result.Payload.Data, &secrets); err != nil {
		return nil, err
	}

	return &secrets, nil
}

func main() {
	configPath := os.Getenv("CONFIG_PATH")
	if configPath == "" {
		configPath = "/opt/coinops/config.yaml"
	}
	cloudProvider := os.Getenv("CLOUD_PROVIDER")
	if cloudProvider == "" {
		cloudProvider = "aws"
	}

	// AWS
	secretNameAWS := os.Getenv("AWS_SECRET_NAME")
	if secretNameAWS == "" {
		secretNameAWS = "coinops/production/app-secrets"
	}
	awsRegion := os.Getenv("AWS_REGION")
	if awsRegion == "" {
		awsRegion = "us-east-1"
	}

	// GCP
	gcpProjectID := os.Getenv("GCP_PROJECT_ID")
	gcpSecretID := os.Getenv("GCP_SECRET_ID")
	if gcpSecretID == "" {
		gcpSecretID = "coinops-app-secrets"
	}

	var backend, dbURL, port string
	var rabbitURL, redisURL string

	appConfig, err := loadConfig(configPath)
	if err == nil {
		backend = appConfig.App.RuntimeBackend
		port = strconv.Itoa(appConfig.App.Port)
		redisURL = appConfig.Redis.URL
	} else {
		log.Printf("Warning: failed to load config from %s: %v", configPath, err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	var appSecrets *Secrets
	if cloudProvider == "gcp" {
		appSecrets, err = fetchSecretsGCP(ctx, gcpProjectID, gcpSecretID)
	} else {
		appSecrets, err = fetchSecretsAWS(ctx, secretNameAWS, awsRegion)
	}

	if err == nil {
		dbURL = appSecrets.DatabaseURL
		rabbitURL = appSecrets.RabbitMQURL
	} else {
		log.Printf("Warning: failed to fetch secrets from %s Secret Manager: %v", cloudProvider, err)
	}

	// Fallback to env vars if missing
	if backend == "" {
		backend = os.Getenv("RUNTIME_BACKEND")
		if backend == "" {
			backend = "external"
		}
	}
	if dbURL == "" {
		dbURL = os.Getenv("DATABASE_URL")
	}
	if port == "" || port == "0" {
		port = os.Getenv("PORT")
		if port == "" {
			port = "8080"
		}
	}

	srv := &Server{backend: backend}

	switch backend {
	case "postgres":
		if dbURL == "" {
			log.Fatal("DATABASE_URL is required when RUNTIME_BACKEND=postgres")
		}
		pool, err := pgxpool.New(context.Background(), dbURL)
		if err != nil {
			log.Fatalf("connect postgres: %v", err)
		}
		defer pool.Close()
		srv.db = pool
		srv.state = &postgresStateStore{db: pool}
		log.Println("Connected to PostgreSQL (postgres mode)")

	default: // "external" — current RabbitMQ + Redis behavior
		if rabbitURL == "" {
			rabbitURL = os.Getenv("RABBITMQ_URL")
			if rabbitURL == "" {
				rabbitURL = "amqp://guest:guest@localhost:5672/"
			}
		}
		conn := connectRabbitMQ(rabbitURL)
		defer conn.Close()
		ch, err := conn.Channel()
		if err != nil {
			log.Fatalf("open channel: %v", err)
		}
		defer ch.Close()
		if _, err := ch.QueueDeclare(queueName, true, false, false, false, nil); err != nil {
			log.Fatalf("declare queue: %v", err)
		}
		srv.ch = ch

		if redisURL == "" {
			redisURL = os.Getenv("REDIS_URL")
			if redisURL == "" {
				redisURL = "redis://localhost:6379/0"
			}
		}
		redisOpts, err := redis.ParseURL(redisURL)
		if err != nil {
			log.Fatalf("parse redis url: %v", err)
		}
		srv.rdb = redis.NewClient(redisOpts)
		srv.state = &redisStateStore{c: srv.rdb}
		pingCtx, pingCancel := context.WithTimeout(context.Background(), 3*time.Second)
		if pingErr := srv.rdb.Ping(pingCtx).Err(); pingErr != nil {
			log.Printf("Warning: Redis not reachable: %v — /state will return 503", pingErr)
		} else {
			log.Println("Connected to Redis")
		}
		pingCancel()
	}
	// Populate market cache immediately, then refresh independently of UI requests.
	go func() {
		srv.fetchAndUpdateMarkets()
		ticker := time.NewTicker(60 * time.Second)
		defer ticker.Stop()
		for range ticker.C {
			srv.fetchAndUpdateMarkets()
		}
	}()

	// Populate whale cache immediately, then refresh every 5 minutes.
	go func() {
		srv.fetchAndUpdateCache()
		ticker := time.NewTicker(5 * time.Minute)
		defer ticker.Stop()
		for range ticker.C {
			srv.fetchAndUpdateCache()
		}
	}()

	// Populate price cache immediately, then refresh every 60 seconds.
	// Binance public API: no key required, generous rate limits.
	go func() {
		srv.fetchAndUpdatePrices()
		ticker := time.NewTicker(60 * time.Second)
		defer ticker.Stop()
		for range ticker.C {
			srv.fetchAndUpdatePrices()
		}
	}()

	mux := http.NewServeMux()
	mux.HandleFunc("/health", corsMiddleware(srv.handleHealth))
	mux.HandleFunc("/current", corsMiddleware(srv.handleCurrent))
	mux.HandleFunc("/whales", corsMiddleware(srv.handleWhales))
	mux.HandleFunc("/prices", corsMiddleware(srv.handlePrices))
	mux.HandleFunc("/state", corsMiddlewareWithPost(srv.handleState))

	log.Printf("Proxy service listening on :%s", port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatalf("server: %v", err)
	}
}

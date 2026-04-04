package main

import (
	"context"
	"encoding/json"
	"fmt"
	"regexp"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"sync"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"
	"github.com/redis/go-redis/v9"
)

const (
	gammaBaseURL = "https://gamma-api.polymarket.com"
	dataBaseURL  = "https://data-api.polymarket.com"
	queueName    = "market_events"
)

const (
	coingeckoURL = "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum&vs_currencies=usd&include_24hr_change=true"
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

type cgPriceEntry struct {
	Usd          float64 `json:"usd"`
	Usd24hChange float64 `json:"usd_24h_change"`
}

type cgPriceResponse map[string]cgPriceEntry

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
	ch    *amqp.Channel
	chMu  sync.Mutex
	rdb   *redis.Client
	cache struct {
		sync.RWMutex
		whales []Whale
		prices Prices
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

func normalizeMarket(m GammaMarket) MarketSnapshot {
	yes, no := parseOutcomePrices(m.OutcomePrices)
	return MarketSnapshot{
		Slug:      m.Slug,
		Question:  m.Question,
		YesPrice:  yes,
		NoPrice:   no,
		Volume24h: toFloat(m.Volume24hr),
		Category:  m.Category,
		EndDate:   m.EndDateIso,
		FetchedAt: time.Now().UTC(),
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

func fetchCoinGecko() (cgPriceResponse, error) {
	var resp cgPriceResponse
	return resp, fetchJSON(coingeckoURL, &resp)
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

// ---- Whale cache refresh ----

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

	cg, err := fetchCoinGecko()
	if err != nil {
		log.Printf("Price update: CoinGecko fetch failed: %v", err)
		return
	}

	uah, err := fetchNBU()
	if err != nil {
		log.Printf("Price update: NBU fetch failed: %v", err)
		// Continue — crypto prices are still valid even if NBU is down
	}

	btc := cg["bitcoin"]
	eth := cg["ethereum"]

	prices := Prices{
		BtcUsd:       btc.Usd,
		EthUsd:       eth.Usd,
		Btc24hChange: btc.Usd24hChange,
		Eth24hChange: eth.Usd24hChange,
		UsdUah:       uah,
		FetchedAt:    now,
	}

	s.cache.Lock()
	s.cache.prices = prices
	s.cache.Unlock()

	// Publish price events to queue for persistence in PostgreSQL
	if err := s.publishPriceEvent("bitcoin", btc.Usd, btc.Usd24hChange, now); err != nil {
		log.Printf("Price publish failed (bitcoin): %v", err)
	}
	if err := s.publishPriceEvent("ethereum", eth.Usd, eth.Usd24hChange, now); err != nil {
		log.Printf("Price publish failed (ethereum): %v", err)
	}
	if uah > 0 {
		if err := s.publishPriceEvent("usd_uah", uah, 0, now); err != nil {
			log.Printf("Price publish failed (usd_uah): %v", err)
		}
	}

	log.Printf("Price cache updated: BTC=$%.0f ETH=$%.0f UAH=%.2f", btc.Usd, eth.Usd, uah)
}

// ---- HTTP handlers ----

func corsMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
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
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func (s *Server) handleCurrent(w http.ResponseWriter, r *http.Request) {
	markets, err := fetchMarkets()
	if err != nil {
		log.Printf("/current: fetch failed: %v", err)
		http.Error(w, "upstream fetch failed", http.StatusBadGateway)
		return
	}

	snapshots := make([]MarketSnapshot, 0, len(markets))
	for _, m := range markets {
		snap := normalizeMarket(m)
		if err := s.publish(snap); err != nil {
			log.Printf("/current: publish failed for %s: %v", snap.Slug, err)
		}
		snapshots = append(snapshots, snap)
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

	val, err := s.rdb.Get(ctx, "session:"+sid).Result()
	if err == redis.Nil {
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
	w.Write([]byte(val))
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

	if err := s.rdb.Set(ctx, "session:"+sid, string(body), 24*time.Hour).Err(); err != nil {
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

// ---- main ----

func main() {
	rabbitURL := os.Getenv("RABBITMQ_URL")
	if rabbitURL == "" {
		rabbitURL = "amqp://guest:guest@localhost:5672/"
	}
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
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

	srv := &Server{ch: ch}

	redisURL := os.Getenv("REDIS_URL")
	if redisURL == "" {
		redisURL = "redis://localhost:6379/0"
	}
	redisOpts, err := redis.ParseURL(redisURL)
	if err != nil {
		log.Fatalf("parse redis url: %v", err)
	}
	srv.rdb = redis.NewClient(redisOpts)

	// Verify Redis is reachable (non-fatal — state endpoints will return 503 if down)
	pingCtx, pingCancel := context.WithTimeout(context.Background(), 3*time.Second)
	if pingErr := srv.rdb.Ping(pingCtx).Err(); pingErr != nil {
		log.Printf("Warning: Redis not reachable: %v — /state will return 503", pingErr)
	} else {
		log.Println("Connected to Redis")
	}
	pingCancel()

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

package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"
)

const nbuBaseURL = "https://bank.gov.ua/NBUStatService/v1/statdirectory/exchange"

// kyivZone is UTC+3 — Ukraine permanently switched to EEST in 2022.
var kyivZone = time.FixedZone("Kyiv", 3*60*60)

func nbuURL() string {
	today := time.Now().In(kyivZone).Format("20060102")
	return fmt.Sprintf("%s?date=%s&json", nbuBaseURL, today)
}

type Rate struct {
	Code string  `json:"code"`
	Name string  `json:"name"`
	Rate float64 `json:"rate"`
	Date string  `json:"date"`
}

type nbuItem struct {
	CC           string  `json:"cc"`
	Txt          string  `json:"txt"`
	Rate         float64 `json:"rate"`
	ExchangeDate string  `json:"exchangedate"`
}

type rateEvent struct {
	FetchedAt string `json:"fetched_at"`
	Rates     []Rate `json:"rates"`
}

type mqClient struct {
	mu   sync.Mutex
	conn *amqp.Connection
	ch   *amqp.Channel
	url  string
}

func (c *mqClient) connect() error {
	conn, err := amqp.Dial(c.url)
	if err != nil {
		return fmt.Errorf("dial: %w", err)
	}

	ch, err := conn.Channel()
	if err != nil {
		conn.Close()
		return fmt.Errorf("channel: %w", err)
	}

	_, err = ch.QueueDeclare("rates.fetched", true, false, false, false, nil)
	if err != nil {
		ch.Close()
		conn.Close()
		return fmt.Errorf("queue declare: %w", err)
	}

	c.mu.Lock()
	c.conn = conn
	c.ch = ch
	c.mu.Unlock()
	return nil
}

func (c *mqClient) connectLoop() {
	backoff := time.Second
	for {
		err := c.connect()
		if err != nil {
			log.Printf("rabbitmq: connect failed: %v, retrying in %s", err, backoff)
			time.Sleep(backoff)
			if backoff < 30*time.Second {
				backoff *= 2
			}
			continue
		}
		backoff = time.Second
		log.Println("rabbitmq: connected, queue rates.fetched ready")

		closed := make(chan *amqp.Error, 1)
		c.mu.Lock()
		c.conn.NotifyClose(closed)
		c.mu.Unlock()
		<-closed
		log.Println("rabbitmq: connection lost, reconnecting...")
	}
}

func (c *mqClient) publish(body []byte) error {
	c.mu.Lock()
	ch := c.ch
	c.mu.Unlock()

	if ch == nil {
		return fmt.Errorf("no channel available")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	return ch.PublishWithContext(ctx, "", "rates.fetched", false, false, amqp.Publishing{
		ContentType: "application/json",
		Body:        body,
	})
}

var mq *mqClient

type rateCache struct {
	mu       sync.RWMutex
	rates    []Rate
	rateDate string
	cachedAt time.Time
}

var cache rateCache
var historyURL string

type historyRecord struct {
	Code     string  `json:"code"`
	Name     string  `json:"name"`
	Rate     float64 `json:"rate"`
	RateDate string  `json:"rate_date"`
}

func fetchFromHistory() ([]Rate, string, bool) {
	client := &http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get(historyURL + "/history?range=7d&limit=50")
	if err != nil {
		log.Printf("history-service: unreachable: %v", err)
		return nil, "", false
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, "", false
	}

	var records []historyRecord
	if err := json.NewDecoder(resp.Body).Decode(&records); err != nil || len(records) == 0 {
		return nil, "", false
	}

	latestDate := records[0].RateDate

	// Reject future dates — history DB may contain next-day rates stored
	// before the proxy was fixed to always request today's date from NBU.
	if parsed, err := time.ParseInLocation("02.01.2006", latestDate, kyivZone); err == nil {
		now := time.Now().In(kyivZone)
		today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, kyivZone)
		if parsed.After(today) {
			log.Printf("history-service: latest date %s is in the future, skipping", latestDate)
			return nil, "", false
		}
	}

	var rates []Rate
	for _, rec := range records {
		if rec.RateDate != latestDate {
			break
		}
		rates = append(rates, Rate{
			Code: rec.Code,
			Name: rec.Name,
			Rate: rec.Rate,
			Date: rec.RateDate,
		})
	}
	return rates, latestDate, true
}

func publishRates(rates []Rate) {
	if mq == nil {
		return
	}

	body, err := json.Marshal(rateEvent{
		FetchedAt: time.Now().UTC().Format(time.RFC3339),
		Rates:     rates,
	})
	if err != nil {
		log.Printf("rabbitmq: marshal error: %v", err)
		return
	}

	if err := mq.publish(body); err != nil {
		log.Printf("rabbitmq: publish error: %v", err)
	}
}

func corsMiddleware(allowedOrigins []string, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		for _, o := range allowedOrigins {
			if o == "*" || o == origin {
				w.Header().Set("Access-Control-Allow-Origin", origin)
				break
			}
		}
		w.Header().Set("Access-Control-Allow-Methods", "GET")
		w.Header().Set("Access-Control-Allow-Headers", "*")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next(w, r)
	}
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(`{"status":"ok"}`))
}

func ratesHandler(w http.ResponseWriter, r *http.Request) {
	ccFilter := strings.ToUpper(r.URL.Query().Get("cc"))

	// serve from cache if data is fresh (TTL: 1 hour)
	cache.mu.RLock()
	if cache.rateDate != "" && time.Since(cache.cachedAt) < time.Hour {
		rates := filterRates(cache.rates, ccFilter)
		cache.mu.RUnlock()
		log.Println("cache: serving cached rates")
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(rates)
		return
	}
	cache.mu.RUnlock()

	// try history-service first (data likely already in DB)
	if rates, date, ok := fetchFromHistory(); ok {
		log.Printf("cache: populated from history-service (date %s)", date)
		cache.mu.Lock()
		cache.rates = rates
		cache.rateDate = date
		cache.cachedAt = time.Now()
		cache.mu.Unlock()

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(filterRates(rates, ccFilter))
		return
	}

	// fallback: fetch full list from NBU
	resp, err := http.Get(nbuURL())
	if err != nil {
		http.Error(w, "failed to fetch NBU data", http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		http.Error(w, "failed to read NBU response", http.StatusInternalServerError)
		return
	}

	var raw []nbuItem
	if err := json.Unmarshal(body, &raw); err != nil {
		http.Error(w, "failed to parse NBU response", http.StatusInternalServerError)
		return
	}

	allRates := make([]Rate, len(raw))
	for i, item := range raw {
		allRates[i] = Rate{
			Code: item.CC,
			Name: item.Txt,
			Rate: item.Rate,
			Date: item.ExchangeDate,
		}
	}

	// update cache and conditionally publish
	var newDate string
	if len(raw) > 0 {
		newDate = raw[0].ExchangeDate
	}

	cache.mu.Lock()
	isNewDate := newDate != cache.rateDate
	cache.rates = allRates
	cache.rateDate = newDate
	cache.cachedAt = time.Now()
	cache.mu.Unlock()

	if isNewDate {
		log.Printf("cache: new rate date %s — publishing to queue", newDate)
		go publishRates(allRates)
	} else {
		log.Printf("cache: refreshed TTL for date %s — skipping publish", newDate)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(filterRates(allRates, ccFilter))
}

func filterRates(rates []Rate, cc string) []Rate {
	if cc == "" {
		return rates
	}
	filtered := make([]Rate, 0)
	for _, r := range rates {
		if r.Code == cc {
			filtered = append(filtered, r)
		}
	}
	return filtered
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8000"
	}

	originsEnv := os.Getenv("CORS_ORIGINS")
	if originsEnv == "" {
		originsEnv = "http://localhost:5000"
	}
	origins := strings.Split(originsEnv, ",")

	historyURL = os.Getenv("HISTORY_SERVICE_URL")
	if historyURL == "" {
		historyURL = "http://localhost:8001"
	}

	mqURL := os.Getenv("RABBITMQ_URL")
	if mqURL == "" {
		log.Fatal("RABBITMQ_URL environment variable is required")
	}
	mq = &mqClient{url: mqURL}
	go mq.connectLoop()

	mux := http.NewServeMux()
	mux.HandleFunc("/health", corsMiddleware(origins, healthHandler))
	mux.HandleFunc("/rates", corsMiddleware(origins, ratesHandler))

	addr := fmt.Sprintf(":%s", port)
	srv := &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
	log.Printf("api-proxy listening on %s", addr)

	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("listen: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("shutting down...")

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("forced shutdown: %v", err)
	}
	log.Println("stopped")
}

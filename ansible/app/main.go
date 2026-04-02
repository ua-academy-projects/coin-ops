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
	"os/signal"
	"path/filepath"
	"strings"
	"sync/atomic"
	"syscall"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"
)

const (
	defaultAPIURL      = "https://bank.gov.ua/NBUStatService/v1/statdirectory/exchange?json"
	defaultIntervalSec = 60
	defaultLogFile     = "logs/app.log"
	defaultQueueName   = "nbu.exchange.rates"

	defaultHTTPAddr = ":8080"
)

type NBUItem struct {
	R030         int     `json:"r030"`
	TXT          string  `json:"txt"`
	Rate         float64 `json:"rate"`
	CC           string  `json:"cc"`
	ExchangeDate string  `json:"exchangedate"`
}

type EnrichedNBUItem struct {
	R030         int       `json:"r030"`
	TXT          string    `json:"txt"`
	Rate         float64   `json:"rate"`
	CC           string    `json:"cc"`
	ExchangeDate string    `json:"exchangedate"`
	CollectedAt  time.Time `json:"collected_at"`
}

type Config struct {
	APIURL        string
	PollInterval  time.Duration
	LogFile       string
	RabbitURL     string
	RabbitQueue   string
	HTTPTimeout   time.Duration
	PublishMode   string // rabbit | stdout
	DryRun        bool
	HTTPAddr      string
	RabbitEnabled bool
}

type AppState struct {
	startedAt         time.Time
	lastSuccessUnix   atomic.Int64
	lastFailureUnix   atomic.Int64
	lastCollectUnix   atomic.Int64
	lastPublishedUnix atomic.Int64
}

func loadConfig() Config {
	publishMode := strings.ToLower(getenv("PUBLISH_MODE", "rabbit"))
	if publishMode != "rabbit" && publishMode != "stdout" {
		publishMode = "rabbit"
	}

	dryRun := getenvBool("DRY_RUN", false)
	rabbitURL := getenv("RABBITMQ_URL", "")

	cfg := Config{
		APIURL:        getenv("NBU_API_URL", defaultAPIURL),
		PollInterval:  time.Duration(getenvInt("POLL_INTERVAL_SECONDS", defaultIntervalSec)) * time.Second,
		LogFile:       getenv("LOG_FILE", defaultLogFile),
		RabbitURL:     rabbitURL,
		RabbitQueue:   getenv("RABBITMQ_QUEUE", defaultQueueName),
		HTTPTimeout:   time.Duration(getenvInt("HTTP_TIMEOUT_SECONDS", 15)) * time.Second,
		PublishMode:   publishMode,
		DryRun:        dryRun,
		HTTPAddr:      getenv("HTTP_ADDR", defaultHTTPAddr),
		RabbitEnabled: publishMode == "rabbit" && !dryRun && rabbitURL != "",
	}

	return cfg
}

func main() {
	cfg := loadConfig()

	logger, closer, err := newLogger(cfg.LogFile)
	if err != nil {
		log.Fatalf("failed to initialize logger: %v", err)
	}
	defer closer()

	state := &AppState{
		startedAt: time.Now().UTC(),
	}

	logger.Printf("service starting")
	logger.Printf("config: publish_mode=%s dry_run=%v http_addr=%s poll_interval=%s",
		cfg.PublishMode, cfg.DryRun, cfg.HTTPAddr, cfg.PollInterval)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	httpClient := &http.Client{
		Timeout: cfg.HTTPTimeout,
	}

	var rabbitConn *amqp.Connection
	var rabbitCh *amqp.Channel

	if cfg.RabbitEnabled {
		rabbitConn, rabbitCh, err = setupRabbitMQ(cfg, logger)
		if err != nil {
			logger.Fatalf("failed to setup RabbitMQ: %v", err)
		}
		defer rabbitCh.Close()
		defer rabbitConn.Close()
		logger.Printf("RabbitMQ enabled, queue=%s", cfg.RabbitQueue)
	} else {
		logger.Printf("RabbitMQ disabled")
		if cfg.DryRun {
			logger.Printf("reason: DRY_RUN=true")
		} else if cfg.PublishMode == "stdout" {
			logger.Printf("reason: PUBLISH_MODE=stdout")
		} else if cfg.RabbitURL == "" {
			logger.Printf("reason: RABBITMQ_URL is empty")
		}
	}

	server := startHTTPServer(cfg, state, logger)
	defer func() {
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := server.Shutdown(shutdownCtx); err != nil {
			logger.Printf("http server shutdown error: %v", err)
		}
	}()

	if err := collectAndProcess(ctx, cfg, httpClient, rabbitCh, logger, state); err != nil {
		state.lastFailureUnix.Store(time.Now().UTC().Unix())
		logger.Printf("initial collection failed: %v", err)
	}

	ticker := time.NewTicker(cfg.PollInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			logger.Printf("shutdown signal received, exiting")
			return
		case <-ticker.C:
			if err := collectAndProcess(ctx, cfg, httpClient, rabbitCh, logger, state); err != nil {
				state.lastFailureUnix.Store(time.Now().UTC().Unix())
				logger.Printf("collection failed: %v", err)
			}
		}
	}
}

func collectAndProcess(
	ctx context.Context,
	cfg Config,
	httpClient *http.Client,
	rabbitCh *amqp.Channel,
	logger *log.Logger,
	state *AppState,
) error {
	state.lastCollectUnix.Store(time.Now().UTC().Unix())
	logger.Printf("fetching data from NBU API: %s", cfg.APIURL)

	items, err := fetchNBUData(ctx, httpClient, cfg.APIURL)
	if err != nil {
		return fmt.Errorf("fetchNBUData: %w", err)
	}

	collectedAt := time.Now().UTC()
	enriched := enrichItems(items, collectedAt)

	logger.Printf("fetched %d exchange records, collected_at=%s", len(enriched), collectedAt.Format(time.RFC3339))

	switch cfg.PublishMode {
	case "stdout":
		if err := publishToStdout(enriched, logger); err != nil {
			return fmt.Errorf("publishToStdout: %w", err)
		}
		state.lastPublishedUnix.Store(time.Now().UTC().Unix())
		logger.Printf("published %d records to stdout", len(enriched))

	case "rabbit":
		if cfg.DryRun {
			logger.Printf("DRY_RUN enabled: RabbitMQ publish skipped")
			if err := publishToStdout(enriched, logger); err != nil {
				return fmt.Errorf("publishToStdout in dry-run: %w", err)
			}
			state.lastPublishedUnix.Store(time.Now().UTC().Unix())
			break
		}

		if rabbitCh == nil {
			return errors.New("rabbit channel is nil while publish mode is rabbit")
		}

		if err := publishBatchMessage(ctx, rabbitCh, cfg.RabbitQueue, enriched); err != nil {
			return fmt.Errorf("publishBatchMessage: %w", err)
		}
		state.lastPublishedUnix.Store(time.Now().UTC().Unix())
		logger.Printf("published 1 batch message with %d records to RabbitMQ queue=%s", len(enriched), cfg.RabbitQueue)

	default:
		return fmt.Errorf("unsupported publish mode: %s", cfg.PublishMode)
	}

	state.lastSuccessUnix.Store(time.Now().UTC().Unix())
	return nil
}

func fetchNBUData(ctx context.Context, client *http.Client, apiURL string) ([]NBUItem, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, apiURL, nil)
	if err != nil {
		return nil, err
	}

	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
		return nil, fmt.Errorf("unexpected status code %d: %s", resp.StatusCode, string(body))
	}

	var items []NBUItem
	if err := json.NewDecoder(resp.Body).Decode(&items); err != nil {
		return nil, err
	}

	return items, nil
}

func enrichItems(items []NBUItem, collectedAt time.Time) []EnrichedNBUItem {
	result := make([]EnrichedNBUItem, 0, len(items))
	for _, item := range items {
		result = append(result, EnrichedNBUItem{
			R030:         item.R030,
			TXT:          item.TXT,
			Rate:         item.Rate,
			CC:           item.CC,
			ExchangeDate: item.ExchangeDate,
			CollectedAt:  collectedAt,
		})
	}
	return result
}

func setupRabbitMQ(cfg Config, logger *log.Logger) (*amqp.Connection, *amqp.Channel, error) {
	conn, err := amqp.Dial(cfg.RabbitURL)
	if err != nil {
		return nil, nil, fmt.Errorf("amqp dial: %w", err)
	}

	ch, err := conn.Channel()
	if err != nil {
		conn.Close()
		return nil, nil, fmt.Errorf("open channel: %w", err)
	}

	_, err = ch.QueueDeclare(
		cfg.RabbitQueue,
		true,
		false,
		false,
		false,
		nil,
	)
	if err != nil {
		ch.Close()
		conn.Close()
		return nil, nil, fmt.Errorf("declare queue: %w", err)
	}

	logger.Printf("RabbitMQ connection established")
	return conn, ch, nil
}

func publishBatchMessage(ctx context.Context, ch *amqp.Channel, queue string, items []EnrichedNBUItem) error {
	body, err := json.Marshal(items)
	if err != nil {
		return err
	}

	pubCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	return ch.PublishWithContext(
		pubCtx,
		"",
		queue,
		false,
		false,
		amqp.Publishing{
			ContentType:  "application/json",
			DeliveryMode: amqp.Persistent,
			Timestamp:    time.Now().UTC(),
			Body:         body,
		},
	)
}

func publishToStdout(items []EnrichedNBUItem, logger *log.Logger) error {
	body, err := json.MarshalIndent(items, "", "  ")
	if err != nil {
		return err
	}

	logger.Printf("stdout publish payload:\n%s", string(body))
	return nil
}

func startHTTPServer(cfg Config, state *AppState, logger *log.Logger) *http.Server {
	mux := http.NewServeMux()

	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		lastSuccess := state.lastSuccessUnix.Load()

		status := http.StatusOK
		healthy := true
		message := "ok"

		if lastSuccess == 0 {
			healthy = false
			status = http.StatusServiceUnavailable
			message = "no successful collection yet"
		} else {
			lastSuccessTime := time.Unix(lastSuccess, 0).UTC()
			maxAge := cfg.PollInterval + 30*time.Second
			if time.Since(lastSuccessTime) > maxAge {
				healthy = false
				status = http.StatusServiceUnavailable
				message = "last successful collection is too old"
			}
		}

		resp := map[string]any{
			"status":             message,
			"healthy":            healthy,
			"started_at":         state.startedAt.Format(time.RFC3339),
			"publish_mode":       cfg.PublishMode,
			"dry_run":            cfg.DryRun,
			"rabbit_enabled":     cfg.RabbitEnabled,
			"last_collect_at":    unixToRFC3339(state.lastCollectUnix.Load()),
			"last_success_at":    unixToRFC3339(state.lastSuccessUnix.Load()),
			"last_failure_at":    unixToRFC3339(state.lastFailureUnix.Load()),
			"last_published_at":  unixToRFC3339(state.lastPublishedUnix.Load()),
			"poll_interval_sec":  int(cfg.PollInterval.Seconds()),
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		_ = json.NewEncoder(w).Encode(resp)
	})

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("nbu-collector is running\n"))
	})

	server := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	go func() {
		logger.Printf("HTTP server listening on %s", cfg.HTTPAddr)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Printf("HTTP server failed: %v", err)
		}
	}()

	return server
}

func unixToRFC3339(v int64) any {
	if v == 0 {
		return nil
	}
	return time.Unix(v, 0).UTC().Format(time.RFC3339)
}

func newLogger(logPath string) (*log.Logger, func(), error) {
	if logPath == "" {
		return nil, nil, errors.New("log file path is empty")
	}

	dir := filepath.Dir(logPath)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, nil, fmt.Errorf("create log dir: %w", err)
	}

	file, err := os.OpenFile(logPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return nil, nil, fmt.Errorf("open log file: %w", err)
	}

	mw := io.MultiWriter(os.Stdout, file)
	logger := log.New(mw, "[nbu-collector] ", log.LstdFlags|log.Lmicroseconds|log.LUTC)

	closeFn := func() {
		_ = file.Close()
	}

	return logger, closeFn, nil
}

func getenv(key, fallback string) string {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	return v
}

func getenvInt(key string, fallback int) int {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}

	var parsed int
	_, err := fmt.Sscanf(v, "%d", &parsed)
	if err != nil {
		return fallback
	}
	return parsed
}

func getenvBool(key string, fallback bool) bool {
	v := strings.TrimSpace(strings.ToLower(os.Getenv(key)))
	switch v {
	case "1", "true", "yes", "y", "on":
		return true
	case "0", "false", "no", "n", "off":
		return false
	default:
		return fallback
	}
}

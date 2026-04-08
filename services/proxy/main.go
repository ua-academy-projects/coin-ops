package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	cfg, err := LoadConfig()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	publisher, err := NewPublisher(cfg)
	if err != nil {
		log.Fatalf("publisher: %v", err)
	}
	defer func() {
		if err := publisher.Close(); err != nil {
			log.Printf("publisher close: %v", err)
		}
	}()

	agg := &rateAggregator{
		client:    newHTTPClient(),
		cfg:       cfg,
		cacheTTL:  cfg.CacheTTL,
		publisher: publisher,
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/api/v1/rates", agg.handleRates)
	mux.HandleFunc("/healthz", handleHealthz)

	handler := withRequestLog(withRecover(withCORS(cfg.CORSAllowOrigin, withSecurityHeaders(mux))))

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	if cfg.PollEnabled {
		log.Printf("background poll: every %v", cfg.PollInterval)
		go agg.runPollLoop(ctx, cfg.PollInterval)
	} else {
		log.Printf("background poll disabled")
	}

	srv := &http.Server{
		Addr:              cfg.Listen,
		Handler:           handler,
		ReadHeaderTimeout: 8 * time.Second,
		ReadTimeout:       60 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       120 * time.Second,
	}

	go func() {
		<-ctx.Done()
		log.Printf("shutting down...")
		shutCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = srv.Shutdown(shutCtx)
	}()

	log.Printf("CoinOps proxy listening on %s (cache TTL %v)", cfg.Listen, cfg.CacheTTL)
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatal(err)
	}
}

func handleHealthz(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	_, _ = w.Write([]byte(`{"status":"ok","service":"proxy"}`))
}

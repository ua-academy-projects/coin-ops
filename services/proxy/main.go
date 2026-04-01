package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strconv"
	"sync"
	"time"

	"golang.org/x/sync/errgroup"
)

// defaultListen is the bind address when COINOPS_LISTEN is unset.
const defaultListen = ":8080"

// defaultCacheTTL is used when COINOPS_CACHE_TTL_SECONDS is unset or invalid.
const defaultCacheTTL = 60 * time.Second

// defaultPollInterval is the background fetch interval when COINOPS_POLL_INTERVAL_SECONDS is unset or invalid.
const defaultPollInterval = 10 * time.Minute

// cachedEntry holds a successful aggregated snapshot for in-memory TTL caching.
// We only cache responses where both NBU and CoinGecko succeeded, to avoid serving
// stale partial data after a transient outage of one provider.
type cachedEntry struct {
	resp      *RatesResponse
	expiresAt time.Time
}

// rateAggregator holds HTTP client and cache state for GET /api/v1/rates.
type rateAggregator struct {
	client    *http.Client
	mu        sync.RWMutex
	cache     *cachedEntry
	cacheTTL  time.Duration
	publisher RatePublisher
}

// BuildRatesResponse fetches both sources in parallel, merges rates, and builds the API payload.
// This function is independent of http.ResponseWriter so the same snapshot can later be
// published to a message queue (Phase 2) without changing fetchers.
func BuildRatesResponse(ctx context.Context, client *http.Client) *RatesResponse {
	if client == nil {
		client = newHTTPClient()
	}
	var fiat, crypto []Rate
	var nbuErr, coingeckoErr error
	g, gctx := errgroup.WithContext(ctx)
	g.Go(func() error {
		r, err := FetchNBU(gctx, client)
		if err != nil {
			nbuErr = err
			return nil // partial failure: still return crypto if available
		}
		fiat = r
		return nil
	})
	g.Go(func() error {
		r, err := FetchCoinGecko(gctx, client)
		if err != nil {
			coingeckoErr = err
			return nil
		}
		crypto = r
		return nil
	})
	_ = g.Wait()
	out := &RatesResponse{
		FetchedAt: time.Now().UTC(),
		Rates:     append(append([]Rate(nil), fiat...), crypto...),
	}
	if nbuErr != nil || coingeckoErr != nil {
		out.Errors = make(map[string]string)
		if nbuErr != nil {
			out.Errors["nbu"] = nbuErr.Error()
		}
		if coingeckoErr != nil {
			out.Errors["coingecko"] = coingeckoErr.Error()
		}
	}
	return out
}

func (a *rateAggregator) getOrFetch(ctx context.Context) *RatesResponse {
	now := time.Now()
	a.mu.RLock()
	ent := a.cache
	a.mu.RUnlock()
	if ent != nil && now.Before(ent.expiresAt) {
		return ent.resp
	}
	return a.refreshFromUpstream(ctx)
}

// refreshFromUpstream always calls NBU + CoinGecko and refreshes the in-memory cache on full success.
func (a *rateAggregator) refreshFromUpstream(ctx context.Context) *RatesResponse {
	resp := BuildRatesResponse(ctx, a.client)
	now := time.Now()
	// Cache only full success to keep CoinGecko request rate predictable and avoid
	// caching incomplete snapshots during provider outages.
	if len(resp.Errors) == 0 && len(resp.Rates) > 0 {
		snap := *resp
		snap.Rates = append([]Rate(nil), resp.Rates...)
		snap.Errors = nil
		a.mu.Lock()
		a.cache = &cachedEntry{resp: &snap, expiresAt: now.Add(a.cacheTTL)}
		a.mu.Unlock()
		return &snap
	}
	return resp
}

func (a *rateAggregator) publishSnapshotAsync(resp RatesResponse) {
	go func(snapshot RatesResponse) {
		pubCtx, pubCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer pubCancel()
		if err := a.publisher.Publish(pubCtx, snapshot); err != nil {
			log.Printf("publish snapshot failed: %v", err)
		}
	}(resp)
}

func (a *rateAggregator) pollAndPublish(ctx context.Context) {
	resp := a.refreshFromUpstream(ctx)
	a.publishSnapshotAsync(*resp)
}

func listenAddr() string {
	if v := os.Getenv("COINOPS_LISTEN"); v != "" {
		return v
	}
	return defaultListen
}

func cacheTTL() time.Duration {
	s := os.Getenv("COINOPS_CACHE_TTL_SECONDS")
	if s == "" {
		return defaultCacheTTL
	}
	sec, err := strconv.Atoi(s)
	if err != nil || sec <= 0 {
		return defaultCacheTTL
	}
	return time.Duration(sec) * time.Second
}

func pollEnabled() bool {
	v := os.Getenv("COINOPS_POLL_ENABLED")
	if v == "" {
		return true
	}
	return v == "1" || v == "true" || v == "TRUE" || v == "yes" || v == "YES"
}

func pollInterval() time.Duration {
	s := os.Getenv("COINOPS_POLL_INTERVAL_SECONDS")
	if s == "" {
		return defaultPollInterval
	}
	sec, err := strconv.Atoi(s)
	if err != nil || sec <= 0 {
		return defaultPollInterval
	}
	return time.Duration(sec) * time.Second
}

func main() {
	publisher, err := NewPublisherFromEnv()
	if err != nil {
		log.Fatalf("publisher init failed: %v", err)
	}
	defer func() {
		if err := publisher.Close(); err != nil {
			log.Printf("publisher close: %v", err)
		}
	}()

	agg := &rateAggregator{
		client:    newHTTPClient(),
		cacheTTL:  cacheTTL(),
		publisher: publisher,
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/api/v1/rates", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
		defer cancel()
		resp := agg.getOrFetch(ctx)
		// Best-effort async publish: live API response must not fail if MQ is down.
		agg.publishSnapshotAsync(*resp)
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		enc := json.NewEncoder(w)
		enc.SetEscapeHTML(true)
		if err := enc.Encode(resp); err != nil {
			log.Printf("encode response: %v", err)
		}
	})
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	if pollEnabled() {
		iv := pollInterval()
		log.Printf("background rate poll: every %v (COINOPS_POLL_INTERVAL_SECONDS)", iv)
		go func() {
			ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
			agg.pollAndPublish(ctx)
			cancel()
			t := time.NewTicker(iv)
			defer t.Stop()
			for range t.C {
				ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
				agg.pollAndPublish(ctx)
				cancel()
			}
		}()
	} else {
		log.Printf("background rate poll disabled (COINOPS_POLL_ENABLED)")
	}

	addr := listenAddr()
	log.Printf("CoinOps proxy listening on %s (cache TTL %v)", addr, agg.cacheTTL)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatal(err)
	}
}

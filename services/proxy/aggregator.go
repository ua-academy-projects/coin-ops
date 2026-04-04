package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"sync"
	"time"

	"golang.org/x/sync/errgroup"
)

type cachedEntry struct {
	resp      *RatesResponse
	expiresAt time.Time
}

type rateAggregator struct {
	client    *http.Client
	mu        sync.RWMutex
	cache     *cachedEntry
	cacheTTL  time.Duration
	publisher RatePublisher
}

func (a *rateAggregator) buildResponse(ctx context.Context) *RatesResponse {
	var fiat, crypto []Rate
	var nbuErr, coingeckoErr error

	g, gctx := errgroup.WithContext(ctx)
	g.Go(func() error {
		r, err := FetchNBU(gctx, a.client)
		if err != nil {
			nbuErr = err
			return nil
		}
		fiat = r
		return nil
	})
	g.Go(func() error {
		r, err := FetchCoinGecko(gctx, a.client)
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
	// encoding/json marshals nil []Rate as "rates":null; Python history service expects a JSON array.
	if out.Rates == nil {
		out.Rates = []Rate{}
	}
	return out
}

// getOrFetch returns the cached response if valid, or fetches fresh data.
// The second return value indicates whether the response came from cache.
func (a *rateAggregator) getOrFetch(ctx context.Context) (*RatesResponse, bool) {
	now := time.Now()
	a.mu.RLock()
	ent := a.cache
	a.mu.RUnlock()
	if ent != nil && now.Before(ent.expiresAt) {
		return ent.resp, true
	}
	return a.refreshFromUpstream(ctx), false
}

// refreshFromUpstream always calls NBU + CoinGecko; caches only on full success
// to avoid serving stale partial data during provider outages.
func (a *rateAggregator) refreshFromUpstream(ctx context.Context) *RatesResponse {
	resp := a.buildResponse(ctx)
	if len(resp.Errors) == 0 && len(resp.Rates) > 0 {
		snap := *resp
		snap.Rates = append([]Rate(nil), resp.Rates...)
		snap.Errors = nil
		a.mu.Lock()
		a.cache = &cachedEntry{resp: &snap, expiresAt: time.Now().Add(a.cacheTTL)}
		a.mu.Unlock()
		return &snap
	}
	return resp
}

func (a *rateAggregator) publishAsync(resp RatesResponse) {
	go func(snapshot RatesResponse) {
		defer func() {
			if rec := recover(); rec != nil {
				log.Printf("publish panic: %v", rec)
			}
		}()
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		if err := a.publisher.Publish(ctx, snapshot); err != nil {
			log.Printf("publish failed: %v", err)
		}
	}(resp)
}

// runPollLoop fetches + publishes immediately, then on every tick until ctx is cancelled.
func (a *rateAggregator) runPollLoop(ctx context.Context, interval time.Duration) {
	defer func() {
		if rec := recover(); rec != nil {
			log.Printf("poll loop panic: %v", rec)
		}
	}()

	a.pollOnce(ctx)

	t := time.NewTicker(interval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			a.pollOnce(ctx)
		}
	}
}

func (a *rateAggregator) pollOnce(ctx context.Context) {
	defer func() {
		if rec := recover(); rec != nil {
			log.Printf("poll tick panic: %v", rec)
		}
	}()
	fetchCtx, cancel := context.WithTimeout(ctx, 45*time.Second)
	defer cancel()
	resp := a.refreshFromUpstream(fetchCtx)
	a.publishAsync(*resp)
}

// handleRates serves GET /api/v1/rates. Publishes to MQ only on cache miss
// to avoid flooding the queue with stale duplicates.
func (a *rateAggregator) handleRates(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 45*time.Second)
	defer cancel()

	resp, fromCache := a.getOrFetch(ctx)
	if !fromCache {
		a.publishAsync(*resp)
	}

	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	if err := json.NewEncoder(w).Encode(resp); err != nil {
		log.Printf("encode response: %v", err)
	}
}

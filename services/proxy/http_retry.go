package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"
)

const (
	maxUpstreamRetries  = 5
	initialRetryBackoff = 350 * time.Millisecond
	maxRetryBackoff     = 12 * time.Second
)

// fetchURL performs an idempotent GET with exponential backoff on 429 / 5xx and transient network errors.
func fetchURL(ctx context.Context, client *http.Client, url string) ([]byte, error) {
	if client == nil {
		client = http.DefaultClient
	}
	backoff := initialRetryBackoff
	var lastErr error

	for attempt := 1; attempt <= maxUpstreamRetries; attempt++ {
		if err := ctx.Err(); err != nil {
			return nil, err
		}

		req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
		if err != nil {
			return nil, err
		}

		res, err := client.Do(req)
		if err != nil {
			lastErr = err
			if attempt >= maxUpstreamRetries || !retriableRoundTripError(err) {
				return nil, fmt.Errorf("request: %w", err)
			}
			if wait(ctx, backoff) != nil {
				return nil, ctx.Err()
			}
			backoff = min(backoff*2, maxRetryBackoff)
			continue
		}

		body, err := io.ReadAll(res.Body)
		_ = res.Body.Close()
		if err != nil {
			return nil, fmt.Errorf("read body: %w", err)
		}

		if res.StatusCode == http.StatusOK {
			return body, nil
		}

		lastErr = fmt.Errorf("http status %d: %s", res.StatusCode, strings.TrimSpace(string(truncateRunes(body, 512))))
		if attempt >= maxUpstreamRetries || !retriableHTTPStatus(res.StatusCode) {
			return nil, lastErr
		}

		delay := max(backoff, retryAfterFromHeader(res.Header, backoff))
		if wait(ctx, delay) != nil {
			return nil, ctx.Err()
		}
		backoff = min(backoff*2, maxRetryBackoff)
	}
	return nil, lastErr
}

func retriableHTTPStatus(code int) bool {
	switch code {
	case http.StatusTooManyRequests,
		http.StatusInternalServerError,
		http.StatusBadGateway,
		http.StatusServiceUnavailable,
		http.StatusGatewayTimeout:
		return true
	default:
		return false
	}
}

func retriableRoundTripError(err error) bool {
	if errors.Is(err, context.Canceled) {
		return false
	}
	// DeadlineExceeded: often upstream slowness; safe to retry idempotent GET within cap.
	return true
}

func retryAfterFromHeader(h http.Header, fallback time.Duration) time.Duration {
	raw := strings.TrimSpace(h.Get("Retry-After"))
	if raw == "" {
		return fallback
	}
	if sec, err := strconv.Atoi(raw); err == nil && sec >= 0 {
		return min(time.Duration(sec)*time.Second, 2*time.Minute)
	}
	if t, err := http.ParseTime(raw); err == nil {
		d := time.Until(t)
		if d > 0 && d < 2*time.Minute {
			return d
		}
	}
	return fallback
}

func wait(ctx context.Context, d time.Duration) error {
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-time.After(d):
		return nil
	}
}

func truncateRunes(b []byte, maxBytes int) []byte {
	if len(b) <= maxBytes {
		return b
	}
	return b[:maxBytes]
}

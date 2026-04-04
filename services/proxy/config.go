package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

const (
	defaultListen       = ":8080"
	defaultCacheTTL     = 60 * time.Second
	defaultPollInterval = 10 * time.Minute
	defaultMQExchange   = "coinops.rates"
	defaultMQRoutingKey = "rates.snapshot"
)

// Config holds all runtime settings for the proxy service, loaded once at startup.
// Mirrors the HistoryConfig / AppConfig pattern used by history_service and frontend.
type Config struct {
	Listen          string
	CacheTTL        time.Duration
	PollEnabled     bool
	PollInterval    time.Duration
	MQEnabled       bool
	MQURL           string
	MQExchange      string
	MQRoutingKey    string
	CORSAllowOrigin string
}

// LoadConfig reads environment variables and returns a validated Config.
func LoadConfig() (*Config, error) {
	cfg := &Config{
		Listen:          envString("COINOPS_LISTEN", defaultListen),
		CacheTTL:        envDurationSec("COINOPS_CACHE_TTL_SECONDS", defaultCacheTTL),
		PollEnabled:     envBool("COINOPS_POLL_ENABLED", true),
		PollInterval:    envDurationSec("COINOPS_POLL_INTERVAL_SECONDS", defaultPollInterval),
		MQEnabled:       envBool("MQ_ENABLED", false),
		MQURL:           envString("RABBITMQ_URL", ""),
		MQExchange:      envString("RABBITMQ_EXCHANGE", defaultMQExchange),
		MQRoutingKey:    envString("RABBITMQ_ROUTING_KEY", defaultMQRoutingKey),
		CORSAllowOrigin: strings.TrimSpace(os.Getenv("COINOPS_CORS_ALLOW_ORIGIN")),
	}
	if cfg.MQEnabled && cfg.MQURL == "" {
		return nil, fmt.Errorf("MQ_ENABLED=true but RABBITMQ_URL is empty")
	}
	return cfg, nil
}

func envString(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// envBool parses a boolean-like env var. Consistent with history_service's _env_bool.
func envBool(key string, fallback bool) bool {
	v := strings.TrimSpace(strings.ToLower(os.Getenv(key)))
	if v == "" {
		return fallback
	}
	switch v {
	case "1", "true", "yes", "on":
		return true
	case "0", "false", "no", "off":
		return false
	default:
		return fallback
	}
}

func envDurationSec(key string, fallback time.Duration) time.Duration {
	s := os.Getenv(key)
	if s == "" {
		return fallback
	}
	sec, err := strconv.Atoi(s)
	if err != nil || sec <= 0 {
		return fallback
	}
	return time.Duration(sec) * time.Second
}

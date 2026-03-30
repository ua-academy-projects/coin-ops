// Package main is the CoinOps HTTP proxy for VM2: it aggregates fiat (NBU) and
// crypto (CoinGecko) rates behind GET /api/v1/rates, with optional in-memory TTL caching
// in main.go to limit upstream call rate.
package main

import "time"

// Rate is a single normalized exchange-rate row returned by GET /api/v1/rates
// and stored by the worker in PostgreSQL.
type Rate struct {
	// AssetSymbol is the short ticker (e.g. USD, EUR, BTC).
	AssetSymbol string `json:"asset_symbol"`
	// AssetType is either "fiat" (NBU) or "crypto" (CoinGecko).
	AssetType string `json:"asset_type"`
	// PriceUAH is the NBU official rate in UAH per one unit of foreign currency, when applicable.
	PriceUAH *float64 `json:"price_uah"`
	// PriceUSD is the price in USD (CoinGecko for crypto; derived from NBU for fiat via USD/UAH cross).
	PriceUSD *float64 `json:"price_usd"`
	// Source identifies the upstream API: "nbu" or "coingecko".
	Source string `json:"source"`
	// Name is the human-readable asset name from NBU (optional; empty for crypto).
	Name string `json:"name,omitempty"`
}

// RatesResponse is the top-level JSON body for GET /api/v1/rates.
type RatesResponse struct {
	Rates     []Rate            `json:"rates"`
	FetchedAt time.Time         `json:"fetched_at"`
	Errors    map[string]string `json:"errors,omitempty"`
}

// nbuRow is one element from the NBU statdirectory JSON array.
type nbuRow struct {
	R030         int     `json:"r030"`
	Txt          string  `json:"txt"`
	Rate         float64 `json:"rate"`
	CC           string  `json:"cc"`
	ExchangeDate string  `json:"exchangedate"`
	Special      *string `json:"special"`
}

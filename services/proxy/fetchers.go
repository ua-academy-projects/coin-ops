package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"sort"
	"strings"
	"time"
)

const (
	nbuURL       = "https://bank.gov.ua/NBUStatService/v1/statdirectory/exchange?json"
	coinGeckoURL = "https://api.coingecko.com/api/v3/simple/price?ids=%s&vs_currencies=usd"
	// coinGeckoIDs lists public CoinGecko asset ids for the MVP (order preserved for stable output).
	coinGeckoIDs = "bitcoin,ethereum,cardano,solana,ripple"
)

// coingeckoSymbol maps CoinGecko id to display symbol (uppercase ticker).
var coingeckoSymbol = map[string]string{
	"bitcoin":  "BTC",
	"ethereum": "ETH",
	"cardano":  "ADA",
	"solana":   "SOL",
	"ripple":   "XRP",
}

// FetchNBU downloads NBU official exchange JSON and maps each row to Rate.
// Business rule: NBU "rate" is UAH per 1 unit of currency (cc). We derive price_usd
// using the USD row: for any currency C, price_usd(C) = rate(C) / rate(USD); for USD, price_usd = 1.
func FetchNBU(ctx context.Context, client *http.Client) ([]Rate, error) {
	if client == nil {
		client = http.DefaultClient
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, nbuURL, nil)
	if err != nil {
		return nil, err
	}
	res, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(res.Body, 2048))
		return nil, fmt.Errorf("nbu: status %d: %s", res.StatusCode, strings.TrimSpace(string(body)))
	}
	body, err := io.ReadAll(res.Body)
	if err != nil {
		return nil, err
	}
	var rows []nbuRow
	if err := json.Unmarshal(body, &rows); err != nil {
		return nil, fmt.Errorf("nbu json: %w", err)
	}
	var usdPerUAH float64 // UAH per 1 USD from NBU (same as rate for USD row)
	for _, r := range rows {
		if strings.EqualFold(r.CC, "USD") {
			usdPerUAH = r.Rate
			break
		}
	}
	if usdPerUAH <= 0 {
		return nil, fmt.Errorf("nbu: missing or invalid USD rate")
	}
	out := make([]Rate, 0, len(rows))
	for _, r := range rows {
		uah := r.Rate
		var usd *float64
		if strings.EqualFold(r.CC, "USD") {
			one := 1.0
			usd = &one
		} else {
			v := uah / usdPerUAH
			usd = &v
		}
		out = append(out, Rate{
			AssetSymbol: strings.ToUpper(strings.TrimSpace(r.CC)),
			AssetType:   "fiat",
			PriceUAH:    &uah,
			PriceUSD:    usd,
			Source:      "nbu",
			Name:        r.Txt,
		})
	}
	return out, nil
}

// FetchCoinGecko downloads simple USD prices for configured crypto ids.
func FetchCoinGecko(ctx context.Context, client *http.Client) ([]Rate, error) {
	if client == nil {
		client = http.DefaultClient
	}
	url := fmt.Sprintf(coinGeckoURL, coinGeckoIDs)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	res, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(res.Body, 2048))
		return nil, fmt.Errorf("coingecko: status %d: %s", res.StatusCode, strings.TrimSpace(string(body)))
	}
	body, err := io.ReadAll(res.Body)
	if err != nil {
		return nil, err
	}
	// Dynamic keys: {"bitcoin":{"usd":123.45}, ...}
	var raw map[string]map[string]float64
	if err := json.Unmarshal(body, &raw); err != nil {
		return nil, fmt.Errorf("coingecko json: %w", err)
	}
	out := make([]Rate, 0, len(raw))
	for id, prices := range raw {
		sym, ok := coingeckoSymbol[id]
		if !ok {
			sym = strings.ToUpper(id)
		}
		usdVal, ok := prices["usd"]
		if !ok {
			continue
		}
		u := usdVal
		out = append(out, Rate{
			AssetSymbol: sym,
			AssetType:   "crypto",
			PriceUAH:    nil,
			PriceUSD:    &u,
			Source:      "coingecko",
		})
	}
	// Stable order regardless of JSON map iteration (helps UI and tests).
	sort.Slice(out, func(i, j int) bool { return out[i].AssetSymbol < out[j].AssetSymbol })
	return out, nil
}

// newHTTPClient returns an HTTP client with bounded timeouts suitable for upstream APIs.
func newHTTPClient() *http.Client {
	return &http.Client{Timeout: 25 * time.Second}
}

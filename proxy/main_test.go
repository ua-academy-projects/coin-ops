package main

import (
	"encoding/json"
	"testing"
	"time"
)

func TestParseOutcomePrices(t *testing.T) {
	tests := []struct {
		name       string
		raw        string
		expectYes  float64
		expectNo   float64
	}{
		{
			name:      "Direct JSON array",
			raw:       `["0.62", "0.38"]`,
			expectYes: 0.62,
			expectNo:  0.38,
		},
		{
			name:      "Stringified JSON array",
			raw:       `"[\"0.65\",\"0.35\"]"`,
			expectYes: 0.65,
			expectNo:  0.35,
		},
		{
			name:      "Single array element",
			raw:       `["0.99"]`,
			expectYes: 0.99,
			expectNo:  0.0,
		},
		{
			name:      "Invalid input",
			raw:       `"invalid"`,
			expectYes: 0.0,
			expectNo:  0.0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			yes, no := parseOutcomePrices(json.RawMessage(tt.raw))
			if yes != tt.expectYes || no != tt.expectNo {
				t.Errorf("got %v, %v; expected %v, %v", yes, no, tt.expectYes, tt.expectNo)
			}
		})
	}
}

func TestNormalizeMarket(t *testing.T) {
	m := GammaMarket{
		Question:      "Will Bitcoin reach $100k?",
		Slug:          "btc-100k",
		OutcomePrices: json.RawMessage(`["0.75", "0.25"]`),
		Volume24hr:    "12345.67",
		EndDateIso:    "2026-06-30T23:59:00Z",
		Category:      "Crypto",
	}

	fetchedAt := time.Now().UTC()
	snap := normalizeMarket(m, fetchedAt)

	if snap.Slug != "btc-100k" {
		t.Errorf("Slug: got %v, want %v", snap.Slug, "btc-100k")
	}
	if snap.Question != "Will Bitcoin reach $100k?" {
		t.Errorf("Question: got %v, want %v", snap.Question, "Will Bitcoin reach $100k?")
	}
	if snap.YesPrice != 0.75 {
		t.Errorf("YesPrice: got %v, want %v", snap.YesPrice, 0.75)
	}
	if snap.NoPrice != 0.25 {
		t.Errorf("NoPrice: got %v, want %v", snap.NoPrice, 0.25)
	}
	if snap.Volume24h != 12345.67 {
		t.Errorf("Volume24h: got %v, want %v", snap.Volume24h, 12345.67)
	}
	if snap.Category != "Crypto" {
		t.Errorf("Category: got %v, want %v", snap.Category, "Crypto")
	}
	if snap.EndDate != "2026-06-30T23:59:00Z" {
		t.Errorf("EndDate: got %v, want %v", snap.EndDate, "2026-06-30T23:59:00Z")
	}
	if snap.FetchedAt != fetchedAt {
		t.Errorf("FetchedAt: got %v, want %v", snap.FetchedAt, fetchedAt)
	}
}

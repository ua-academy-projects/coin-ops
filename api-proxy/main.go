package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
)

const nbuURL = "https://bank.gov.ua/NBUStatService/v1/statdirectory/exchange?json"

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
	url := nbuURL
	if cc := r.URL.Query().Get("cc"); cc != "" {
		url += "&valcode=" + strings.ToUpper(cc)
	}

	resp, err := http.Get(url)
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

	rates := make([]Rate, len(raw))
	for i, item := range raw {
		rates[i] = Rate{
			Code: item.CC,
			Name: item.Txt,
			Rate: item.Rate,
			Date: item.ExchangeDate,
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(rates)
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

	mux := http.NewServeMux()
	mux.HandleFunc("/health", corsMiddleware(origins, healthHandler))
	mux.HandleFunc("/rates", corsMiddleware(origins, ratesHandler))

	addr := fmt.Sprintf(":%s", port)
	log.Printf("api-proxy listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, mux))
}

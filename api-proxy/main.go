package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"
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

type rateEvent struct {
	FetchedAt string `json:"fetched_at"`
	Rates     []Rate `json:"rates"`
}

var mqChannel *amqp.Channel

func connectRabbitMQ(url string) {
	conn, err := amqp.Dial(url)
	if err != nil {
		log.Printf("rabbitmq: connection failed (running without queue): %v", err)
		return
	}

	ch, err := conn.Channel()
	if err != nil {
		log.Printf("rabbitmq: channel failed: %v", err)
		conn.Close()
		return
	}

	_, err = ch.QueueDeclare("rates.fetched", true, false, false, false, nil)
	if err != nil {
		log.Printf("rabbitmq: queue declare failed: %v", err)
		ch.Close()
		conn.Close()
		return
	}

	mqChannel = ch
	log.Println("rabbitmq: connected, queue rates.fetched ready")
}

func publishRates(rates []Rate) {
	if mqChannel == nil {
		return
	}

	body, err := json.Marshal(rateEvent{
		FetchedAt: time.Now().UTC().Format(time.RFC3339),
		Rates:     rates,
	})
	if err != nil {
		log.Printf("rabbitmq: marshal error: %v", err)
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	err = mqChannel.PublishWithContext(ctx, "", "rates.fetched", false, false, amqp.Publishing{
		ContentType: "application/json",
		Body:        body,
	})
	if err != nil {
		log.Printf("rabbitmq: publish error: %v", err)
	}
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

	go publishRates(rates)
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

	mqURL := os.Getenv("RABBITMQ_URL")
	if mqURL == "" {
		mqURL = "amqp://guest:guest@localhost:5672/"
	}
	connectRabbitMQ(mqURL)

	mux := http.NewServeMux()
	mux.HandleFunc("/health", corsMiddleware(origins, healthHandler))
	mux.HandleFunc("/rates", corsMiddleware(origins, ratesHandler))

	addr := fmt.Sprintf(":%s", port)
	log.Printf("api-proxy listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, mux))
}

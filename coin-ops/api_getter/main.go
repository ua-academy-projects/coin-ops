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

// RateMessage is the payload published to RabbitMQ.
type RateMessage struct {
	CurrencyCode string  `json:"currency_code"`
	CurrencyName string  `json:"currency_name"`
	Source       string  `json:"source"`
	Rate         float64 `json:"rate"`
	BaseCurrency string  `json:"base_currency"`
	FetchedAt    string  `json:"fetched_at"`
}

// ── CoinGecko ────────────────────────────────────────────────────────────────

var cryptoCoins = map[string]string{
	"bitcoin":  "BTC",
	"ethereum": "ETH",
	"solana":   "SOL",
	"ripple":   "XRP",
	"cardano":  "ADA",
	"dogecoin": "DOGE",
}

type coinGeckoResp map[string]map[string]float64

func fetchCoinGecko() ([]RateMessage, error) {
	ids := strings.Join(mapKeys(cryptoCoins), ",")
	url := fmt.Sprintf(
		"https://api.coingecko.com/api/v3/simple/price?ids=%s&vs_currencies=usd,uah,eur",
		ids,
	)

	resp, err := http.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)

	var data coinGeckoResp
	if err := json.Unmarshal(body, &data); err != nil {
		return nil, fmt.Errorf("parse coingecko: %w (body: %s)", err, body[:min(len(body), 200)])
	}

	now := time.Now().UTC().Format(time.RFC3339)
	var msgs []RateMessage
	for coinID, prices := range data {
		symbol, ok := cryptoCoins[coinID]
		if !ok {
			continue
		}
		for currency, price := range prices {
			msgs = append(msgs, RateMessage{
				CurrencyCode: symbol,
				CurrencyName: coinID,
				Source:       "coingecko",
				Rate:         price,
				BaseCurrency: strings.ToUpper(currency),
				FetchedAt:    now,
			})
		}
	}
	return msgs, nil
}

// ── NBU (National Bank of Ukraine) ───────────────────────────────────────────

type nbuRate struct {
	CC   string  `json:"cc"`
	Rate float64 `json:"rate"`
	Txt  string  `json:"txt"`
}

var nbuFilter = map[string]bool{
	"USD": true, "EUR": true, "GBP": true,
	"PLN": true, "CHF": true, "JPY": true,
	"CZK": true, "HUF": true,
}

func fetchNBU() ([]RateMessage, error) {
	resp, err := http.Get("https://bank.gov.ua/NBU_Exchange/exchange_site?json")
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)

	var rates []nbuRate
	if err := json.Unmarshal(body, &rates); err != nil {
		return nil, fmt.Errorf("parse nbu: %w", err)
	}

	now := time.Now().UTC().Format(time.RFC3339)
	var msgs []RateMessage
	for _, r := range rates {
		if !nbuFilter[r.CC] {
			continue
		}
		msgs = append(msgs, RateMessage{
			CurrencyCode: r.CC,
			CurrencyName: r.Txt,
			Source:       "nbu",
			Rate:         r.Rate,
			BaseCurrency: "UAH",
			FetchedAt:    now,
		})
	}
	return msgs, nil
}

// ── RabbitMQ helpers ─────────────────────────────────────────────────────────

func connectRabbitMQ(url string) (*amqp.Connection, *amqp.Channel, error) {
	conn, err := amqp.Dial(url)
	if err != nil {
		return nil, nil, err
	}
	ch, err := conn.Channel()
	if err != nil {
		conn.Close()
		return nil, nil, err
	}
	if err := ch.ExchangeDeclare("rates", "fanout", true, false, false, false, nil); err != nil {
		ch.Close()
		conn.Close()
		return nil, nil, err
	}
	return conn, ch, nil
}

func publish(ch *amqp.Channel, msgs []RateMessage) {
	for _, msg := range msgs {
		body, _ := json.Marshal(msg)
		err := ch.PublishWithContext(
			context.Background(),
			"rates", "", false, false,
			amqp.Publishing{
				ContentType:  "application/json",
				DeliveryMode: amqp.Persistent,
				Body:         body,
			},
		)
		if err != nil {
			log.Printf("[publish error] %v", err)
		} else {
			log.Printf("[%s] %s/%s = %.6f", msg.Source, msg.CurrencyCode, msg.BaseCurrency, msg.Rate)
		}
	}
}

func fetchAndPublish(ch *amqp.Channel) {
	log.Println("--- Fetching CoinGecko ---")
	if msgs, err := fetchCoinGecko(); err != nil {
		log.Printf("[coingecko error] %v", err)
	} else {
		publish(ch, msgs)
		log.Printf("[coingecko] published %d rates", len(msgs))
	}

	log.Println("--- Fetching NBU ---")
	if msgs, err := fetchNBU(); err != nil {
		log.Printf("[nbu error] %v", err)
	} else {
		publish(ch, msgs)
		log.Printf("[nbu] published %d rates", len(msgs))
	}
}

// ── Main ─────────────────────────────────────────────────────────────────────

func main() {
	rabbitmqURL := os.Getenv("RABBITMQ_URL")
	if rabbitmqURL == "" {
		rabbitmqURL = "amqp://coinops:coinops123@localhost:5672/"
	}

	interval := 20 * time.Minute
	if s := os.Getenv("FETCH_INTERVAL"); s != "" {
		if d, err := time.ParseDuration(s); err == nil {
			interval = d
		}
	}

	var conn *amqp.Connection
	var ch *amqp.Channel
	var err error

	for i := 1; i <= 30; i++ {
		conn, ch, err = connectRabbitMQ(rabbitmqURL)
		if err == nil {
			break
		}
		log.Printf("RabbitMQ not ready (%d/30): %v — retrying in 5s", i, err)
		time.Sleep(5 * time.Second)
	}
	if err != nil {
		log.Fatalf("Cannot connect to RabbitMQ: %v", err)
	}
	defer conn.Close()
	defer ch.Close()

	log.Printf("Connected. Fetch interval: %s", interval)
	fetchAndPublish(ch)

	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for range ticker.C {
		if conn.IsClosed() {
			log.Println("Reconnecting to RabbitMQ...")
			conn, ch, err = connectRabbitMQ(rabbitmqURL)
			if err != nil {
				log.Printf("Reconnect failed: %v", err)
				continue
			}
		}
		fetchAndPublish(ch)
	}
}

// ── Utils ────────────────────────────────────────────────────────────────────

func mapKeys(m map[string]string) []string {
	ks := make([]string, 0, len(m))
	for k := range m {
		ks = append(ks, k)
	}
	return ks
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

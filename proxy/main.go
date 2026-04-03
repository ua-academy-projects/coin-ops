package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"

	amqp "github.com/rabbitmq/amqp091-go"
)

type Rate struct {
	CC   string  `json:"cc"`
	Txt  string  `json:"txt"`
	Rate float64 `json:"rate"`
}

var rabbitConn *amqp.Connection
var rabbitChannel *amqp.Channel

func connectRabbitMQ() {
	// Підключаємось до RabbitMQ на VM4
	conn, err := amqp.Dial("amqp://coinops:coinops123@192.168.56.104:5672/")
	if err != nil {
		log.Printf("Помилка підключення до RabbitMQ: %s", err)
		return
	}
	rabbitConn = conn

	ch, err := conn.Channel()
	if err != nil {
		log.Printf("Помилка відкриття каналу: %s", err)
		return
	}
	rabbitChannel = ch

	// Створюємо чергу якщо не існує
	ch.QueueDeclare("rates", false, false, false, false, nil)
	log.Println("Підключено до RabbitMQ")
}

func publishToQueue(rates []Rate) {
	if rabbitChannel == nil {
		log.Println("RabbitMQ не підключений")
		return
	}

	// Конвертуємо в JSON
	body, err := json.Marshal(rates)
	if err != nil {
		log.Printf("Помилка конвертації: %s", err)
		return
	}

	// Публікуємо в чергу
	err = rabbitChannel.Publish(
		"",      // exchange
		"rates", // queue name
		false,
		false,
		amqp.Publishing{
			ContentType: "application/json",
			Body:        body,
		},
	)
	if err != nil {
		log.Printf("Помилка публікації: %s", err)
		return
	}
	log.Println("Повідомлення відправлено в чергу")
}

func getRates(w http.ResponseWriter, r *http.Request) {
	// Йдемо до НБУ API
	resp, err := http.Get("https://bank.gov.ua/NBUStatService/v1/statdirectory/exchange?json")
	if err != nil {
		http.Error(w, "Помилка запиту до НБУ", http.StatusInternalServerError)
		return
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		http.Error(w, "Помилка читання", http.StatusInternalServerError)
		return
	}

	var allRates []Rate
	json.Unmarshal(body, &allRates)

    filtered := allRates

	// Публікуємо в RabbitMQ асинхронно
	go publishToQueue(filtered)

	// Повертаємо дані Flask
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(filtered)
}

func main() {
	// Підключаємось до RabbitMQ при старті
	connectRabbitMQ()

	http.HandleFunc("/rates", getRates)
	fmt.Println("Проксі сервіс запущено на порту 8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}

type CryptoRate struct {
	CC   string  `json:"cc"`
	Txt  string  `json:"txt"`
	Rate float64 `json:"rate"`
}

func getCrypto(w http.ResponseWriter, r *http.Request) {
	resp, err := http.Get("https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum&vs_currencies=uah")
	if err != nil {
		http.Error(w, "Помилка запиту до CoinGecko", http.StatusInternalServerError)
		return
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		http.Error(w, "Помилка читання", http.StatusInternalServerError)
		return
	}

	// CoinGecko повертає: {"bitcoin":{"uah":123},"ethereum":{"uah":456}}
	var raw map[string]map[string]float64
	json.Unmarshal(body, &raw)

	var result []CryptoRate
	if btc, ok := raw["bitcoin"]; ok {
		result = append(result, CryptoRate{
			CC:   "BTC",
			Txt:  "Bitcoin",
			Rate: btc["uah"],
		})
	}
	if eth, ok := raw["ethereum"]; ok {
		result = append(result, CryptoRate{
			CC:   "ETH",
			Txt:  "Ethereum",
			Rate: eth["uah"],
		})
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}

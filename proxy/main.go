package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"
)
type Rate struct {
	CC   string  `json:"cc"`
	Txt  string  `json:"txt"`
	Rate float64 `json:"rate"`
}

type CryptoRate struct {
	CC   string  `json:"cc"`
	Txt  string  `json:"txt"`
	Rate float64 `json:"rate"`
}

var rabbitConn *amqp.Connection
var rabbitChannel *amqp.Channel

func connectRabbitMQ() {
	for {
		conn, err := amqp.Dial("amqp://coinops:coinops123@192.168.56.104:5672/")
		if err != nil {
			log.Printf("RabbitMQ не підключений, спробую знову через 5 секунд...")
			time.Sleep(5 * time.Second)
			continue
		}
		rabbitConn = conn

		ch, err := conn.Channel()
		if err != nil {
			log.Printf("Помилка каналу, спробую знову...")
			time.Sleep(5 * time.Second)
			continue
		}
		rabbitChannel = ch
		ch.QueueDeclare("rates", false, false, false, false, nil)
		log.Println("Підключено до RabbitMQ")
		return
	}
}

func publishToQueue(rates []Rate) {
	if rabbitChannel == nil {
		log.Println("RabbitMQ не підключений")
		return
	}

	body, err := json.Marshal(rates)
	if err != nil {
		log.Printf("Помилка конвертації: %s", err)
		return
	}

	err = rabbitChannel.Publish(
		"",
		"rates",
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

	// Публікуємо всі валюти в RabbitMQ асинхронно
	go publishToQueue(allRates)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(allRates)
}

var cryptoCache []CryptoRate
var cryptoCacheTime time.Time

func getCrypto(w http.ResponseWriter, r *http.Request) {
	// Якщо кеш свіжий (менше 60 секунд) — повертаємо його
	if time.Since(cryptoCacheTime) < 60*time.Second && len(cryptoCache) > 0 {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(cryptoCache)
		return
	}

	resp, err := http.Get("https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,solana,binancecoin,cardano,ripple,dogecoin,polkadot,avalanche-2,chainlink&vs_currencies=uah")
	if err != nil {
		// Якщо помилка але є кеш — повертаємо кеш
		if len(cryptoCache) > 0 {
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(cryptoCache)
			return
		}
		http.Error(w, "Помилка запиту до CoinGecko", http.StatusInternalServerError)
		return
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		http.Error(w, "Помилка читання", http.StatusInternalServerError)
		return
	}

	var raw map[string]map[string]float64
	json.Unmarshal(body, &raw)

	if len(raw) == 0 {
		// CoinGecko повернув порожньо (rate limit) — повертаємо кеш
		if len(cryptoCache) > 0 {
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(cryptoCache)
			return
		}
	}

	names := map[string]string{
		"bitcoin": "Bitcoin", "ethereum": "Ethereum", "solana": "Solana",
		"binancecoin": "BNB", "cardano": "Cardano", "ripple": "XRP",
		"dogecoin": "Dogecoin", "polkadot": "Polkadot", "avalanche-2": "Avalanche",
		"chainlink": "Chainlink",
	}
	codes := map[string]string{
		"bitcoin": "BTC", "ethereum": "ETH", "solana": "SOL",
		"binancecoin": "BNB", "cardano": "ADA", "ripple": "XRP",
		"dogecoin": "DOGE", "polkadot": "DOT", "avalanche-2": "AVAX",
		"chainlink": "LINK",
	}

	var result []CryptoRate
	for id, data := range raw {
		result = append(result, CryptoRate{
			CC:   codes[id],
			Txt:  names[id],
			Rate: data["uah"],
		})
	}

	// Зберігаємо в кеш
	cryptoCache = result
	cryptoCacheTime = time.Now()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}
func main() {
	go connectRabbitMQ()

	http.HandleFunc("/rates", getRates)
	http.HandleFunc("/crypto", getCrypto)

	fmt.Println("Проксі сервіс запущено на порту 8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}

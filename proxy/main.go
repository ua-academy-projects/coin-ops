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

var cryptoCache []CryptoRate
var cryptoCacheTime time.Time

var cryptoNames = map[string]string{
	"bitcoin": "Bitcoin", "ethereum": "Ethereum", "solana": "Solana",
	"binancecoin": "BNB", "cardano": "Cardano", "ripple": "XRP",
	"dogecoin": "Dogecoin", "polkadot": "Polkadot", "avalanche-2": "Avalanche",
	"chainlink": "Chainlink",
}

var cryptoCodes = map[string]string{
	"bitcoin": "BTC", "ethereum": "ETH", "solana": "SOL",
	"binancecoin": "BNB", "cardano": "ADA", "ripple": "XRP",
	"dogecoin": "DOGE", "polkadot": "DOT", "avalanche-2": "AVAX",
	"chainlink": "LINK",
}

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
	err = rabbitChannel.Publish("", "rates", false, false,
		amqp.Publishing{ContentType: "application/json", Body: body},
	)
	if err != nil {
		log.Printf("Помилка публікації: %s", err)
		return
	}
	log.Println("Повідомлення відправлено в чергу")
}

func fetchNBU() []Rate {
	resp, err := http.Get("https://bank.gov.ua/NBUStatService/v1/statdirectory/exchange?json")
	if err != nil {
		log.Printf("Помилка НБУ: %s", err)
		return nil
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil
	}
	var rates []Rate
	json.Unmarshal(body, &rates)
	return rates
}

func fetchCryptoRates() []Rate {
	resp, err := http.Get("https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,solana,binancecoin,cardano,ripple,dogecoin,polkadot,avalanche-2,chainlink&vs_currencies=uah")
	if err != nil {
		log.Printf("Помилка CoinGecko: %s", err)
		return nil
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil
	}
	var raw map[string]map[string]float64
	json.Unmarshal(body, &raw)
	if len(raw) == 0 {
		return nil
	}
	var result []Rate
	for id, data := range raw {
		result = append(result, Rate{
			CC:   cryptoCodes[id],
			Txt:  cryptoNames[id],
			Rate: data["uah"],
		})
	}
	return result
}

// autoRefresh — кожні 5 хвилин автоматично отримує дані і публікує в чергу
func autoRefresh() {
	for {
		log.Println("Автооновлення: отримуємо курси...")

		// НБУ
		nbuRates := fetchNBU()
		if len(nbuRates) > 0 {
			publishToQueue(nbuRates)
			log.Printf("Автооновлення: опубліковано %d валют НБУ", len(nbuRates))
		}

		// Крипта
		time.Sleep(2 * time.Second) // невелика пауза між запитами
		cryptoRates := fetchCryptoRates()
		if len(cryptoRates) > 0 {
			publishToQueue(cryptoRates)
			// Оновлюємо кеш
			var cr []CryptoRate
			for _, r := range cryptoRates {
				cr = append(cr, CryptoRate{CC: r.CC, Txt: r.Txt, Rate: r.Rate})
			}
			cryptoCache = cr
			cryptoCacheTime = time.Now()
			log.Printf("Автооновлення: опубліковано %d крипто курсів", len(cryptoRates))
		}

		time.Sleep(5 * time.Minute)
	}
}

func getRates(w http.ResponseWriter, r *http.Request) {
	rates := fetchNBU()
	if rates == nil {
		http.Error(w, "Помилка запиту до НБУ", http.StatusInternalServerError)
		return
	}
	// Також публікуємо при запиті юзера
	go publishToQueue(rates)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(rates)
}

func getCrypto(w http.ResponseWriter, r *http.Request) {
	// Якщо кеш свіжий (менше 60 секунд) — повертаємо його
	if time.Since(cryptoCacheTime) < 60*time.Second && len(cryptoCache) > 0 {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(cryptoCache)
		return
	}

	cryptoRates := fetchCryptoRates()
	if cryptoRates == nil {
		if len(cryptoCache) > 0 {
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(cryptoCache)
			return
		}
		http.Error(w, "Помилка CoinGecko", http.StatusInternalServerError)
		return
	}

	// Публікуємо в чергу і оновлюємо кеш
	go publishToQueue(cryptoRates)
	var cr []CryptoRate
	for _, r := range cryptoRates {
		cr = append(cr, CryptoRate{CC: r.CC, Txt: r.Txt, Rate: r.Rate})
	}
	cryptoCache = cr
	cryptoCacheTime = time.Now()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(cryptoCache)
}

func main() {
	go connectRabbitMQ()

	// Запускаємо автооновлення кожні 5 хвилин
	go autoRefresh()

	http.HandleFunc("/rates", getRates)
	http.HandleFunc("/crypto", getCrypto)

	fmt.Println("Проксі сервіс запущено на порту 8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}

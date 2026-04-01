package main

import (
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"os"
	"encoding/json"
	"time"
	"strings"	// every lib should be used in the code, otherwise it will be error
	"github.com/streadway/amqp"	// to work with rabbitmq

	_ "github.com/lib/pq"

)


var db *sql.DB

type Price struct {
	Coin      string  `json:"coin"`
	Price float64 `json:"price"`
    RecordedAt  string  `json:"recorded_at"`	//`

}


func connectDB() *sql.DB{
	host := getEnv("POSTGRES_HOST", "localhost")
	dbname := getEnv("POSTGRES_DB", "currency_rates_tracker")
	user := getEnv("POSTGRES_USER", "currency_app_user")
	password := getEnv("POSTGRES_PASS", "password")

	connStr := fmt.Sprintf(
		"host=%s dbname=%s user=%s password=%s sslmode=disable",
		host, dbname, user, password,
	)	// set value without printing

	db, err := sql.Open("postgres", connStr)	// if not db set value as error
	if err != nil {		// if error is present
		log.Fatalf("DB connection error: %v", err)
	}	

	_, err = db.Exec(`
		CREATE TABLE IF NOT EXISTS currency_rates (
			id SERIAL PRIMARY KEY,
			coin	VARCHAR(10) NOT NULL,
			price NUMERIC(15, 2) NOT NULL,
			recorded_at TIMESTAMP DEFAULT NOW()
		)
	`)

	if err != nil {
        log.Fatalf("Failed to create table: %v", err)
    }

    log.Println("DB connected, table ready")

	return db
}

func saveToDB(coin string, price float64) {
	_, err := db.Exec(
		"INSERT INTO currency_rates (coin, price) VALUES ($1, $2)", coin, price,
	)	// we only need err, _ - omits the result of exec
	// $1 placeholder for coin value, $2 for price value
	if err != nil {
		log.Printf("DB insert error: %v", err)
		return
	}
	log.Printf("Saved to DB: %s = %f", coin, price)
}

func startWorker() {
	host := getEnv("RABBITMQ_HOST", "localhost")
	user := getEnv("RABBITMQ_USER", "currency_app_user")
	password := getEnv("RABBITMQ_PASS", "password")
	queue := getEnv("RABBITMQ_QUEUE", "currency_rates")

	for {
		url := fmt.Sprintf("amqp://%s:%s@%s:5672/", user, password, host)
		conn, err := amqp.Dial(url)	// connect to rabbitmq server
		if err != nil {
			log.Printf("RabbitMQ error: %v", err)
			time.Sleep(5 * time.Second)
			continue
		}
	
		ch, err := conn.Channel()
		if err != nil {
			log.Printf("Channel error: %v", err)
			conn.Close()
			time.Sleep(5 * time.Second)
			continue
		}
	
		q, err := ch.QueueDeclare(queue, true, false, false, false, nil)
		if err != nil {
			log.Printf("Queue error: %v", err)
			continue
		}
	// nil = None
	// consume msgs from the queue (queue, tag, auto-acknowledge, exclusive, nolocal, notwait, args)
		msgs, err := ch.Consume(q.Name, "", false, false, false, false, nil)
		if err != nil {
			log.Printf("Consume error: %v", err)
			continue
		}

		log.Println("Worker started")

		for msg := range msgs {
			var data map[string]interface{} // {"key": 54.45}
			// unmarshal json -> map(dict) (json.loads())
			// 1) asign value to err 2) check err != nil
			if err := json.Unmarshal(msg.Body, &data); err != nil {
				log.Printf("JSON error: %v", err)
				// multiple, requeue
				// error occured - do not acknowledge msg - return it to queue
				msg.Nack(false, false)
				continue // skip the lower code and move to the next msg
			}
			price := data["price"].(float64)
			coin, ok := data["coin"].(string)	// if not coin - then data=ok
			if !ok || coin == "" {	// if not ok or coin is empty
				coin = "BTC"
			}
			log.Printf("Received: %s = %f", coin, price)
			saveToDB(coin, price)
				// save to db and remove from queue
			msg.Ack(false)
		}

		conn.Close()
		time.Sleep(5 * time.Second)
	}
}

func historyHandler(w http.ResponseWriter, r *http.Request) {
	rows, err := db.Query(
		"SELECT coin, price, recorded_at FROM currency_rates ORDER BY recorded_at DESC",
	)	
	if err != nil {
		http.Error(w, "DB error", http.StatusInternalServerError)
		return
	}
	defer rows.Close()
	
	// SHOW VALUES FROM DB IN JSON FORMAT 5002
	var prices []Price	
	for rows.Next() {	// iterate through sql data request rows
		var p Price
		var t time.Time // type of time
		if err := rows.Scan(&p.Coin, &p.Price, &t); err != nil {
			continue
		}
		p.RecordedAt = t.Format("2006-01-02 15:04:05")
		prices = append(prices, p)
	}

	if prices == nil {
		prices = []Price{}
	}
	w.Header().Set("Content-Type", "application/json") // set header to json
	// map - {} string key type interface any type {'key': value}
	// convert data from json to map and send to client
	json.NewEncoder(w).Encode(map[string]interface{}{	
		"data": prices,
	})
}

// stats (highest, lowest) value
type Stats struct {
	Highest_Price float64 `json:"highest_price"`
	Lowest_Price  float64 `json:"lowest_price"`
}

func statsHandler(w http.ResponseWriter, r *http.Request) {
	// get coin from query params default - BTC
	coin := strings.ToUpper(r.URL.Query().Get("coin"))
	if coin == "" {
		coin = "BTC"
	}

	var stats Stats
	err := db.QueryRow(
		"SELECT MAX(price), MIN(price) FROM currency_rates WHERE coin = $1", coin,
	).Scan(&stats.Highest_Price, &stats.Lowest_Price)

	if err != nil {
		http.Error(w, "DB error", http.StatusInternalServerError)
		return
	}

	// return data to client in json format
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(stats)
}

func getEnv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func main() {
	db = connectDB()
	defer db.Close()	// will be completed after all commands in the end

	go startWorker()

	http.HandleFunc("/history", historyHandler)
	log.Println("History service is running on port 5002")
	// activate stats handler for /stats endpoint
	http.HandleFunc("/stats", statsHandler)
	// after listenandserver no rows will be executed
	log.Fatal(http.ListenAndServe("0.0.0.0:5002", nil))
	
}	


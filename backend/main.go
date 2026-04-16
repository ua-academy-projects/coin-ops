package main

import (
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/redis/go-redis/v9"
	"github.com/streadway/amqp"
	"context"
)

var ctx = context.Background()

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}

func main() {
	rabbitmqURL := getEnv("RABBIT_URL", "")
	redisURL := getEnv("REDIS_URL", "localhost:6379")

	// Redis connection
	rdb := redis.NewClient(&redis.Options{
		Addr: redisURL,
	})

	var conn *amqp.Connection
	var err error

	log.Println("Connecting to RabbitMQ...")
	for {
		conn, err = amqp.Dial(rabbitmqURL)
		if err == nil {
			break
		}
		log.Printf("Failed to connect to RabbitMQ: %v. Retrying in 5 seconds...", err)
		time.Sleep(5 * time.Second)
	}
	defer conn.Close()

	ch, err := conn.Channel()
	if err != nil {
		log.Fatal(err)
	}
	defer ch.Close()

	q, err := ch.QueueDeclare(
		"weather_data",
		false, false, false, false, nil,
	)
	if err != nil {
		log.Fatal(err)
	}

	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}

		if r.URL.Path == "/history" {
			historyURL := "http://history:8000/history"
			resp, err := http.Get(historyURL)
			if err != nil {
				log.Printf("Failed to fetch history: %v", err)
				http.Error(w, "Failed to fetch history from service", http.StatusInternalServerError)
				return
			}
			defer resp.Body.Close()

			body, _ := ioutil.ReadAll(resp.Body)
			w.Header().Set("Content-Type", "application/json")
			w.Write(body)
			return
		}

		if r.URL.Path != "/weather" {
			http.NotFound(w, r)
			return
		}

		w.Header().Set("Content-Type", "application/json")

		lat := r.URL.Query().Get("lat")
		lon := r.URL.Query().Get("lon")
		if lat == "" || lon == "" {
			lat = "50.4501"
			lon = "30.5234"
		}

		cacheKey := fmt.Sprintf("weather:%s:%s", lat, lon)

		// Check Redis cache
		cachedData, err := rdb.Get(ctx, cacheKey).Bytes()
		if err == nil {
			log.Println("Returning cached data from Redis...")
			w.Write(cachedData)
			return
		}

		log.Println("Fetching from Open-Meteo API...")
		apiURL := fmt.Sprintf(
			"https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&current_weather=true&daily=temperature_2m_max,temperature_2m_min,windspeed_10m_max&timezone=auto",
			lat, lon,
		)

		resp, err := http.Get(apiURL)
		if err != nil {
			http.Error(w, "Failed to fetch weather from API", http.StatusInternalServerError)
			return
		}
		defer resp.Body.Close()

		body, _ := ioutil.ReadAll(resp.Body)

		// Save to Redis with 5 minute expiration
		err = rdb.Set(ctx, cacheKey, body, 5*time.Minute).Err()
		if err != nil {
			log.Printf("Failed to save to Redis: %v", err)
		}

		// Відправляємо дані в RabbitMQ для оновлення історії
		err = ch.Publish(
			"", q.Name, false, false,
			amqp.Publishing{
				ContentType: "application/json",
				Body:        body,
			},
		)
		if err != nil {
			log.Printf("Failed to publish to RabbitMQ: %v", err)
		}

		w.Write(body)
	})

	log.Println("Weather proxy running on :8080")
	log.Fatal(http.ListenAndServe(":8080", handler))
}

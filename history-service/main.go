package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	_ "github.com/lib/pq"
	amqp "github.com/rabbitmq/amqp091-go"
)

// --- shared types ---

type Rate struct {
	Code string  `json:"code"`
	Name string  `json:"name"`
	Rate float64 `json:"rate"`
	Date string  `json:"date"`
}

type rateEvent struct {
	FetchedAt string `json:"fetched_at"`
	Rates     []Rate `json:"rates"`
}

type historyRecord struct {
	ID        int64   `json:"id"`
	Code      string  `json:"code"`
	Name      string  `json:"name"`
	Rate      float64 `json:"rate"`
	RateDate  string  `json:"rate_date"`
	FetchedAt string  `json:"fetched_at"`
}

// --- consumer ---

func startConsumer(mqURL string, db *sql.DB) {
	conn, err := amqp.Dial(mqURL)
	if err != nil {
		log.Fatalf("rabbitmq: failed to connect: %v", err)
	}

	ch, err := conn.Channel()
	if err != nil {
		log.Fatalf("rabbitmq: failed to open channel: %v", err)
	}

	_, err = ch.QueueDeclare("rates.fetched", true, false, false, false, nil)
	if err != nil {
		log.Fatalf("rabbitmq: failed to declare queue: %v", err)
	}

	msgs, err := ch.Consume("rates.fetched", "", false, false, false, false, nil)
	if err != nil {
		log.Fatalf("rabbitmq: failed to start consumer: %v", err)
	}

	log.Println("rabbitmq: consumer started, waiting for messages")

	for msg := range msgs {
		var event rateEvent
		if err := json.Unmarshal(msg.Body, &event); err != nil {
			log.Printf("consumer: failed to parse message: %v", err)
			msg.Nack(false, false)
			continue
		}

		fetchedAt, err := time.Parse(time.RFC3339, event.FetchedAt)
		if err != nil {
			log.Printf("consumer: invalid fetched_at: %v", err)
			msg.Nack(false, false)
			continue
		}

		tx, err := db.Begin()
		if err != nil {
			log.Printf("consumer: failed to begin tx: %v", err)
			msg.Nack(false, true)
			continue
		}

		failed := false
		for _, r := range event.Rates {
			_, err := tx.Exec(
				`INSERT INTO rate_history (code, name, rate, rate_date, fetched_at) VALUES ($1, $2, $3, $4, $5)`,
				r.Code, r.Name, r.Rate, r.Date, fetchedAt,
			)
			if err != nil {
				log.Printf("consumer: insert failed: %v", err)
				failed = true
				break
			}
		}

		if failed {
			tx.Rollback()
			msg.Nack(false, true)
			continue
		}

		if err := tx.Commit(); err != nil {
			log.Printf("consumer: commit failed: %v", err)
			msg.Nack(false, true)
			continue
		}

		log.Printf("consumer: stored %d rates fetched at %s", len(event.Rates), event.FetchedAt)
		msg.Ack(false)
	}
}

// --- HTTP handlers ---

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

func makeHistoryHandler(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// parse ?cc=USD,EUR (comma-separated)
		ccParam := r.URL.Query().Get("cc")
		var codes []string
		if ccParam != "" {
			for _, c := range strings.Split(ccParam, ",") {
				c = strings.TrimSpace(strings.ToUpper(c))
				if c != "" {
					codes = append(codes, c)
				}
			}
		}

		// parse ?range=7d|30d|90d|6m|1y|all (default 30d)
		rangeParam := r.URL.Query().Get("range")
		var since time.Time
		switch rangeParam {
		case "7d":
			since = time.Now().UTC().AddDate(0, 0, -7)
		case "90d":
			since = time.Now().UTC().AddDate(0, 0, -90)
		case "6m":
			since = time.Now().UTC().AddDate(0, -6, 0)
		case "1y":
			since = time.Now().UTC().AddDate(-1, 0, 0)
		case "all":
			since = time.Time{} // zero = no filter
		default: // 30d
			since = time.Now().UTC().AddDate(0, 0, -30)
		}

		// parse ?limit=N (default 500, max 5000)
		limit := 500
		if lp := r.URL.Query().Get("limit"); lp != "" {
			fmt.Sscanf(lp, "%d", &limit)
			if limit > 5000 {
				limit = 5000
			}
			if limit < 1 {
				limit = 1
			}
		}

		// build query dynamically
		args := []interface{}{}
		conditions := []string{}
		argIdx := 1

		if len(codes) > 0 {
			placeholders := make([]string, len(codes))
			for i, c := range codes {
				placeholders[i] = fmt.Sprintf("$%d", argIdx)
				args = append(args, c)
				argIdx++
			}
			conditions = append(conditions, fmt.Sprintf("code IN (%s)", strings.Join(placeholders, ",")))
		}

		if !since.IsZero() {
			conditions = append(conditions, fmt.Sprintf("fetched_at >= $%d", argIdx))
			args = append(args, since)
			argIdx++
		}

		query := `SELECT id, code, name, rate, rate_date, fetched_at FROM rate_history`
		if len(conditions) > 0 {
			query += " WHERE " + strings.Join(conditions, " AND ")
		}
		query += fmt.Sprintf(" ORDER BY fetched_at DESC, id DESC LIMIT $%d", argIdx)
		args = append(args, limit)

		rows, err := db.Query(query, args...)
		if err != nil {
			log.Printf("history query error: %v", err)
			http.Error(w, "query failed", http.StatusInternalServerError)
			return
		}
		defer rows.Close()

		records := []historyRecord{}
		for rows.Next() {
			var rec historyRecord
			var fetchedAt time.Time
			if err := rows.Scan(&rec.ID, &rec.Code, &rec.Name, &rec.Rate, &rec.RateDate, &fetchedAt); err != nil {
				log.Printf("history scan error: %v", err)
				continue
			}
			rec.FetchedAt = fetchedAt.UTC().Format(time.RFC3339)
			records = append(records, rec)
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(records)
	}
}

// --- main ---

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8001"
	}

	originsEnv := os.Getenv("CORS_ORIGINS")
	if originsEnv == "" {
		originsEnv = "http://localhost:5000"
	}
	origins := strings.Split(originsEnv, ",")

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = "postgres://coinops:coinops@localhost:5432/coinops?sslmode=disable"
	}

	mqURL := os.Getenv("RABBITMQ_URL")
	if mqURL == "" {
		mqURL = "amqp://guest:guest@localhost:5672/"
	}

	db, err := sql.Open("postgres", dbURL)
	if err != nil {
		log.Fatalf("db: failed to open: %v", err)
	}
	defer db.Close()

	if err := db.Ping(); err != nil {
		log.Fatalf("db: failed to connect: %v", err)
	}
	log.Println("db: connected")

	go startConsumer(mqURL, db)

	mux := http.NewServeMux()
	mux.HandleFunc("/health", corsMiddleware(origins, healthHandler))
	mux.HandleFunc("/history", corsMiddleware(origins, makeHistoryHandler(db)))

	addr := fmt.Sprintf(":%s", port)
	log.Printf("history-service listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, mux))
}

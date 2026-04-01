package main

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"sync"
	"time"

	"github.com/google/uuid"
	amqp "github.com/rabbitmq/amqp091-go"
)

const (
	defaultMQExchange   = "coinops.rates"
	defaultMQRoutingKey = "rates.snapshot"
)

// RatePublisher publishes normalized snapshots to an asynchronous transport.
type RatePublisher interface {
	Publish(ctx context.Context, payload RatesResponse) error
	Close() error
}

// NoopPublisher is used when MQ is disabled.
type NoopPublisher struct{}

func (n *NoopPublisher) Publish(_ context.Context, _ RatesResponse) error { return nil }
func (n *NoopPublisher) Close() error                                     { return nil }

// RabbitPublisher publishes events to RabbitMQ direct exchange.
type RabbitPublisher struct {
	url        string
	exchange   string
	routingKey string
	mu         sync.Mutex
	conn       *amqp.Connection
	ch         *amqp.Channel
}

func mqEnabled() bool {
	v := os.Getenv("MQ_ENABLED")
	return v == "1" || v == "true" || v == "TRUE" || v == "yes" || v == "YES"
}

func mqURL() string { return os.Getenv("RABBITMQ_URL") }

func mqExchange() string {
	if v := os.Getenv("RABBITMQ_EXCHANGE"); v != "" {
		return v
	}
	return defaultMQExchange
}

func mqRoutingKey() string {
	if v := os.Getenv("RABBITMQ_ROUTING_KEY"); v != "" {
		return v
	}
	return defaultMQRoutingKey
}

func NewPublisherFromEnv() (RatePublisher, error) {
	if !mqEnabled() {
		return &NoopPublisher{}, nil
	}
	r := &RabbitPublisher{
		url:        mqURL(),
		exchange:   mqExchange(),
		routingKey: mqRoutingKey(),
	}
	if r.url == "" {
		return nil, errors.New("MQ_ENABLED=true but RABBITMQ_URL is empty")
	}
	if err := r.connect(); err != nil {
		return nil, err
	}
	return r, nil
}

func (r *RabbitPublisher) connect() error {
	conn, err := amqp.Dial(r.url)
	if err != nil {
		return err
	}
	ch, err := conn.Channel()
	if err != nil {
		_ = conn.Close()
		return err
	}
	if err := ch.ExchangeDeclare(
		r.exchange,
		"direct",
		true,
		false,
		false,
		false,
		nil,
	); err != nil {
		_ = ch.Close()
		_ = conn.Close()
		return err
	}
	r.conn = conn
	r.ch = ch
	return nil
}

func (r *RabbitPublisher) reconnect() error {
	if r.ch != nil {
		_ = r.ch.Close()
		r.ch = nil
	}
	if r.conn != nil {
		_ = r.conn.Close()
		r.conn = nil
	}
	// Tiny backoff to avoid hot looping on transient broker errors.
	time.Sleep(200 * time.Millisecond)
	return r.connect()
}

func (r *RabbitPublisher) Publish(ctx context.Context, payload RatesResponse) error {
	event := RatesEvent{
		EventID:   uuid.NewString(),
		EventType: "rates.snapshot.v1",
		CreatedAt: time.Now().UTC(),
		Source:    "proxy",
		Data:      payload,
	}
	body, err := json.Marshal(event)
	if err != nil {
		return err
	}

	r.mu.Lock()
	defer r.mu.Unlock()
	if r.ch == nil {
		if err := r.connect(); err != nil {
			return err
		}
	}
	msg := amqp.Publishing{
		ContentType:  "application/json",
		DeliveryMode: amqp.Persistent,
		Body:         body,
		Timestamp:    time.Now().UTC(),
		Type:         event.EventType,
	}
	if err := r.ch.PublishWithContext(ctx, r.exchange, r.routingKey, false, false, msg); err == nil {
		return nil
	}
	if err := r.reconnect(); err != nil {
		return err
	}
	return r.ch.PublishWithContext(ctx, r.exchange, r.routingKey, false, false, msg)
}

func (r *RabbitPublisher) Close() error {
	r.mu.Lock()
	defer r.mu.Unlock()
	var first error
	if r.ch != nil {
		if err := r.ch.Close(); err != nil && first == nil {
			first = err
		}
		r.ch = nil
	}
	if r.conn != nil {
		if err := r.conn.Close(); err != nil && first == nil {
			first = err
		}
		r.conn = nil
	}
	return first
}

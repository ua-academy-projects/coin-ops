package main

import (
	"context"
	"encoding/json"
	"sync"
	"time"

	"github.com/google/uuid"
	amqp "github.com/rabbitmq/amqp091-go"
)

const maxPublishAttempts = 5

// RatePublisher publishes normalized snapshots to an asynchronous transport.
type RatePublisher interface {
	Publish(ctx context.Context, payload RatesResponse) error
	Close() error
}

// NoopPublisher is used when MQ is disabled.
type NoopPublisher struct{}

func (n *NoopPublisher) Publish(_ context.Context, _ RatesResponse) error { return nil }
func (n *NoopPublisher) Close() error                                     { return nil }

// RabbitPublisher publishes events to a RabbitMQ direct exchange.
type RabbitPublisher struct {
	url        string
	exchange   string
	routingKey string
	mu         sync.Mutex
	conn       *amqp.Connection
	ch         *amqp.Channel
}

// NewPublisher creates a RatePublisher based on Config.
func NewPublisher(cfg *Config) (RatePublisher, error) {
	if !cfg.MQEnabled {
		return &NoopPublisher{}, nil
	}
	r := &RabbitPublisher{
		url:        cfg.MQURL,
		exchange:   cfg.MQExchange,
		routingKey: cfg.MQRoutingKey,
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
	if err := ch.ExchangeDeclare(r.exchange, "direct", true, false, false, false, nil); err != nil {
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
	time.Sleep(200 * time.Millisecond)
	return r.connect()
}

func (r *RabbitPublisher) Publish(ctx context.Context, payload RatesResponse) error {
	if payload.Rates == nil {
		payload.Rates = []Rate{}
	}
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

	msg := amqp.Publishing{
		ContentType:  "application/json",
		DeliveryMode: amqp.Persistent,
		Body:         body,
		Timestamp:    time.Now().UTC(),
		Type:         event.EventType,
	}

	backoff := 200 * time.Millisecond
	var lastErr error
	for attempt := 1; attempt <= maxPublishAttempts; attempt++ {
		if err := ctx.Err(); err != nil {
			return err
		}

		pubErr := func() error {
			r.mu.Lock()
			defer r.mu.Unlock()
			if r.ch == nil {
				if err := r.connect(); err != nil {
					return err
				}
			}
			return r.ch.PublishWithContext(ctx, r.exchange, r.routingKey, false, false, msg)
		}()

		if pubErr == nil {
			return nil
		}
		lastErr = pubErr

		r.mu.Lock()
		_ = r.reconnect()
		r.mu.Unlock()

		if attempt >= maxPublishAttempts {
			break
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(backoff):
		}
		backoff = min(backoff*2, 2*time.Second)
	}
	return lastErr
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

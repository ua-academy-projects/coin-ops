package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"sync"
	"time"

	"cloud.google.com/go/pubsub"
	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	azservicebus "github.com/Azure/azure-sdk-for-go/sdk/messaging/azservicebus"
	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/jackc/pgx/v5/pgconn"
	amqp "github.com/rabbitmq/amqp091-go"
)

// EventPublisher abstracts event transport across runtime backends.
type EventPublisher interface {
	Publish(ctx context.Context, body []byte) error
	Close() error
}

type eventDB interface {
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
}

type postgresEventPublisher struct {
	db eventDB
}

func (p *postgresEventPublisher) Publish(ctx context.Context, body []byte) error {
	_, err := p.db.Exec(ctx, "SELECT runtime.enqueue_event($1::jsonb)", body)
	return err
}

func (p *postgresEventPublisher) Close() error { return nil }

type rabbitMQEventPublisher struct {
	conn      *amqp.Connection
	ch        *amqp.Channel
	queueName string
	mu        sync.Mutex
}

func newRabbitMQEventPublisher(url, queueName string) (*rabbitMQEventPublisher, error) {
	conn := connectRabbitMQ(url)
	ch, err := conn.Channel()
	if err != nil {
		_ = conn.Close()
		return nil, fmt.Errorf("open rabbitmq channel: %w", err)
	}
	if _, err := ch.QueueDeclare(queueName, true, false, false, false, nil); err != nil {
		_ = ch.Close()
		_ = conn.Close()
		return nil, fmt.Errorf("declare rabbitmq queue: %w", err)
	}
	return &rabbitMQEventPublisher{conn: conn, ch: ch, queueName: queueName}, nil
}

func (p *rabbitMQEventPublisher) Publish(ctx context.Context, body []byte) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.ch.PublishWithContext(ctx, "", p.queueName, false, false, amqp.Publishing{
		DeliveryMode: amqp.Persistent,
		ContentType:  "application/json",
		Body:         body,
	})
}

func (p *rabbitMQEventPublisher) Close() error {
	var err error
	if p.ch != nil {
		err = p.ch.Close()
	}
	if p.conn != nil {
		if closeErr := p.conn.Close(); err == nil {
			err = closeErr
		}
	}
	return err
}

type sqsSendMessageAPI interface {
	SendMessage(ctx context.Context, params *sqs.SendMessageInput, optFns ...func(*sqs.Options)) (*sqs.SendMessageOutput, error)
}

type sqsEventPublisher struct {
	client   sqsSendMessageAPI
	queueURL string
}

func newSQSEventPublisher(ctx context.Context, queueURL, region string) (*sqsEventPublisher, error) {
	if queueURL == "" {
		return nil, errors.New("SQS_QUEUE_URL is required when QUEUE_BACKEND=sqs")
	}
	var cfg aws.Config
	var err error
	if region == "" {
		cfg, err = awsconfig.LoadDefaultConfig(ctx)
	} else {
		cfg, err = awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(region))
	}
	if err != nil {
		return nil, fmt.Errorf("load aws config: %w", err)
	}
	return &sqsEventPublisher{client: sqs.NewFromConfig(cfg), queueURL: queueURL}, nil
}

func (p *sqsEventPublisher) Publish(ctx context.Context, body []byte) error {
	_, err := p.client.SendMessage(ctx, &sqs.SendMessageInput{
		QueueUrl:    aws.String(p.queueURL),
		MessageBody: aws.String(string(body)),
	})
	return err
}

func (p *sqsEventPublisher) Close() error { return nil }

type pubsubEventPublisher struct {
	client *pubsub.Client
	topic  *pubsub.Topic
}

func newPubSubEventPublisher(ctx context.Context, projectID, topicID string) (*pubsubEventPublisher, error) {
	if projectID == "" {
		return nil, errors.New("GCP_PROJECT_ID or GOOGLE_CLOUD_PROJECT is required when QUEUE_BACKEND=pubsub")
	}
	if topicID == "" {
		return nil, errors.New("PUBSUB_TOPIC_ID is required when QUEUE_BACKEND=pubsub")
	}
	client, err := pubsub.NewClient(ctx, projectID)
	if err != nil {
		return nil, fmt.Errorf("create pubsub client: %w", err)
	}
	return &pubsubEventPublisher{client: client, topic: client.Topic(topicID)}, nil
}

func (p *pubsubEventPublisher) Publish(ctx context.Context, body []byte) error {
	result := p.topic.Publish(ctx, &pubsub.Message{Data: body})
	_, err := result.Get(ctx)
	return err
}

func (p *pubsubEventPublisher) Close() error {
	if p.topic != nil {
		p.topic.Stop()
	}
	if p.client != nil {
		return p.client.Close()
	}
	return nil
}

type serviceBusEventPublisher struct {
	client *azservicebus.Client
	sender *azservicebus.Sender
}

func newServiceBusEventPublisher(ctx context.Context, namespace, queueName string) (*serviceBusEventPublisher, error) {
	if namespace == "" {
		return nil, errors.New("AZURE_SERVICEBUS_NAMESPACE is required when QUEUE_BACKEND=servicebus")
	}
	if queueName == "" {
		return nil, errors.New("AZURE_SERVICEBUS_QUEUE_NAME is required when QUEUE_BACKEND=servicebus")
	}
	cred, err := azidentity.NewDefaultAzureCredential(nil)
	if err != nil {
		return nil, fmt.Errorf("create azure credential: %w", err)
	}
	client, err := azservicebus.NewClient(namespace, cred, nil)
	if err != nil {
		return nil, fmt.Errorf("create service bus client: %w", err)
	}
	sender, err := client.NewSender(queueName, nil)
	if err != nil {
		_ = client.Close(ctx)
		return nil, fmt.Errorf("create service bus sender: %w", err)
	}
	return &serviceBusEventPublisher{client: client, sender: sender}, nil
}

func (p *serviceBusEventPublisher) Publish(ctx context.Context, body []byte) error {
	return p.sender.SendMessage(ctx, &azservicebus.Message{Body: body}, nil)
}

func (p *serviceBusEventPublisher) Close() error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	var err error
	if p.sender != nil {
		err = p.sender.Close(ctx)
	}
	if p.client != nil {
		if closeErr := p.client.Close(ctx); err == nil {
			err = closeErr
		}
	}
	return err
}

func detectCloudNativeQueueBackend() string {
	backend := os.Getenv("QUEUE_BACKEND")
	if backend != "" {
		return backend
	}
	switch {
	case os.Getenv("SQS_QUEUE_URL") != "":
		return "sqs"
	case os.Getenv("PUBSUB_TOPIC_ID") != "":
		return "pubsub"
	case os.Getenv("AZURE_SERVICEBUS_NAMESPACE") != "" || os.Getenv("AZURE_SERVICEBUS_QUEUE_NAME") != "":
		return "servicebus"
	default:
		return ""
	}
}

func newCloudNativeEventPublisher(ctx context.Context) (EventPublisher, error) {
	backend := detectCloudNativeQueueBackend()

	switch backend {
	case "sqs":
		return newSQSEventPublisher(ctx, os.Getenv("SQS_QUEUE_URL"), os.Getenv("AWS_REGION"))
	case "pubsub":
		projectID := os.Getenv("GCP_PROJECT_ID")
		if projectID == "" {
			projectID = os.Getenv("GOOGLE_CLOUD_PROJECT")
		}
		return newPubSubEventPublisher(ctx, projectID, os.Getenv("PUBSUB_TOPIC_ID"))
	case "servicebus", "azure_servicebus":
		return newServiceBusEventPublisher(ctx, os.Getenv("AZURE_SERVICEBUS_NAMESPACE"), os.Getenv("AZURE_SERVICEBUS_QUEUE_NAME"))
	default:
		return nil, fmt.Errorf("unsupported or missing QUEUE_BACKEND %q", backend)
	}
}

func (s *Server) publishEvent(body []byte) error {
	if s.publisher == nil {
		return errors.New("event publisher is not configured")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := s.publisher.Publish(ctx, body); err != nil {
		log.Printf("publish event failed: %v", err)
		return err
	}
	return nil
}

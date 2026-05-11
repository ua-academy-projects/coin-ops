package main

import (
	"context"
	"errors"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
)

type fakeSQSClient struct {
	input *sqs.SendMessageInput
	err   error
}

func (f *fakeSQSClient) SendMessage(_ context.Context, input *sqs.SendMessageInput, _ ...func(*sqs.Options)) (*sqs.SendMessageOutput, error) {
	f.input = input
	return &sqs.SendMessageOutput{}, f.err
}

func TestSQSEventPublisherPublishesBody(t *testing.T) {
	t.Parallel()
	client := &fakeSQSClient{}
	publisher := &sqsEventPublisher{client: client, queueURL: "https://sqs.example/queue"}

	if err := publisher.Publish(context.Background(), []byte(`{"type":"price"}`)); err != nil {
		t.Fatalf("Publish() error = %v", err)
	}
	if client.input == nil || aws.ToString(client.input.QueueUrl) != "https://sqs.example/queue" {
		t.Fatalf("queue URL = %#v", client.input)
	}
	if aws.ToString(client.input.MessageBody) != `{"type":"price"}` {
		t.Fatalf("message body = %q", aws.ToString(client.input.MessageBody))
	}
}

func TestSQSEventPublisherReturnsSendError(t *testing.T) {
	t.Parallel()
	boom := errors.New("sqs down")
	publisher := &sqsEventPublisher{client: &fakeSQSClient{err: boom}, queueURL: "q"}

	if err := publisher.Publish(context.Background(), []byte(`{}`)); !errors.Is(err, boom) {
		t.Fatalf("Publish() error = %v, want %v", err, boom)
	}
}

func TestCloudNativePublisherRequiresBackend(t *testing.T) {
	t.Setenv("QUEUE_BACKEND", "")
	t.Setenv("SQS_QUEUE_URL", "")
	t.Setenv("PUBSUB_TOPIC_ID", "")

	_, err := newCloudNativeEventPublisher(context.Background())
	if err == nil {
		t.Fatal("expected error for missing cloud-native queue backend")
	}
}

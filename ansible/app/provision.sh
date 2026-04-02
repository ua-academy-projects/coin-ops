#!/bin/bash
set -e

echo "===> Updating system"
apt-get update -y

echo "===> Installing dependencies"
apt-get install -y curl git

# ------------------------
# Install Go
# ------------------------
GO_VERSION="1.22.3"

if ! command -v go &> /dev/null; then
  echo "===> Installing Go"
  curl -LO https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz
  rm -rf /usr/local/go
  tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
  echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
fi

export PATH=$PATH:/usr/local/go/bin

# ------------------------
# Install RabbitMQ
# ------------------------
echo "===> Installing RabbitMQ"

apt-get install -y rabbitmq-server

systemctl enable rabbitmq-server
systemctl start rabbitmq-server

# ------------------------
# Build app
# ------------------------
cd /app

echo "===> Building app"
go mod tidy
go build -o nbu-collector

# ------------------------
# Create systemd service
# ------------------------
cat <<EOF > /etc/systemd/system/nbu-collector.service
[Unit]
Description=NBU Collector
After=network.target rabbitmq-server.service

[Service]
WorkingDirectory=/app
ExecStart=/app/nbu-collector

# ENV
Environment="PUBLISH_MODE=rabbit"
Environment="DRY_RUN=false"
Environment="RABBITMQ_URL=amqp://guest:guest@localhost:5672/"
Environment="RABBITMQ_QUEUE=nbu.exchange.rates"
Environment="HTTP_ADDR=:8080"

Restart=always
RestartSec=5

User=vagrant

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable nbu-collector
systemctl start nbu-collector

echo "===> Done!"

# Manual Deployment (without Ansible)

Everything Ansible does, but typed by hand over SSH. Same end result: three VMs, systemd services, no containers.

---

## node-01 — PostgreSQL + RabbitMQ + History Service

### SSH in
```bash
ssh vagrant@172.31.1.10
```

### Install packages
```bash
sudo apt update
sudo apt install -y postgresql postgresql-contrib rabbitmq-server \
                    python3 python3-venv python3-pip
```

### Start infrastructure services
```bash
sudo systemctl enable --now postgresql
sudo systemctl enable --now rabbitmq-server
```

### Create PostgreSQL user and database
```bash
sudo -u postgres psql <<'SQL'
CREATE USER cognitor WITH PASSWORD 'changeme';
CREATE DATABASE cognitor OWNER cognitor;
SQL
```

### Create RabbitMQ user
```bash
sudo rabbitmqctl add_user cognitor changeme
sudo rabbitmqctl set_permissions -p / cognitor ".*" ".*" ".*"
```

### Create system user for the service
```bash
sudo useradd --system --shell /usr/sbin/nologin cognitor-history
```

### Create secrets directory
```bash
sudo mkdir -p /etc/cognitor
sudo chmod 750 /etc/cognitor
```

### Deploy Python source files
```bash
# On your laptop — copy files to node-01
scp -r history/ vagrant@172.31.1.10:/tmp/history-src

# Back on node-01
sudo mkdir -p /opt/cognitor/history
sudo cp /tmp/history-src/* /opt/cognitor/history/
sudo chown -R cognitor-history:cognitor-history /opt/cognitor/history
```

### Create virtualenv and install dependencies
```bash
sudo -u cognitor-history python3 -m venv /opt/cognitor/history/venv
sudo -u cognitor-history /opt/cognitor/history/venv/bin/pip install \
    -r /opt/cognitor/history/requirements.txt
```

### Write the secrets file
```bash
sudo tee /etc/cognitor/history.env > /dev/null <<'EOF'
DATABASE_URL=postgresql://cognitor:changeme@172.31.1.10:5432/cognitor
RABBITMQ_URL=amqp://cognitor:changeme@172.31.1.10:5672/
PORT=8000
EOF
sudo chown cognitor-history:cognitor-history /etc/cognitor/history.env
sudo chmod 640 /etc/cognitor/history.env
```

### Create systemd unit — history-consumer
```bash
sudo tee /etc/systemd/system/cognitor-history-consumer.service > /dev/null <<'EOF'
[Unit]
Description=Coin-Ops History Consumer (Python/pika)
After=network.target rabbitmq-server.service postgresql.service

[Service]
Type=simple
User=cognitor-history
EnvironmentFile=/etc/cognitor/history.env
ExecStart=/opt/cognitor/history/venv/bin/python /opt/cognitor/history/consumer.py
Restart=on-failure
RestartSec=5s
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
```

### Create systemd unit — history-api
```bash
sudo tee /etc/systemd/system/cognitor-history-api.service > /dev/null <<'EOF'
[Unit]
Description=Coin-Ops History API (FastAPI/uvicorn)
After=network.target postgresql.service

[Service]
Type=simple
User=cognitor-history
EnvironmentFile=/etc/cognitor/history.env
ExecStart=/opt/cognitor/history/venv/bin/python /opt/cognitor/history/main.py
Restart=on-failure
RestartSec=5s
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
```

### Enable and start both services
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now cognitor-history-consumer
sudo systemctl enable --now cognitor-history-api

# Verify
sudo systemctl status cognitor-history-consumer
sudo systemctl status cognitor-history-api
curl http://localhost:8000/health
```

---

## node-02 — Proxy Service (Go)

### SSH in
```bash
ssh vagrant@172.31.1.11
```

### Install Go
```bash
sudo apt update
sudo apt install -y golang-go
```

### Create system user
```bash
sudo useradd --system --shell /usr/sbin/nologin cognitor-proxy
```

### Create secrets directory
```bash
sudo mkdir -p /etc/cognitor
sudo chmod 750 /etc/cognitor
```

### Deploy Go source files
```bash
# On your laptop
scp -r proxy/ vagrant@172.31.1.11:/tmp/proxy-src

# On node-02
sudo mkdir -p /opt/cognitor/proxy
sudo cp /tmp/proxy-src/* /opt/cognitor/proxy/
```

### Build the binary
```bash
cd /opt/cognitor/proxy
sudo go build -mod=mod -o proxy .
sudo chown cognitor-proxy:cognitor-proxy proxy
sudo chmod 750 proxy
```

### Write the secrets file
```bash
sudo tee /etc/cognitor/proxy.env > /dev/null <<'EOF'
RABBITMQ_URL=amqp://cognitor:changeme@172.31.1.10:5672/
PORT=8080
EOF
sudo chown cognitor-proxy:cognitor-proxy /etc/cognitor/proxy.env
sudo chmod 640 /etc/cognitor/proxy.env
```

### Create systemd unit
```bash
sudo tee /etc/systemd/system/cognitor-proxy.service > /dev/null <<'EOF'
[Unit]
Description=Coin-Ops Proxy Service (Go)
After=network.target

[Service]
Type=simple
User=cognitor-proxy
EnvironmentFile=/etc/cognitor/proxy.env
ExecStart=/opt/cognitor/proxy/proxy
Restart=on-failure
RestartSec=5s
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
```

### Enable and start
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now cognitor-proxy

# Verify
sudo systemctl status cognitor-proxy
curl http://localhost:8080/health
```

---

## node-03 — Web UI (nginx)

### SSH in
```bash
ssh vagrant@172.31.1.12
```

### Install nginx
```bash
sudo apt update
sudo apt install -y nginx
```

### Deploy the dashboard
```bash
# On your laptop
scp ui/index.html vagrant@172.31.1.12:/tmp/index.html
scp ui/nginx.conf vagrant@172.31.1.12:/tmp/nginx.conf

# On node-03
sudo mkdir -p /var/www/coin-ops
sudo cp /tmp/index.html /var/www/coin-ops/index.html
sudo chown -R www-data:www-data /var/www/coin-ops
```

### Configure nginx
```bash
sudo cp /tmp/nginx.conf /etc/nginx/sites-available/coin-ops
sudo ln -s /etc/nginx/sites-available/coin-ops /etc/nginx/sites-enabled/coin-ops
sudo rm -f /etc/nginx/sites-enabled/default

sudo nginx -t          # verify config syntax
sudo systemctl reload nginx
```

### Verify
```bash
curl http://localhost/
```

---

## Updating after code changes

### Proxy (node-02)
```bash
# copy new source, rebuild
scp -r proxy/ vagrant@172.31.1.11:/tmp/proxy-src
ssh vagrant@172.31.1.11 "
  sudo cp /tmp/proxy-src/* /opt/cognitor/proxy/ &&
  cd /opt/cognitor/proxy &&
  sudo go build -mod=mod -o proxy . &&
  sudo chown cognitor-proxy:cognitor-proxy proxy &&
  sudo systemctl restart cognitor-proxy
"
```

### History (node-01)
```bash
scp -r history/ vagrant@172.31.1.10:/tmp/history-src
ssh vagrant@172.31.1.10 "
  sudo cp /tmp/history-src/* /opt/cognitor/history/ &&
  sudo -u cognitor-history /opt/cognitor/history/venv/bin/pip install \
      -r /opt/cognitor/history/requirements.txt &&
  sudo systemctl restart cognitor-history-consumer cognitor-history-api
"
```

### UI (node-03)
```bash
scp ui/index.html vagrant@172.31.1.12:/tmp/index.html
ssh vagrant@172.31.1.12 "
  sudo cp /tmp/index.html /var/www/coin-ops/index.html &&
  sudo systemctl reload nginx
"
```

---

## Useful debug commands (on any VM)

```bash
# Follow live logs
sudo journalctl -u cognitor-proxy -f
sudo journalctl -u cognitor-history-consumer -f
sudo journalctl -u cognitor-history-api -f

# Check if service is actually responding (not just "active")
curl http://localhost:8080/health
curl http://localhost:8000/health

# PostgreSQL — check rows are coming in
sudo -u postgres psql cognitor -c "SELECT count(*) FROM market_snapshots;"

# RabbitMQ — check queue depth
sudo rabbitmqctl list_queues name messages consumers
```

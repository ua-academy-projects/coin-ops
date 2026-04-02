#!/bin/bash

set -e
WORKING_DIR="/home/vagrant/shared_folder/proxy"

# vm 2 - proxy
sudo apt install -y golang
sudo cp "$WORKING_DIR/proxy.service" "/lib/systemd/system/"
sudo systemctl daemon-reload
sudo systemctl stop proxy 2>/dev/null || true

cd "$WORKING_DIR" || { echo "Cannot cd to $WORKING_DIR" >&2; exit 1; }
go build -o proxy.bin .

sudo systemctl enable proxy
sudo systemctl start proxy

echo -e "\033[0;32mVM 2 success setup. Proxy service is running..."
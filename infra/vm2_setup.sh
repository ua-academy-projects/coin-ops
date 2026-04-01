#!/bin/bash

WORKING_DIR="/home/working_dir"

# vm 2 - proxy
sudo apt install -y golang
cp -r "/home/shared_folder/proxy" "$WORKING_DIR"
sudo cp "$WORKING_DIR/proxy.service" "/lib/systemd/system/"
cd "$WORKING_DIR" || exit
go build -o proxy .

sudo systemctl daemon-reload
sudo systemctl start proxy
sudo systemctl enable proxy

# nohup ./proxy > "$WORKING_DIR/proxy.log" 2>&1 &

echo -e "\033[0;32mVM 2 success setup. Proxy service is running..."
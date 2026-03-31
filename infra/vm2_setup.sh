#!/bin/bash

WORKING_DIR="/home/working_dir"

# vm 2 - proxy
sudo apt install -y golang
cp -r "/home/shared_folder/proxy" "$WORKING_DIR"
cd "$WORKING_DIR" || exit
go build

# temporary use of exposed variables
export COINOPS_LISTEN=":8080"

nohup ./proxy > "$WORKING_DIR/proxy.log" 2>&1 &

echo -e "\033[0;32mVM 2 success setup. Proxy service is running..."
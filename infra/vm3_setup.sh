#!/bin/bash

set -e
WORKING_DIR="/home/vagrant/shared_folder/worker"
VENV_DIR="/home/vagrant/venv"

# vm 3 - history service (MQ consumer + history API)
sudo apt install -y python3 python3-pip python3-venv
sudo cp "$WORKING_DIR/worker.service" "/lib/systemd/system/"
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi
source "$VENV_DIR/bin/activate"
pip install -r "$WORKING_DIR/requirements.txt"

sudo systemctl daemon-reload
sudo systemctl start worker
sudo systemctl enable worker

echo -e "\033[0;32mVM 3 success setup. History service is running..."
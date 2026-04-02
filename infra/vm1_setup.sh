#!/bin/bash

set -e
WORKING_DIR="/home/vagrant/shared_folder/frontend"
VENV_DIR="/home/vagrant/venv"

# vm 1 - frontend
sudo apt install -y python3 python3-pip python3-venv python3-flask nginx
sudo cp "$WORKING_DIR/frontend.service" "/lib/systemd/system/"
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi
source "$VENV_DIR/bin/activate"
pip install -r "$WORKING_DIR/requirements.txt"

sudo systemctl daemon-reload
sudo systemctl start frontend
sudo systemctl enable frontend

echo -e "\033[0;32mVM 1 success setup. Flask app is running..."
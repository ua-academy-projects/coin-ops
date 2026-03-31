#!/bin/bash

WORKING_DIR="/home/working_dir"

# vm 3 - db / message queue handler
sudo apt install -y python3 python3-pip python3-venv
cp -r "/home/shared_folder/worker" "$WORKING_DIR"
sudo cp "$WORKING_DIR/worker.service" "/lib/systemd/system/"
python3 -m venv "$WORKING_DIR/venv"
source "$WORKING_DIR/venv/bin/activate"
pip install -r "$WORKING_DIR/requirements.txt"

sudo systemctl daemon-reload
sudo systemctl start worker
sudo systemctl enable worker

# nohup python3 "$WORKING_DIR/worker.py" > "$WORKING_DIR/worker.log" 2>&1 &

echo -e "\033[0;32mVM 3 success setup. Worker is running..."
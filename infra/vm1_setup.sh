#!/bin/bash

WORKING_DIR="/home/working_dir"

# vm 1 - frontend
sudo apt install -y python3 python3-pip python3-venv python3-flask nginx
cp -r "/home/shared_folder/frontend" "$WORKING_DIR"
sudo cp "$WORKING_DIR/frontend.service" "/lib/systemd/system/"
python3 -m venv "$WORKING_DIR/venv"
source "$WORKING_DIR/venv/bin/activate"
pip install -r "$WORKING_DIR/requirements.txt"

sudo systemctl daemon-reload
sudo systemctl start frontend
sudo systemctl enable frontend

# nohup python3 "$WORKING_DIR/app.py" > "$WORKING_DIR/app.log" 2>&1 &
# або
# python3 "$WORKING_DIR/frontend/app.py" > /dev/null 2>&1 &
# disown

echo -e "\033[0;32mVM 1 success setup. Flask app is running..."
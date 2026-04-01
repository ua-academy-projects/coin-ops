#!/bin/bash

# vm 4 - rabbitmq
sudo apt install -y rabbitmq-server
sudo systemctl enable rabbitmq-server
sudo systemctl start rabbitmq-server

sudo rabbitmqctl add_user coinops coinops
sudo rabbitmqctl set_user_tags coinops management
sudo rabbitmqctl set_permissions -p / coinops ".*" ".*" ".*"

echo -e "\033[0;32mVM 4 success setup. RabbitMQ is running..."
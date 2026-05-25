#!/bin/bash
# Changes SSH port and creates ops user. Runs once on first boot.
if [ -f /etc/ssh/sshd_config.d/custom-port.conf ]; then
  exit 0
fi
echo "Port ${ssh_port}" > /etc/ssh/sshd_config.d/custom-port.conf
systemctl daemon-reload
sleep 2
systemctl restart ssh.service

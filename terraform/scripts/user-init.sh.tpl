#!/bin/bash
# User bootstrap: set a stable hostname, create ${username} with sudo and SSH
# key access, then configure sshd to listen on port ${ssh_port}.
set -euo pipefail

log() { echo "[user-init] $*"; }

log "Setting hostname to '${hostname}'..."
hostnamectl set-hostname "${hostname}"

log "Creating user '${username}'..."
if ! id "${username}" &>/dev/null; then
  useradd -m -s /bin/bash "${username}"
fi

echo "${username} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${username}
chmod 440 /etc/sudoers.d/${username}

mkdir -p /home/${username}/.ssh
echo '${ssh_public_key}' >> /home/${username}/.ssh/authorized_keys
chmod 700 /home/${username}/.ssh
chmod 600 /home/${username}/.ssh/authorized_keys
chown -R ${username}:${username} /home/${username}/.ssh

log "User '${username}' created successfully."
log "Configuring SSH port ${ssh_port}..."

SSHD_CFG=/etc/ssh/sshd_config

if grep -qE "^#?Port " "$SSHD_CFG"; then
  sed -i "s/^#\?Port .*/Port ${ssh_port}/" "$SSHD_CFG"
else
  echo "Port ${ssh_port}" >> "$SSHD_CFG"
fi

if systemctl is-active --quiet sshd; then
  systemctl reload sshd
elif systemctl is-active --quiet ssh; then
  systemctl reload ssh
fi

log "SSH port set to ${ssh_port}."

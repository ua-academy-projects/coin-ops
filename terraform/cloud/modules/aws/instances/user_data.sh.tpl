#!/bin/bash
set -euo pipefail

if ! id ${ssh_user} >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash ${ssh_user}
fi

install -d -m 700 -o ${ssh_user} -g ${ssh_user} /home/${ssh_user}/.ssh
cat > /home/${ssh_user}/.ssh/authorized_keys <<'KEYS'
${ssh_public_key}
KEYS
chown ${ssh_user}:${ssh_user} /home/${ssh_user}/.ssh/authorized_keys
chmod 600 /home/${ssh_user}/.ssh/authorized_keys

if command -v apt-get >/dev/null 2>&1; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y python3 sudo
fi

usermod -aG sudo ${ssh_user}
echo '${ssh_user} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/${ssh_user}
chmod 440 /etc/sudoers.d/${ssh_user}

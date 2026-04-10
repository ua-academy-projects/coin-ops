# Iteration 1 — VM-Based Deployment with Ansible

## What Was Built

5 isolated Ubuntu 24.04 VMs, each running one service, fully automated with Ansible.

## Why This Approach

The task required VM-based isolation without containers for the first iteration. Each service runs independently — if one crashes, others continue. Ansible ensures the entire setup can be reproduced with one command.

## VM Architecture

| VM | Service | IP (Host-Only) |
|---|---|---|
| server1 | UI — Flask + React | 192.168.56.101 |
| server2 | Proxy — Flask | 192.168.56.102 |
| server3 | RabbitMQ | 192.168.56.103 |
| server4 | History — Go | 192.168.56.104 |
| server5 | PostgreSQL | 192.168.56.105 |

Each VM has two network adapters:
- **Bridged** — for internet access (dynamic IP, changes per network)
- **Host-Only** — for stable VM-to-VM communication (static IP via Netplan)

## Setting Static IPs with Netplan

```bash
sudo nano /etc/netplan/50-cloud-init.yaml
```

```yaml
network:
  version: 2
  ethernets:
    enp0s3:
      dhcp4: true        # bridged — internet access
    enp0s8:
      dhcp4: no
      addresses: [192.168.56.101/24]   # host-only — stable VM communication
```

```bash
sudo netplan apply
ip a show enp0s8   # verify
```

## Ansible Structure

```
ansible/
├── inventory.ini        ← list of all servers with IPs and users
├── site.yml             ← master playbook — runs everything in order
├── ansible.cfg          ← SSH config
├── playbooks/
│   ├── server5.yml      ← PostgreSQL setup
│   ├── server03.yml     ← RabbitMQ setup
│   ├── server4.yml      ← Go history service
│   ├── server2.yml      ← Python proxy service
│   └── server1.yml      ← React UI + Flask
└── files/
    ├── ui/app.py
    ├── proxy/app.py
    └── history/main.go
```

## Deploy Everything

```bash
cd ansible/
ansible-playbook -i inventory.ini site.yml
```

## Key Ansible Concepts Used

- **Idempotency** — safe to run multiple times, always same result
- **become: true** — allows Ansible to use sudo on remote servers
- **ansible_connection=local** — server1 runs Ansible on itself
- **systemd module** — enables and starts services automatically
- **copy module** — copies local files to remote servers

## systemd — Service Management

Every service is registered with systemd so it:
- Starts automatically when VM boots
- Restarts automatically if it crashes

```bash
sudo systemctl status ui-service
sudo systemctl status proxy-service
sudo systemctl status history-service
sudo systemctl status rabbitmq-server
sudo systemctl status postgresql
```

## RabbitMQ User Setup

RabbitMQ uses separate users with minimal permissions:

```bash
sudo rabbitmqctl add_user proxy_user proxy_password
sudo rabbitmqctl add_user history_user history_password
sudo rabbitmqctl set_permissions -p / proxy_user ".*" ".*" ""   # configure + write
sudo rabbitmqctl set_permissions -p / history_user ".*" "" ".*" # configure + read
sudo rabbitmqctl delete_user guest   # security — remove default user
```

## Blockers & Workarounds

| Blocker | Cause | Fix |
|---|---|---|
| Node.js v18 EOL | Vite 9 requires Node 20+ | Installed NVM, upgraded to Node 20 LTS |
| CoinGecko rate limiting | Too many rapid API calls | Added 25-second cache to proxy |
| Python package conflict | apt vs pip packages | Used Python virtual environment |
| Vagrant SSH key auth | server03 disabled password auth | Manually added Ansible key to authorized_keys |
| apt lock during Ansible | unattended-upgrades held lock | Killed background process, removed lock files |
| postgresql_user module bug | Ubuntu 24.04 chmod issue | Used shell module with direct psql commands |
| create-react-app too heavy | 1400+ packages, slow on VM | Switched to Vite — 20x fewer packages |
| Dynamic IP addresses | DHCP changes IP on network switch | Configured static IPs via Netplan on Host-Only adapter |
| soft lockup on server03 | CPU stuck in VirtualBox (Vagrant VM) | Recreated server03 as manual VirtualBox VM |

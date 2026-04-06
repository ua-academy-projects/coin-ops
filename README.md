# Coin Rates Dashboard

A multi-VM application that fetches live cryptocurrency and currency exchange rates, displays them in a React dashboard, and stores historical data asynchronously.

## Architecture

| VM | Service | IP | Language |
|---|---|---|---|
| server1 | UI Service (Flask + React) | 192.168.0.106 | Python |
| server2 | Proxy/API Service | 192.168.0.103 | Python |
| server03 | Message Queue (RabbitMQ) | 192.168.0.105 | - |
| server4 | History Service | 192.168.0.107 | Go |
| server5 | Database (PostgreSQL) | 192.168.0.108 | - |

## Data Flow

User opens browser → Flask serves React UI → React fetches from Proxy → Proxy calls CoinGecko and NBU → Proxy publishes to RabbitMQ → Go consumes from queue → Go saves to PostgreSQL → React fetches history from Flask

## Data Sources

- Crypto: CoinGecko API (Bitcoin, Ethereum in USD and UAH)
- Currency: NBU API (~40 currencies)

## Features

- Live Bitcoin and Ethereum prices
- Price change indicator since first record
- Separate charts for Bitcoin and Ethereum with smart Y-axis
- Currency selector from full NBU list
- Auto-refresh every 30 seconds with countdown
- History table with pagination
- Service status monitoring panel
- 25-second response cache on proxy

## Tech Stack

- Frontend: React + Vite + Recharts
- UI Backend: Python/Flask
- Proxy: Python/Flask
- History Service: Go
- Message Queue: RabbitMQ
- Database: PostgreSQL

## Deployment

All services deployed on Ubuntu VMs using Ansible.

### Requirements
- Ansible installed on server1
- SSH key access from server1 to all VMs
- Passwordless sudo on all VMs

### Deploy everything
cd ansible
ansible-playbook -i inventory.ini site.yml

### Deploy individual service
ansible-playbook -i inventory.ini playbooks/server1.yml
ansible-playbook -i inventory.ini playbooks/server2.yml
ansible-playbook -i inventory.ini playbooks/server03.yml
ansible-playbook -i inventory.ini playbooks/server4.yml
ansible-playbook -i inventory.ini playbooks/server5.yml

## Service Management

All services managed by systemd, start automatically on boot.

Check status:
sudo systemctl status ui-service
sudo systemctl status proxy-service
sudo systemctl status history-service
sudo systemctl status rabbitmq-server
sudo systemctl status postgresql

## Blockers and Workarounds

- RabbitMQ slow install — VM was paused in VirtualBox, resumed and completed
- Node.js version — upgraded from EOL Node 18 to Node 20 LTS using NVM
- CoinGecko rate limiting — added 25-second cache to proxy service
- Python package conflicts — used virtualenv instead of system pip
- Vagrant SSH — server03 uses key-only auth, manually added Ansible key
- Unattended upgrades lock — killed background apt process blocking Ansible

## VM Setup Notes

- server1, server4, server5 — created manually in VirtualBox with Ubuntu 24.04
- server2 — created with Vagrant (ubuntu/jammy64)
- server03 — recreated with Vagrant after slow manual Ubuntu installation
- All VMs use Bridged Adapter for network connectivity
# Coin-Ops

A microservices-based financial data aggregator that fetches, normalizes, and stores real-time exchange rates for Fiat and Cryptocurrencies.<br><br>
Coin-Ops is designed with an infrastructure-first approach to demonstrate a robust microservices architecture. It pulls data from public sources (NBU, CoinGecko) via a Go-based proxy, processes it asynchronously, and serves it through a Python/Flask web interface. The entire environment is automated and provisioned across isolated virtual machines.

## Architecture
System runs on 5 virtual machines configured via Vagrant and Ansible.
* **VM1 - Frontend**: Python / Flask web interface, Redis.
* **VM2 - Proxy service**: Go API gateway, fetches and normalizes data from 3rd-party APIs.
* **VM3 - History service**: Python service that consumes MQ events and exposes History API.
* **VM4 - Message queue**: RabbitMQ broker.
* **VM5 - Database**: PostgreSQL instance storing historical exchange rates.

## How to use?
### Prerequisites
Ensure you have the following installed on your host machine before starting:
* [Vagrant](https://developer.hashicorp.com/vagrant)
* VMware Workstation (or VirtualBox, but you need to specify compatible Vagrant box)

### Installation & Run

1. Clone the repository:
   ```bash
   git clone https://github.com/ua-academy-projects/coin-ops.git
   ```
2. Generate an SSH key for Vagrant VMs (must be done before provisioning):
   ```bash
   ssh-keygen -t ed25519 -f .ssh/vagrant_key -C "vagrant-key" -N ""
   ```
   *(Ansible will automatically distribute the public key to all VMs during the first run and disable the insecure default key).*

3. Provision and start the infrastructure:
    ```Bash
    vagrant up
    # or run the batch script for parallel deployment of each VM:
    ./launch.sh
### Configuration & Environment files
Environment variables and configuration (IPs, Ports, URLs) are managed by **Ansible IaC**. 
- Non-secret variables are in `infra/group_vars/all/vars.yml`.
- Secrets (Database/MQ Passwords) are encrypted in `infra/group_vars/all/vault.yml`.
- During `vagrant provision`, Ansible uses Jinja2 templates (`.env.j2`) to automatically generate the required `.env` files directly on the target VMs with strict security permissions (`0600`).
*(Do not manually edit `.env` files locally or on the VMs)*

### Basic run notes (systemd)
After updating env files:
```bash
sudo systemctl daemon-reload
sudo systemctl restart proxy history_service frontend
sudo systemctl status proxy history_service frontend
```

## To-Do List
* Phase 1 - Usability:
  * [x] Better UI
    * [x] Convert currency to a human-readable format
    * [x] Convert time to a human-readable format
  * [x] Show only the most popular fiats / coins
  * [x] Search by code (UAH / USD / BTC / etc) or name if possible (Долар США / Євро / Etherum / etc) - need to fetch list of coin names / codes
  * [x] Convert coins to UAH for general list
  * [x] Convert any-to-any fiat / coin (but that would be more of a currency converter than a list)<br>
* Phase 2 - Infrastructure Evolution:
  * [x] RabbitMQ implementing
  * [x] Redis implementing (caching and remembering user preferences)
  * [x] Migrate provisioning to Terraform / Ansible
  * [ ] Security work (minimum permissions, firewall, secrets for credentials, etc)
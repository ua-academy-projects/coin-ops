# Coin-Ops

A microservices-based financial data aggregator that fetches, normalizes, and stores real-time exchange rates for Fiat and Cryptocurrencies.<br><br>
Coin-Ops is designed with an infrastructure-first approach to demonstrate a robust microservices architecture. It pulls data from public sources (NBU, CoinGecko) via a Go-based proxy, processes it asynchronously, and serves it through a Python/Flask web interface. The entire environment is automated and provisioned across isolated virtual machines.

## Architecture
System runs on 4 virtual machines (currently) configured via Vagrant and Bash scripts.
* **VM1 (Frontend)**: Simple Python / Flask web interface.
* **VM2 (Proxy service)**: Go application that acts as an API gateway, fetching and normalizing data from 3rd-party APIs.
* **VM3 (Worker)**: Python service that processes data from the Proxy and saves it to the database.
* **VM4 (Database)**: PostgreSQL instance storing historical exchange rates.

## How to use?
### Prerequisites
Ensure you have the following installed on your host machine before starting:
* [Vagrant](https://developer.hashicorp.com/vagrant)
* VMware Workstation (or VirtualBox, but you need to specify compatible Vagrant box)

### Installation & Run

1. Clone the repository:
   ```bash
   git clone <your-repo-link>
   cd coin-ops
2. Provision and start the infrastructure:
    ```Bash
    vagrant up
    # or run the batch script for parallel deployment of each VM:
    ./launch.sh
## To-Do List
* Phase 1 - Usability:
  * [ ] Better UI
    * [ ] Convert currency to a human-readable format
    * [ ] Convert time to a human-readable format
  * [ ] Show only the most popular fiats / coins
  * [ ] Search by code (UAH / USD / BTC / etc) or name if possible (Долар США / Євро / Etherum / etc) - need to fetch list of coin names / codes
  * [ ] Convert coins to UAH for general list
  * [ ] Convert any-to-any fiat / coin (but that would be more of a currency converter than a list)<br>
* Phase 2 - Infrastructure Evolution:
  * [ ] RabbitMQ implementing
  * [ ] Redis implementing (caching and remembering user preferences)
  * [ ] Migrate provisioning to Terraform / Ansible
  * [ ] Security work (minimum permissions, firewall, secrets for credentials, etc)
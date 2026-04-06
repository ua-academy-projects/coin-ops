# CoinOps Runbook

This runbook provides a compact “what talks to what” network matrix plus a short operational flow for starting and smoke-testing the system.

## VM IPs (Vagrant private_network)

From `Vagrantfile` (base `10.10.1.` plus VM index):

| VM | Role | IP (private_network) |
| --- | --- | --- |
| `vm1` | Frontend | `10.10.1.2` |
| `vm2` | Proxy | `10.10.1.3` |
| `vm3` | History Service | `10.10.1.4` |
| `vm4` | RabbitMQ | `10.10.1.5` |
| `vm5` | PostgreSQL | `10.10.1.6` |

## Service ports

- Proxy (vm2): `8080` (HTTP)
- History Service (vm3): `8090` (HTTP)
- RabbitMQ (vm4): `5672` (AMQP)
- PostgreSQL (vm5): `5432` (TCP)
- Redis (vm1, **localhost**): `6379` (TCP) — optional Phase D UI state (`REDIS_URL`, same-origin `/api/v1/ui-state`)

## Network matrix (required east-west traffic)

| From | To | Protocol | Port | Purpose / example |
| --- | --- | --- | --- | --- |
| `vm1` | `vm2` | TCP (HTTP) | `8080` | UI live data refresh: `GET http://10.10.1.3:8080/api/v1/rates` |
| `vm1` | `vm3` | TCP (HTTP) | `8090` | History API: `GET http://10.10.1.4:8090/api/v1/history?limit=5` (UI fetches via Flask same-origin proxy) |
| `vm3` | `vm4` | TCP (AMQP) | `5672` | History service consumes MQ events from `RABBITMQ_URL` |
| `vm3` | `vm5` | TCP | `5432` | History Service writes to PostgreSQL using `PGHOST/PGPORT` |
| `vm1` (Flask) | `vm1` (Redis) | TCP | `6379` | `127.0.0.1:6379` — UI state (no east-west traffic) |

Outgoing from `vm2`:
- `vm2 -> external`: outbound HTTP(S) to public data sources (NBU, CoinGecko)

## Startup order (systemd inside VMs)

Typical order to avoid dependency issues:

1. `vm5`: `sudo systemctl restart postgresql`
2. `vm4`: `sudo systemctl restart rabbitmq-server`
3. `vm2`: `sudo systemctl restart proxy`
4. `vm3`: `sudo systemctl restart history_service`
5. `vm1`: `sudo systemctl restart redis-server` then `sudo systemctl restart frontend`

After env changes (**DO NOT edit `.env` manually on the VM - edit `infra/group_vars/all/vars.yml` and run `vagrant provision`**):
- `sudo systemctl daemon-reload`
- `sudo systemctl restart <service>`

## Smoke tests (run from the host or any VM with routing to the private subnet)

1. Live rates via Proxy:
```bash
curl -sS http://10.10.1.3:8080/api/v1/rates | jq '.rates | length'
```

2. History API:
```bash
curl -sS "http://10.10.1.4:8090/api/v1/history?limit=5" | jq '.count'
```

3. Queue status on vm4 (RabbitMQ):
```bash
rabbitmqctl list_queues name messages consumers
```

4. Postgres has rows on vm5:
```bash
psql -h 10.10.1.6 -U coinops -d coinops_db -c "select count(*) from exchange_rates;"
```

## Notes

- `infra/base_setup.sh` installs `ufw`, but it does not configure port rules. If you enable host/guest firewall, ensure the TCP ports in the network matrix are allowed between `10.10.1.0/24` VMs.
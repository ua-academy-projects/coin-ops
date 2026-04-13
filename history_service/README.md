# History Service

Go service that consumes price messages from RabbitMQ, stores them in PostgreSQL, and exposes history/statistics endpoints.

## Responsibility

- consumes messages from RabbitMQ
- inserts prices into PostgreSQL
- serves historical data for the UI
- serves chart data and min/max statistics

## Runtime

- language: Go
- service port: `5002`
- host VM: `devops-history`

## Endpoints

- `GET /history` - returns filtered price history
- `GET /stats` - returns highest and lowest price for a coin
- `GET /chart` - returns chart points for a selected time range

## Dependencies

- PostgreSQL
- RabbitMQ

## Environment Variables

- `POSTGRES_HOST`
- `POSTGRES_DB`
- `POSTGRES_USER`
- `POSTGRES_PASS`
- `POSTGRES_TABLE`
- `RABBITMQ_HOST`
- `RABBITMQ_USER`
- `RABBITMQ_PASS`
- `RABBITMQ_QUEUE`

These variables are rendered by Ansible into `history.service`.

## Build and Service

The binary is built by Ansible with:

```bash
go build -o history-service main.go
```

Systemd unit template:

- `ansible/roles/history/templates/history.service.j2`

Useful commands on `devops-history`:

```bash
sudo systemctl status history
sudo journalctl -u history.service -n 50
sudo systemctl cat history.service
sudo systemctl show history.service -p Environment
```

## Common Problems

### `Failed to create table: pq: syntax error at or near "("`

Cause:

- `POSTGRES_TABLE` is empty when the service starts

Check:

```bash
sudo systemctl show history.service -p Environment
```

Expected:

```text
POSTGRES_TABLE=currency_rates
```

### RabbitMQ reconnect loop

Cause:

- RabbitMQ is down
- wrong user or password
- queue name is missing

Check:

```bash
sudo journalctl -u history.service -n 50
```

## Notes

- the service creates the target table if it does not exist
- duplicate inserts within a short time window are skipped

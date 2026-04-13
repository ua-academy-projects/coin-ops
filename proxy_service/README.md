# Proxy Service

Flask service that fetches live cryptocurrency prices from Coinbase and sends them to RabbitMQ.

## Responsibility

- provides live prices for supported coins
- periodically refreshes prices in the background
- smooths sharp price jumps before publishing
- sends messages to RabbitMQ for the history service

## Runtime

- language: Python 3
- framework: Flask
- service port: `5001`
- host VM: `devops-proxy`

## Endpoints

- `GET /price/<coin>` - fetches current price and sends it to RabbitMQ

Supported coins:

- `BTC`
- `ETH`
- `SOL`
- `BNB`

## External Dependencies

- Coinbase spot price API
- RabbitMQ
- History service

## Environment Variables

- `RABBITMQ_HOST`
- `RABBITMQ_USER`
- `RABBITMQ_PASS`
- `RABBITMQ_QUEUE`
- `HISTORY_HOST`

These variables are rendered by Ansible into `proxy.service`.

## Systemd

Unit template:

- `ansible/roles/proxy/templates/proxy.service.j2`

Useful commands on `devops-proxy`:

```bash
sudo systemctl status proxy
sudo journalctl -u proxy.service -n 50
sudo systemctl cat proxy.service
sudo systemctl show proxy.service -p Environment
```

## Common Problems

### `RabbitMQ error: 'NoneType' object has no attribute 'encode'`

Cause:

- one of the RabbitMQ environment variables is missing, usually `RABBITMQ_PASS`

Check:

```bash
sudo systemctl cat proxy.service
sudo systemctl show proxy.service -p Environment
```

### Prices are inserted in unexpected order

Cause:

- prices are fetched sequentially
- whichever response is processed first reaches RabbitMQ and PostgreSQL first
- rows with equal timestamps need explicit SQL ordering if a fixed display order is required

## Notes

- this service uses Flask's built-in server
- background updates run every 3 minutes

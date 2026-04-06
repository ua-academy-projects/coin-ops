# Proxy Role

Deploys the Go microservice acting as an API gateway between the Frontend and the external world. Targeted at `vm2`.

## Tasks
1. Installs `golang` from the default repositories.
2. Compiles the Golang source code, dropping the built binary (`proxy.bin`) directly into the `shared_folder`.
3. Generates `proxy.env` dynamically via Jinja2 templating (assigning AMQP credentials and routing details).
4. Copies, enables, and restarts the `proxy.service` (Systemd).

## Role Variables
Expects the following variables from `group_vars/all`:
- `proxy_listen`
- `mq_enabled`
- `rabbitmq_url`, `rabbitmq_exchange`, `rabbitmq_routing_key`

## Dependencies
The `message_queue` role must be successfully provisioned and running for the Proxy to open AMQP connections.

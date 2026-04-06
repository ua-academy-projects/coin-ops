# History Service Role

A multi-purpose Python application running an HTTP API for historical analytics and a RabbitMQ Consumer polling for persistence. Targeted at `vm3`.

## Tasks
1. Installs Python dependencies: `python3`, `python3-pip`, `python3-venv`, `python3-flask`.
2. Creates a Virtual Environment (`venv`) and installs project dependencies from `requirements.txt`.
3. Templates `history_service.env.j2`, passing environment variables for both PostgreSQL and RabbitMQ setups.
4. Registers and starts the `history_service.service` systemd unit.

## Role Variables
Configured using the following variables from `group_vars/all`:
- DB: `pg_host`, `pg_port`, `pg_user`, `pg_password`, `pg_database`
- MQ: `rabbitmq_url`, `rabbitmq_exchange`, `rabbitmq_queue`, `rabbitmq_routing_key`
- Service config: `mq_consumer_enabled`, `http_api_enabled`, `history_listen`, `history_port`

## Dependencies
Requires active network paths to PostgreSQL (`database` role at `vm5`) and RabbitMQ (`message_queue` role at `vm4`).

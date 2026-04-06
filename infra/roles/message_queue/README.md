# Message Queue Role

Installs and configures RabbitMQ. The broker receives `snapshot_event` messages from the Proxy service and delivers them to the History Service for persistence. Targeted at `vm4`.

## Tasks
1. Installs the `rabbitmq-server` system package.
2. Enables and starts the RabbitMQ `systemd` service.
3. Creates a dedicated RabbitMQ user (with defined passwords from Vault) and sets full vhost privileges.

## Role Variables
Expects the following variables from `group_vars/all`:
- `rabbitmq_user` (encrypted, from vault.yml)
- `rabbitmq_password` (encrypted, from vault.yml)

## Dependencies
Requires the `base` role.

# RabbitMQ Queue Service

Running on: server03 (192.168.0.105)
Managed by: Ansible playbook (ansible/playbooks/server03.yml)

## Users
- proxy_user — write permissions (publishes messages)
- history_user — read permissions (consumes messages)

## Queue
- Name: rates
- Used to pass rate data from proxy service to history service

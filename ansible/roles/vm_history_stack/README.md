# vm_history_stack
Full lifecycle (system prep + docker install + registry login + service
deploy) for a VM-mode history node — PostgreSQL + RabbitMQ + history-api +
history-consumer.

Applied to `hosts: history` by `deploy.yml`.

Imports: [[common]], [[docker]], [[registry_login]], [[history]].

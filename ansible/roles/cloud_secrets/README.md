# cloud_secrets
Resolve DB password / RabbitMQ password / GHCR token from the active cloud's
secret manager (AWS Secrets Manager or GCP Secret Manager) and publish them
as host facts onto every host in the `cloud` inventory group.

**Where it runs:** on the controller (`hosts: localhost`, `connection: local`).
Run as the first play of `cloud-deploy.yml` before any role that needs
resolved secret values on cloud hosts.

**Reads:** `coinops_*_secret_ref` host vars on the first cloud host (set by
Terraform-generated inventory) plus env fallbacks (`DB_PASSWORD`,
`RABBITMQ_PASSWORD`, `GHCR_TOKEN`).

**Writes:** `coinops_db_password`, `coinops_rabbitmq_password`,
`coinops_ghcr_token` onto every host in `groups['cloud']` via `add_host`.

Behaves as the previous inline secrets-fetch play in `cloud-deploy.yml`.

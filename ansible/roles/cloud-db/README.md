# cloud-db

Deploy PostgreSQL (and optionally RabbitMQ + Redis when
`runtime_backend == "external"`) on a private VM behind the cloud app stack.
Applies the history schema and — when `runtime_backend == "postgres"` — the
runtime queue/session schema, persists the runtime app role, and verifies
both extensions and cron jobs.

**Where it runs:** on every host in the `db` inventory group.

**Skipped entirely when** `runtime_backend == "cloud_native"` — that path uses
managed RDS bootstrapped by the [[cloud-db-bootstrap]] role instead.

**Reads:** `db_user` / `db_password` / `db_name` / `runtime_backend` from
[[cloud-secrets]] + `group_vars/all/main.yml`.

**Produces:** `/etc/cognitor/cloud-db.env`, `/opt/cognitor/cloud-db/compose.yaml`,
running postgres (+ rabbitmq/redis in external mode) containers, applied
schemas.

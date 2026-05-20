# cloud-db-stack

Full lifecycle (system prep + docker install + registry login + DB deploy)
for the cloud private DB/runtime node — Postgres (+ RabbitMQ + Redis in
`external` runtime) on a dedicated VM behind the cloud app stack.

Applied to `hosts: db` by `cloud-deploy.yml`.

**No-op when** `runtime_backend == "cloud_native"` — managed RDS / Cloud SQL
replaces this node and gets schema-bootstrapped by [[cloud-db-bootstrap]]
inside the [[cloud-app-stack]] instead.

Imports: [[common]], [[docker]], [[registry-login]], [[cloud-db]].

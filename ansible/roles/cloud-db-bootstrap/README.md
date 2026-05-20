# cloud-db-bootstrap

Apply the history schema and (when `session_backend == "postgres"`) the
cloud-native session schema to the managed cloud-native database
(`cloud_db_host`), using `psql` from the app VMs.

**Where it runs:** on the `app` inventory group, gated by
`run_once: true` so the schema is applied exactly once per play.

**Skipped entirely unless** `runtime_backend == "cloud_native"`.

**Reads:** `cloud_db_host`, `db_port`, `db_user`, `db_password`, `db_name`,
`session_backend` from [[cloud-secrets]] + `group_vars/all/main.yml`.

**Produces:** `/opt/cognitor/managed-db/` with the SQL files on disk, plus
the applied schemas inside the managed DB instance.

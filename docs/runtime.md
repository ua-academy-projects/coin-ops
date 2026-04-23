# Runtime layer — operator runbook

> Design rationale: see [ADR 0001](adr/0001-postgres-runtime.md). This
> document is the operator-facing view; the ADR is the decision record.

## Postgres image requirements

The runtime layer depends on two extensions:

- `pg_cron` — scheduled TTL reap of `runtime.cache` and `runtime.session`.
- `pgmq` — queue primitives used by the sibling branch.

Neither ships in the stock `postgres:16-alpine` image referenced by
`deploy/compose/node-01.compose.yaml` today, so a custom image is
required. Per ADR §9.1, the chosen base is
`quay.io/tembo/pg16-pgmq` with `postgresql-16-cron` layered on top.

At a minimum, whichever image is used, the Postgres process must start
with:

```conf
shared_preload_libraries = 'pg_cron,pgmq'
cron.database_name       = 'cognitor'   # optional — jobs pin themselves via schedule_in_database
```

`shared_preload_libraries` can only be changed via `postgresql.conf` (or
an equivalent `-c` command-line flag) and requires a server restart;
`CREATE EXTENSION` alone is not enough.

## One-time bootstrap

Run as a superuser, or as a role with `CREATE EXTENSION` privilege. From
the repository root:

```bash
# 1. Pin the application role the cache/session wrappers will GRANT EXECUTE to.
psql "$DATABASE_URL" -c "ALTER DATABASE $PGDATABASE SET runtime.app_role = 'cognitor_app';"

# 2. Apply the schema, wrappers, and pg_cron schedules.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f runtime/00_run_all.sql

# 3. Verify.
psql "$DATABASE_URL" \
  -c "SELECT jobname, schedule, active FROM cron.job WHERE jobname LIKE 'runtime-%';"
```

Step 1 must happen **before** step 2. The wrappers in
`runtime/07_cache_wrappers.sql` are `SECURITY DEFINER` and revoke
`EXECUTE` from `PUBLIC` unconditionally; they only grant `EXECUTE` to the
role named by the `runtime.app_role` GUC. If the GUC is unset at load
time, the REVOKE runs, the GRANT is skipped, and the proxy will get
permission-denied on its first `runtime.cache_*` call. Recover by
setting the GUC and re-running `runtime/07_cache_wrappers.sql`.

`runtime/00_run_all.sql` uses `\i` with repository-relative paths and
must be run from the repo root.

## Running the smoke tests

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f runtime/tests/test_runtime.sql
```

Seven `PASS` notices confirm that:

- `cache_set` / `cache_get` / `cache_delete` round-trip correctly.
- `cache_get` filters expired rows before the reaper runs.
- `cache_reap` physically removes expired rows.
- `runtime.session_*` round-trip correctly.
- `runtime.cache` and `runtime.session` are both `UNLOGGED`.
- All three `runtime-*` jobs are registered in `cron.job` and active.

A single `FAIL` raises an exception and stops the script.

## Known behaviour

- `runtime-dlq-reap` (nightly at 03:00 UTC) calls `runtime.dlq_reap_expired()`,
  which is defined on the queue side of the runtime layer
  (`runtime/05_dlq.sql`). pg_cron stores scheduled commands as plain text and
  does not validate them at schedule time, so the job is registered
  successfully regardless of whether the function exists — only the firing
  will error if it is missing. With the full bootstrap applied via
  `runtime/00_run_all.sql` the function is present and the job succeeds; the
  caveat is documented here in case the cache layer is ever bootstrapped in
  isolation.

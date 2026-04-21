-- =============================================================================
-- runtime/00_run_all.sql
-- Bootstrap script for the runtime cache/session layer.
-- Use this for a fresh install or after a clean wipe.
--
-- Usage:
--   psql $DATABASE_URL -f runtime/00_run_all.sql
--
-- Requirements:
--   • The executing role must have CREATE EXTENSION privilege (for pg_cron),
--     or the extension must already be installed by a superuser.
--   • shared_preload_libraries must include 'pg_cron,pgmq' in postgresql.conf
--     (see ADR §9).
--
-- Merge note:
--   This branch (feature/postgres-runtime-cache) ships [6/8] … [8/8] only.
--   The queue branch (postgres-runtime-queue) owns [1/5] … [5/5]. When both
--   branches converge on dev, concatenate this file with queue's 00_run_all.sql
--   — queue lines first, cache lines after — and update the counters to /8.
-- =============================================================================

\echo '>>> [6/8] cache/session schema + pg_cron extension'
\i runtime/06_cache_schema.sql

\echo '>>> [7/8] cache/session wrappers'
\i runtime/07_cache_wrappers.sql

\echo '>>> [8/8] pg_cron schedules'
\i runtime/08_cron.sql

\echo '>>> runtime cache/session bootstrap complete.'
\echo '    Verify with: SELECT jobname, schedule, active FROM cron.job WHERE jobname LIKE ''runtime-%'';'

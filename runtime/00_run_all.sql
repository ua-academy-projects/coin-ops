-- =============================================================================
-- runtime/00_run_all.sql
-- Master bootstrap script. Runs all runtime SQL files in order.
-- Use this for a fresh install or after a clean wipe.
--
-- Usage:
--   psql $DATABASE_URL -f runtime/00_run_all.sql
--
-- Requirements:
--   • The executing role must have CREATE EXTENSION privilege, or pgmq must
--     already be installed by a superuser.
--   • Run as a role that owns (or can create objects in) the target database.
-- =============================================================================

\echo '>>> [1/5] runtime schema + pgmq + tables'
\i runtime/01_schema.sql

\echo '>>> [2/5] queue wrappers (enqueue / claim / ack / fail)'
\i runtime/02_wrappers.sql

\echo '>>> [3/5] LISTEN/NOTIFY trigger + queue_depth view'
\i runtime/03_notify.sql

\echo '>>> [4/5] advisory lock helpers'
\i runtime/04_advisory.sql

\echo '>>> [5/5] DLQ management functions'
\i runtime/05_dlq.sql

\echo '>>> runtime schema bootstrap complete.'
\echo '    Verify with: SELECT * FROM runtime.queue_depth;'

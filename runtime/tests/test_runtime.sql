-- =============================================================================
-- runtime/tests/test_runtime.sql
-- Smoke tests / acceptance criteria for the cache/session layer.
--
-- Run against a live PostgreSQL instance with the runtime schema applied:
--   psql $DATABASE_URL -f runtime/tests/test_runtime.sql
--
-- Each test uses a DO block that raises EXCEPTION on failure and NOTICE on pass.
-- =============================================================================

\echo '=== runtime cache/session acceptance tests ==='

-- ── Test 1: cache_set + cache_get round-trip ────────────────────────────────
DO $$
DECLARE
    v_got JSONB;
BEGIN
    PERFORM runtime.cache_set('t1', '{"x":1}'::JSONB, '1 hour');
    SELECT runtime.cache_get('t1') INTO v_got;

    IF v_got IS NULL OR v_got <> '{"x":1}'::JSONB THEN
        RAISE EXCEPTION 'FAIL test1: cache_get returned %, want {"x":1}', v_got;
    END IF;

    RAISE NOTICE 'PASS test1: cache_set + cache_get round-trip';
END;
$$;

-- ── Test 2: cache_delete hit/miss semantics ─────────────────────────────────
DO $$
DECLARE
    v_hit  BOOLEAN;
    v_miss BOOLEAN;
BEGIN
    v_hit  := runtime.cache_delete('t1');
    v_miss := runtime.cache_delete('t1');

    IF v_hit IS NOT TRUE THEN
        RAISE EXCEPTION 'FAIL test2: delete on existing key returned %, want true', v_hit;
    END IF;

    IF v_miss IS NOT FALSE THEN
        RAISE EXCEPTION 'FAIL test2: delete on absent key returned %, want false', v_miss;
    END IF;

    RAISE NOTICE 'PASS test2: cache_delete hit=true / miss=false';
END;
$$;

-- ── Test 3: cache_get filters expired rows pre-reap ─────────────────────────
DO $$
DECLARE
    v_got JSONB;
BEGIN
    PERFORM runtime.cache_set('t3', '{"x":3}'::JSONB, '10 milliseconds');
    PERFORM pg_sleep(0.05);

    SELECT runtime.cache_get('t3') INTO v_got;
    IF v_got IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL test3: cache_get returned % for expired row, want NULL', v_got;
    END IF;

    -- Row is still physically present — reap lives in test 4.
    IF (SELECT COUNT(*) FROM runtime.cache WHERE key = 't3') <> 1 THEN
        RAISE EXCEPTION 'FAIL test3: expired row missing from physical storage';
    END IF;

    RAISE NOTICE 'PASS test3: cache_get hides rows past expires_at';
END;
$$;

-- ── Test 4: cache_reap removes expired rows ─────────────────────────────────
DO $$
DECLARE
    v_reaped INT;
    v_left   INT;
BEGIN
    v_reaped := runtime.cache_reap();

    IF v_reaped < 1 THEN
        RAISE EXCEPTION 'FAIL test4: cache_reap returned %, want >= 1', v_reaped;
    END IF;

    SELECT COUNT(*) INTO v_left FROM runtime.cache WHERE key = 't3';
    IF v_left <> 0 THEN
        RAISE EXCEPTION 'FAIL test4: runtime.cache still has % row(s) for t3 after reap', v_left;
    END IF;

    RAISE NOTICE 'PASS test4: cache_reap deleted % expired row(s)', v_reaped;
END;
$$;

-- ── Test 5: session round-trip (set/get/delete) ─────────────────────────────
DO $$
DECLARE
    v_got     JSONB;
    v_deleted BOOLEAN;
BEGIN
    PERFORM runtime.session_set('sid-abc', '{"uid":42}'::JSONB, '1 hour');

    SELECT runtime.session_get('sid-abc') INTO v_got;
    IF v_got IS NULL OR v_got <> '{"uid":42}'::JSONB THEN
        RAISE EXCEPTION 'FAIL test5: session_get returned %, want {"uid":42}', v_got;
    END IF;

    v_deleted := runtime.session_delete('sid-abc');
    IF v_deleted IS NOT TRUE THEN
        RAISE EXCEPTION 'FAIL test5: session_delete returned %, want true', v_deleted;
    END IF;

    RAISE NOTICE 'PASS test5: session_set + session_get + session_delete round-trip';
END;
$$;

-- ── Test 6: cache and session tables are UNLOGGED ───────────────────────────
DO $$
DECLARE
    v_cache_persistence   CHAR;
    v_session_persistence CHAR;
BEGIN
    -- relpersistence: 'u' = unlogged, 'p' = permanent, 't' = temp
    SELECT c.relpersistence
    INTO   v_cache_persistence
    FROM   pg_class     c
    JOIN   pg_namespace n ON n.oid = c.relnamespace
    WHERE  n.nspname = 'runtime' AND c.relname = 'cache';

    SELECT c.relpersistence
    INTO   v_session_persistence
    FROM   pg_class     c
    JOIN   pg_namespace n ON n.oid = c.relnamespace
    WHERE  n.nspname = 'runtime' AND c.relname = 'session';

    IF v_cache_persistence <> 'u' THEN
        RAISE EXCEPTION 'FAIL test6: runtime.cache relpersistence = %, want u (UNLOGGED)',
                        v_cache_persistence;
    END IF;

    IF v_session_persistence <> 'u' THEN
        RAISE EXCEPTION 'FAIL test6: runtime.session relpersistence = %, want u (UNLOGGED)',
                        v_session_persistence;
    END IF;

    RAISE NOTICE 'PASS test6: runtime.cache and runtime.session are UNLOGGED';
END;
$$;

-- ── Test 7: pg_cron jobs registered ─────────────────────────────────────────
-- Tolerant of queue files being absent: runtime-dlq-reap references
-- runtime.dlq_reap_expired() from 05_dlq.sql (queue branch). When the cache
-- branch is loaded standalone (without queue), 08_cron.sql still schedules
-- the job — pg_cron does not validate the command at schedule time — so we
-- expect exactly 3 jobs after bootstrap regardless.
DO $$
DECLARE
    v_count INT;
BEGIN
    SELECT COUNT(*)
    INTO   v_count
    FROM   cron.job
    WHERE  jobname IN (
               'runtime-cache-reap',
               'runtime-session-reap',
               'runtime-dlq-reap'
           )
      AND  active;

    IF v_count < 3 THEN
        RAISE EXCEPTION 'FAIL test7: expected 3 active runtime-* cron jobs, got %', v_count;
    END IF;

    RAISE NOTICE 'PASS test7: % runtime-* cron jobs are scheduled and active', v_count;
END;
$$;

\echo '=== all cache/session tests passed ==='

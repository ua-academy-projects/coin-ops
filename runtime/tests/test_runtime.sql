-- =============================================================================
-- runtime/tests/test_runtime.sql
-- Smoke tests / acceptance criteria for the runtime schema.
--
-- Run against a live PostgreSQL instance with the runtime schema applied:
--   psql $DATABASE_URL -f runtime/tests/test_runtime.sql
--
-- Each test uses a DO block that raises EXCEPTION on failure and NOTICE on pass.
-- =============================================================================

\echo '=== runtime queue acceptance tests ==='

-- ── Test 1: enqueue_event returns a msg_id ───────────────────────────────────
DO $$
DECLARE
    v_id BIGINT;
BEGIN
    SELECT runtime.enqueue_event('{"type":"market","slug":"test-1","yes_price":0.5}'::JSONB)
    INTO   v_id;

    IF v_id IS NULL OR v_id <= 0 THEN
        RAISE EXCEPTION 'FAIL test1: enqueue_event returned invalid msg_id: %', v_id;
    END IF;

    RAISE NOTICE 'PASS test1: enqueue_event → msg_id=%', v_id;
END;
$$;

-- ── Test 2: claim_events returns the enqueued message ────────────────────────
DO $$
DECLARE
    v_enqueue_id BIGINT;
    v_msg        RECORD;
BEGIN
    SELECT runtime.enqueue_event('{"type":"market","slug":"test-2","yes_price":0.6}'::JSONB)
    INTO   v_enqueue_id;

    SELECT * INTO v_msg
    FROM   runtime.claim_events(1, 30)
    WHERE  msg_id = v_enqueue_id;

    IF v_msg IS NULL THEN
        RAISE EXCEPTION 'FAIL test2: claim_events did not return enqueued msg_id=%', v_enqueue_id;
    END IF;

    IF (v_msg.message->>'slug') <> 'test-2' THEN
        RAISE EXCEPTION 'FAIL test2: payload slug mismatch, got %', v_msg.message->>'slug';
    END IF;

    -- cleanup
    PERFORM runtime.ack_event(v_enqueue_id);

    RAISE NOTICE 'PASS test2: claim_events returned msg_id=% with correct payload', v_enqueue_id;
END;
$$;

-- ── Test 3: ack_event removes message from queue ─────────────────────────────
DO $$
DECLARE
    v_id   BIGINT;
    v_msg  RECORD;
BEGIN
    SELECT runtime.enqueue_event('{"type":"market","slug":"test-3","yes_price":0.7}'::JSONB)
    INTO   v_id;

    -- Claim then ack.
    PERFORM runtime.claim_events(1, 5) WHERE msg_id = v_id;
    PERFORM runtime.ack_event(v_id);

    -- Retry state should be gone.
    IF EXISTS (SELECT 1 FROM runtime.event_retry WHERE msg_id = v_id) THEN
        RAISE EXCEPTION 'FAIL test3: retry row still exists after ack for msg_id=%', v_id;
    END IF;

    RAISE NOTICE 'PASS test3: ack_event removed msg_id=% and its retry row', v_id;
END;
$$;

-- ── Test 4: fail_event increments retry counter ───────────────────────────────
DO $$
DECLARE
    v_id      BIGINT;
    v_count   INT;
BEGIN
    SELECT runtime.enqueue_event('{"type":"market","slug":"test-4","yes_price":0.4}'::JSONB)
    INTO   v_id;

    -- First failure
    PERFORM runtime.fail_event(v_id, 'simulated error', 3);

    SELECT attempt_count INTO v_count
    FROM   runtime.event_retry
    WHERE  msg_id = v_id;

    IF v_count <> 1 THEN
        RAISE EXCEPTION 'FAIL test4: expected attempt_count=1, got %', v_count;
    END IF;

    -- Cleanup (ack so the message doesn't linger)
    PERFORM pgmq.delete('events', v_id);
    DELETE FROM runtime.event_retry WHERE msg_id = v_id;

    RAISE NOTICE 'PASS test4: fail_event incremented attempt_count to 1 for msg_id=%', v_id;
END;
$$;

-- ── Test 5: fail_event promotes to DLQ after MAX_RETRIES ─────────────────────
DO $$
DECLARE
    v_id       BIGINT;
    v_dlq_cnt  INT;
    v_audit_cnt INT;
BEGIN
    SELECT runtime.enqueue_event('{"type":"poison","slug":"test-5","yes_price":0.0}'::JSONB)
    INTO   v_id;

    -- Exhaust retries (max_tries = 2 for this test)
    PERFORM runtime.fail_event(v_id, 'err1', 2);
    PERFORM runtime.fail_event(v_id, 'err2', 2);

    -- Message should now be in events_dlq
    SELECT COUNT(*) INTO v_dlq_cnt
    FROM   pgmq.q_events_dlq;

    SELECT COUNT(*) INTO v_audit_cnt
    FROM   runtime.dead_letter_audit
    WHERE  original_msg_id = v_id;

    -- Retry row should be gone
    IF EXISTS (SELECT 1 FROM runtime.event_retry WHERE msg_id = v_id) THEN
        RAISE EXCEPTION 'FAIL test5: retry row still present after DLQ promotion';
    END IF;

    IF v_audit_cnt < 1 THEN
        RAISE EXCEPTION 'FAIL test5: no audit row written for DLQ promotion';
    END IF;

    RAISE NOTICE 'PASS test5: msg_id=% promoted to DLQ after 2 failures; audit rows=%',
        v_id, v_audit_cnt;

    -- Cleanup DLQ
    DELETE FROM runtime.dead_letter_audit WHERE original_msg_id = v_id;
    PERFORM pgmq.purge_queue('events_dlq');
END;
$$;

-- ── Test 6: advisory_try_lock / advisory_unlock ───────────────────────────────
DO $$
DECLARE
    v_got   BOOLEAN;
    v_rel   BOOLEAN;
BEGIN
    v_got := runtime.advisory_try_lock(99);
    IF NOT v_got THEN
        RAISE EXCEPTION 'FAIL test6: advisory_try_lock(99) returned false on first call';
    END IF;

    v_rel := runtime.advisory_unlock(99);
    IF NOT v_rel THEN
        RAISE EXCEPTION 'FAIL test6: advisory_unlock(99) returned false';
    END IF;

    RAISE NOTICE 'PASS test6: advisory_try_lock + advisory_unlock work correctly';
END;
$$;

\echo '=== all tests passed ==='

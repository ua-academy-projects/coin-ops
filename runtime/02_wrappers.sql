-- =============================================================================
-- runtime/02_wrappers.sql
-- High-level PL/pgSQL wrappers around raw pgmq calls.
--
-- Functions:
--   runtime.enqueue_event(payload JSONB)          → BIGINT  (msg_id)
--   runtime.claim_events(n INT, vt INT)           → SETOF pgmq.message_record
--   runtime.ack_event(msg_id BIGINT)              → VOID
--   runtime.fail_event(msg_id BIGINT, err TEXT)   → VOID
--
-- All wrappers are SECURITY DEFINER so application roles only need EXECUTE on
-- the wrapper, not direct access to pgmq internals.
--
-- Run after 01_schema.sql.
-- =============================================================================

-- ── enqueue_event ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION runtime.enqueue_event(
    p_payload JSONB
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = runtime, public
AS $$
DECLARE
    v_msg_id BIGINT;
BEGIN
    -- pgmq.send returns the assigned message id.
    SELECT pgmq.send('events', p_payload)
    INTO   v_msg_id;

    -- Initialise retry counter for this message.
    INSERT INTO runtime.event_retry (msg_id, queue_name)
    VALUES (v_msg_id, 'events')
    ON CONFLICT (msg_id) DO NOTHING;

    -- Wake up any LISTEN-based consumers immediately (see 03_notify.sql).
    PERFORM pg_notify('runtime_events', v_msg_id::TEXT);

    RETURN v_msg_id;
END;
$$;

COMMENT ON FUNCTION runtime.enqueue_event(JSONB) IS
  'Push a JSON payload onto the events queue and notify waiting consumers. '
  'Returns the pgmq message id.';

-- ── claim_events ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION runtime.claim_events(
    p_n  INT     DEFAULT 1,    -- number of messages to claim in one call
    p_vt INT     DEFAULT 30    -- visibility timeout in seconds
)
RETURNS SETOF pgmq.message_record
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = runtime, public
AS $$
BEGIN
    -- pgmq.read hides claimed messages from other consumers for p_vt seconds.
    -- If the consumer crashes without calling ack_event() the message becomes
    -- visible again after the timeout (at-least-once delivery).
    RETURN QUERY
        SELECT * FROM pgmq.read('events', p_vt, p_n);
END;
$$;

COMMENT ON FUNCTION runtime.claim_events(INT, INT) IS
  'Claim up to p_n events from the queue with a p_vt-second visibility window. '
  'Un-acked messages re-appear automatically after vt expires.';

-- ── ack_event ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION runtime.ack_event(
    p_msg_id BIGINT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = runtime, public
AS $$
BEGIN
    -- Permanently remove the message from the queue.
    PERFORM pgmq.delete('events', p_msg_id);

    -- Clean up retry state — no longer needed.
    DELETE FROM runtime.event_retry WHERE msg_id = p_msg_id;
END;
$$;

COMMENT ON FUNCTION runtime.ack_event(BIGINT) IS
  'Acknowledge successful processing: deletes the message and its retry record.';

-- ── fail_event ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION runtime.fail_event(
    p_msg_id    BIGINT,
    p_error     TEXT    DEFAULT NULL,
    p_max_tries INT     DEFAULT 3
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = runtime, public
AS $$
DECLARE
    v_attempts  INT;
    v_payload   JSONB;
BEGIN
    -- ── 1. Increment attempt counter ─────────────────────────────────────────
    UPDATE runtime.event_retry
    SET    attempt_count  = attempt_count + 1,
           last_error     = p_error,
           last_failed_at = NOW()
    WHERE  msg_id = p_msg_id
    RETURNING attempt_count INTO v_attempts;

    IF NOT FOUND THEN
        -- Safety net: retry row was missing (e.g. message pre-dated this schema).
        INSERT INTO runtime.event_retry (msg_id, attempt_count, last_error, last_failed_at)
        VALUES (p_msg_id, 1, p_error, NOW())
        RETURNING attempt_count INTO v_attempts;
    END IF;

    -- ── 2. Decide: retry or DLQ ──────────────────────────────────────────────
    IF v_attempts < p_max_tries THEN
        -- Release the visibility lock so the message becomes claimable again
        -- after an exponential back-off (2^attempt * 5 s, capped at 120 s).
        PERFORM pgmq.set_vt(
            'events',
            p_msg_id,
            LEAST(120, (5 * (2 ^ v_attempts))::INT)
        );
        RAISE NOTICE 'runtime.fail_event: msg_id=% attempt=%/% — will retry in ~%s',
            p_msg_id, v_attempts, p_max_tries,
            LEAST(120, (5 * (2 ^ v_attempts))::INT);
    ELSE
        -- ── 3. Promote to DLQ ────────────────────────────────────────────────
        -- Read the raw payload before deleting.
        SELECT message
        INTO   v_payload
        FROM   pgmq.q_events          -- pgmq internal table for 'events' queue
        WHERE  msg_id = p_msg_id;

        IF v_payload IS NULL THEN
            -- Message may have already been deleted; record what we know.
            v_payload := jsonb_build_object(
                '_dlq_warning', 'original payload not found',
                '_msg_id',      p_msg_id
            );
        END IF;

        -- Move message to DLQ queue.
        PERFORM pgmq.send('events_dlq', v_payload);

        -- Write audit row.
        INSERT INTO runtime.dead_letter_audit
            (original_msg_id, queue_name, payload, last_error, attempt_count)
        VALUES
            (p_msg_id, 'events', v_payload, p_error, v_attempts);

        -- Remove from primary queue and retry table.
        PERFORM pgmq.delete('events', p_msg_id);
        DELETE FROM runtime.event_retry WHERE msg_id = p_msg_id;

        RAISE WARNING 'runtime.fail_event: msg_id=% moved to events_dlq after % attempts. error: %',
            p_msg_id, v_attempts, p_error;
    END IF;
END;
$$;

COMMENT ON FUNCTION runtime.fail_event(BIGINT, TEXT, INT) IS
  'Record a processing failure. Re-schedules the message with exponential back-off '
  'until p_max_tries is reached, then promotes to events_dlq.';

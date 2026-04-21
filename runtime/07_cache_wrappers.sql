-- =============================================================================
-- runtime/07_cache_wrappers.sql
-- High-level PL/pgSQL wrappers around runtime.cache and runtime.session.
--
-- Functions:
--   runtime.cache_set   (key, value, ttl)   → VOID
--   runtime.cache_get   (key)               → JSONB   (NULL if missing/expired)
--   runtime.cache_delete(key)               → BOOLEAN (true on hit)
--   runtime.cache_reap  ()                  → INT     (rows deleted)
--
--   runtime.session_set   (sid, data, ttl)  → VOID
--   runtime.session_get   (sid)             → JSONB
--   runtime.session_delete(sid)             → BOOLEAN
--   runtime.session_reap  ()                → INT
--
-- All wrappers are SECURITY DEFINER so application roles only need EXECUTE on
-- the wrapper, not direct access to the underlying tables.
--
-- Run after 06_cache_schema.sql.
-- =============================================================================

-- ── cache_set ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION runtime.cache_set(
    p_key   TEXT,
    p_value JSONB,
    p_ttl   INTERVAL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = runtime, public
AS $$
BEGIN
    INSERT INTO runtime.cache (key, value, expires_at, updated_at)
    VALUES (p_key, p_value, NOW() + p_ttl, NOW())
    ON CONFLICT (key) DO UPDATE
        SET value      = EXCLUDED.value,
            expires_at = EXCLUDED.expires_at,
            updated_at = EXCLUDED.updated_at;
END;
$$;

COMMENT ON FUNCTION runtime.cache_set(TEXT, JSONB, INTERVAL) IS
  'UPSERT a cache entry with a relative TTL (INTERVAL).';

-- ── cache_get ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION runtime.cache_get(
    p_key TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = runtime, public
AS $$
DECLARE
    v_value JSONB;
BEGIN
    -- Filter on expires_at so expired rows are invisible even before the
    -- reaper deletes them physically.
    SELECT value
    INTO   v_value
    FROM   runtime.cache
    WHERE  key        = p_key
      AND  expires_at > NOW();

    RETURN v_value;
END;
$$;

COMMENT ON FUNCTION runtime.cache_get(TEXT) IS
  'Return cache value or NULL if missing or past expires_at.';

-- ── cache_delete ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION runtime.cache_delete(
    p_key TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = runtime, public
AS $$
DECLARE
    v_rows INT;
BEGIN
    DELETE FROM runtime.cache WHERE key = p_key;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RETURN v_rows > 0;
END;
$$;

COMMENT ON FUNCTION runtime.cache_delete(TEXT) IS
  'Remove a cache entry. Returns true if a row was deleted, false otherwise.';

-- ── cache_reap ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION runtime.cache_reap()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = runtime, public
AS $$
DECLARE
    v_rows INT;
BEGIN
    DELETE FROM runtime.cache WHERE expires_at < NOW();
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RETURN v_rows;
END;
$$;

COMMENT ON FUNCTION runtime.cache_reap() IS
  'Delete expired rows from runtime.cache. Scheduled by 08_cron.sql.';

-- ── session_set ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION runtime.session_set(
    p_sid  TEXT,
    p_data JSONB,
    p_ttl  INTERVAL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = runtime, public
AS $$
BEGIN
    INSERT INTO runtime.session (sid, data, expires_at, updated_at)
    VALUES (p_sid, p_data, NOW() + p_ttl, NOW())
    ON CONFLICT (sid) DO UPDATE
        SET data       = EXCLUDED.data,
            expires_at = EXCLUDED.expires_at,
            updated_at = EXCLUDED.updated_at;
END;
$$;

COMMENT ON FUNCTION runtime.session_set(TEXT, JSONB, INTERVAL) IS
  'UPSERT a session row with a relative TTL (INTERVAL).';

-- ── session_get ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION runtime.session_get(
    p_sid TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = runtime, public
AS $$
DECLARE
    v_data JSONB;
BEGIN
    SELECT data
    INTO   v_data
    FROM   runtime.session
    WHERE  sid        = p_sid
      AND  expires_at > NOW();

    RETURN v_data;
END;
$$;

COMMENT ON FUNCTION runtime.session_get(TEXT) IS
  'Return session data or NULL if missing or past expires_at.';

-- ── session_delete ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION runtime.session_delete(
    p_sid TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = runtime, public
AS $$
DECLARE
    v_rows INT;
BEGIN
    DELETE FROM runtime.session WHERE sid = p_sid;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RETURN v_rows > 0;
END;
$$;

COMMENT ON FUNCTION runtime.session_delete(TEXT) IS
  'Remove a session row. Returns true if a row was deleted, false otherwise.';

-- ── session_reap ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION runtime.session_reap()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = runtime, public
AS $$
DECLARE
    v_rows INT;
BEGIN
    DELETE FROM runtime.session WHERE expires_at < NOW();
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RETURN v_rows;
END;
$$;

COMMENT ON FUNCTION runtime.session_reap() IS
  'Delete expired rows from runtime.session. Scheduled by 08_cron.sql.';

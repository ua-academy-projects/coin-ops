CREATE SCHEMA IF NOT EXISTS runtime;

CREATE TABLE IF NOT EXISTS runtime.session (
    sid        TEXT        PRIMARY KEY,
    data       JSONB       NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_runtime_session_expires_at
    ON runtime.session (expires_at);

CREATE OR REPLACE FUNCTION runtime.session_get(p_sid TEXT)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_data JSONB;
BEGIN
    SELECT data INTO v_data
    FROM runtime.session
    WHERE sid = p_sid
      AND expires_at > NOW();

    RETURN v_data;
END;
$$;

CREATE OR REPLACE FUNCTION runtime.session_set(p_sid TEXT, p_data JSONB, p_ttl INTERVAL)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM runtime.session WHERE expires_at <= NOW();

    INSERT INTO runtime.session (sid, data, expires_at, updated_at)
    VALUES (p_sid, p_data, NOW() + p_ttl, NOW())
    ON CONFLICT (sid) DO UPDATE
    SET data = EXCLUDED.data,
        expires_at = EXCLUDED.expires_at,
        updated_at = NOW();
END;
$$;

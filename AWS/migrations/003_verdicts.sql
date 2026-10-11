-- Applied transactionally by registry.cli; do not edit after deployment.
CREATE TABLE IF NOT EXISTS kilnwatch.verdicts (
    verdict_id uuid PRIMARY KEY,
    kiln_id text NOT NULL REFERENCES kilnwatch.candidates,
    outcome text NOT NULL CHECK (outcome IN ('confirmed','compliant','not_a_kiln','closed')),
    note text CHECK (char_length(note) <= 2000),
    recorded_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    body_sha256 text NOT NULL CHECK (body_sha256 ~ '^[0-9a-f]{64}$'),
    photos jsonb NOT NULL CHECK (jsonb_typeof(photos) = 'array' AND jsonb_array_length(photos) <= 8)
);
CREATE INDEX IF NOT EXISTS verdicts_latest_idx ON kilnwatch.verdicts (kiln_id, recorded_at DESC);
CREATE TABLE IF NOT EXISTS kilnwatch.verdict_days (
    day date PRIMARY KEY,
    count integer NOT NULL CHECK (count BETWEEN 0 AND 30)
);
DO $$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'kilnwatch_verdict_writer') THEN
        CREATE ROLE kilnwatch_verdict_writer NOLOGIN;
    END IF;
END $$;
REVOKE ALL ON kilnwatch.verdicts, kilnwatch.verdict_days FROM PUBLIC;
GRANT USAGE ON SCHEMA kilnwatch TO kilnwatch_verdict_writer;
GRANT SELECT ON kilnwatch.candidates TO kilnwatch_verdict_writer;
GRANT SELECT, INSERT ON kilnwatch.verdicts TO kilnwatch_verdict_writer;
GRANT SELECT, INSERT, UPDATE ON kilnwatch.verdict_days TO kilnwatch_verdict_writer;
GRANT UPDATE (status, review_state) ON kilnwatch.candidates TO kilnwatch_verdict_writer;
GRANT SELECT (kiln_id, outcome, recorded_at) ON kilnwatch.verdicts TO kilnwatch_reader;

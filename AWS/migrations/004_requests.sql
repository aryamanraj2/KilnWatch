-- Applied transactionally by registry.cli; do not edit after deployment.
CREATE TABLE IF NOT EXISTS kilnwatch.inspection_requests (
    request_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    kiln_id text NOT NULL REFERENCES kilnwatch.candidates,
    client_hash text NOT NULL CHECK (client_hash ~ '^[0-9a-f]{64}$'),
    concerns text[] NOT NULL CHECK (cardinality(concerns) BETWEEN 1 AND 4
        AND array_position(concerns,NULL) IS NULL
        AND concerns <@ ARRAY['smoke_or_ash','near_homes','near_school_or_hospital','other']::text[]),
    distance_band text NOT NULL CHECK (distance_band IN ('under_1km','1_to_5km','over_5km','not_said')),
    lang text NOT NULL CHECK (lang IN ('en','hi')),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (kiln_id,client_hash)
);
CREATE INDEX IF NOT EXISTS inspection_requests_kiln_idx ON kilnwatch.inspection_requests (kiln_id);
CREATE TABLE IF NOT EXISTS kilnwatch.request_days (
    day date PRIMARY KEY,
    count integer NOT NULL CHECK (count BETWEEN 0 AND 300)
);
DO $$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='kilnwatch_request_writer') THEN
        CREATE ROLE kilnwatch_request_writer NOLOGIN;
    END IF;
END $$;
REVOKE ALL ON kilnwatch.inspection_requests,kilnwatch.request_days FROM PUBLIC;
GRANT USAGE ON SCHEMA kilnwatch TO kilnwatch_request_writer;
GRANT SELECT ON kilnwatch.candidates TO kilnwatch_request_writer;
GRANT SELECT,INSERT ON kilnwatch.inspection_requests TO kilnwatch_request_writer;
GRANT SELECT,INSERT,UPDATE ON kilnwatch.request_days TO kilnwatch_request_writer;
GRANT SELECT (kiln_id,concerns,distance_band,created_at) ON kilnwatch.inspection_requests TO kilnwatch_reader;
-- Disposable test databases may not have the separately provisioned existing login.
DO $$ BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname='kilnwatch_verdicts') THEN
        GRANT kilnwatch_request_writer TO kilnwatch_verdicts;
    END IF;
END $$;

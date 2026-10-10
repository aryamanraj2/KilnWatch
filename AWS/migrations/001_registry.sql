-- Applied transactionally by registry.cli; do not edit after deployment.
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE SCHEMA IF NOT EXISTS kilnwatch;
CREATE TABLE IF NOT EXISTS kilnwatch.import_runs (
    run_id text PRIMARY KEY CHECK (run_id ~ '^[0-9a-f]{64}$'),
    input_sha256 text NOT NULL CHECK (input_sha256 ~ '^[0-9a-f]{64}$'),
    evidence_sha256 text CHECK (evidence_sha256 ~ '^[0-9a-f]{64}$'),
    model_sha256 text NOT NULL CHECK (model_sha256 ~ '^[0-9a-f]{64}$'),
    imported_at timestamptz NOT NULL DEFAULT now(),
    record_count integer NOT NULL CHECK (record_count >= 0)
);
CREATE TABLE IF NOT EXISTS kilnwatch.candidates (
    kiln_id text PRIMARY KEY,
    district text NOT NULL,
    status text NOT NULL DEFAULT 'flagged' CHECK (status IN ('flagged','confirmed','compliant','not_a_kiln','closed')),
    review_state text NOT NULL DEFAULT 'pending',
    assessment jsonb NOT NULL DEFAULT '{}'::jsonb,
    first_seen timestamptz NOT NULL,
    last_seen timestamptz NOT NULL CHECK (last_seen >= first_seen)
);
CREATE INDEX IF NOT EXISTS candidates_read_idx ON kilnwatch.candidates (district, status, kiln_id);
CREATE TABLE IF NOT EXISTS kilnwatch.observations (
    observation_id text PRIMARY KEY CHECK (observation_id ~ '^[0-9a-f]{64}$'),
    kiln_id text NOT NULL REFERENCES kilnwatch.candidates,
    scene_id text NOT NULL,
    acquired_at timestamptz NOT NULL,
    model_sha256 text NOT NULL CHECK (model_sha256 ~ '^[0-9a-f]{64}$'),
    footprint geometry(Polygon,4326) NOT NULL CHECK (ST_IsValid(footprint) AND NOT ST_IsEmpty(footprint)),
    payload jsonb NOT NULL
);
CREATE INDEX IF NOT EXISTS observations_spatial_idx ON kilnwatch.observations USING gist(footprint);
CREATE INDEX IF NOT EXISTS observations_kiln_idx ON kilnwatch.observations (kiln_id, acquired_at DESC, observation_id);
CREATE TABLE IF NOT EXISTS kilnwatch.run_observations (
    run_id text NOT NULL REFERENCES kilnwatch.import_runs,
    observation_id text NOT NULL REFERENCES kilnwatch.observations,
    PRIMARY KEY (run_id, observation_id)
);
CREATE TABLE IF NOT EXISTS kilnwatch.evidence (
    observation_id text NOT NULL REFERENCES kilnwatch.observations,
    side text NOT NULL CHECK (side IN ('before','after')),
    sha256 text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
    object_key text NOT NULL CHECK (object_key = 'evidence/' || sha256 || '.png'),
    metadata jsonb NOT NULL,
    PRIMARY KEY (observation_id, side)
);
-- Runtime account credentials are provisioned separately by the AWS teammate.
DO $$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'kilnwatch_reader') THEN
        CREATE ROLE kilnwatch_reader NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'kilnwatch_importer') THEN
        CREATE ROLE kilnwatch_importer NOLOGIN;
    END IF;
END $$;
REVOKE ALL ON SCHEMA kilnwatch FROM PUBLIC;
GRANT USAGE ON SCHEMA kilnwatch TO kilnwatch_reader, kilnwatch_importer;
GRANT SELECT ON ALL TABLES IN SCHEMA kilnwatch TO kilnwatch_reader, kilnwatch_importer;
GRANT INSERT ON kilnwatch.import_runs, kilnwatch.run_observations, kilnwatch.candidates,
    kilnwatch.observations, kilnwatch.evidence TO kilnwatch_importer;
-- Imports may only update observation times and evidence, never human decisions.
GRANT UPDATE (first_seen,last_seen) ON kilnwatch.candidates TO kilnwatch_importer;
GRANT UPDATE (metadata,sha256,object_key) ON kilnwatch.evidence TO kilnwatch_importer;

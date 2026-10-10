-- Applied transactionally by registry.cli; do not edit after deployment.
-- Rules-engine results: a role that may write candidates.assessment and nothing else.
DO $$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'kilnwatch_assessor') THEN
        CREATE ROLE kilnwatch_assessor NOLOGIN;
    END IF;
END $$;
GRANT USAGE ON SCHEMA kilnwatch TO kilnwatch_assessor;
GRANT SELECT ON kilnwatch.candidates, kilnwatch.observations TO kilnwatch_assessor;
GRANT UPDATE (assessment) ON kilnwatch.candidates TO kilnwatch_assessor;

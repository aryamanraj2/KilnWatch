"""Administrative credential provisioning. Run ONLY after authorized AWS deployment/migration.
DB_SECRET must be the master secret; REGISTRY_READER_SECRET the empty dedicated secret.
Never prints credentials; runtime Lambda has no permission to execute this operation.
"""
import os
from contextlib import closing
import secrets
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from registry.db import connect_from_env


def main():
    import boto3
    import json
    connection=connect_from_env()
    password=secrets.token_urlsafe(40)
    try:
        with closing(connection.cursor()) as cur:
            cur.execute("SELECT 1 FROM pg_roles WHERE rolname='kilnwatch_api'")
            if cur.fetchone():
                raise ValueError('Reader login already exists; use a reviewed rotation process.')
            cur.execute("SELECT format('CREATE ROLE kilnwatch_api LOGIN PASSWORD %L', %s)",(password,))
            cur.execute(cur.fetchone()[0])
            cur.execute('GRANT kilnwatch_reader TO kilnwatch_api')
        # Write the secret before commit: failure rolls back DB role creation.
        boto3.client('secretsmanager').put_secret_value(SecretId=os.environ['REGISTRY_READER_SECRET'],
            SecretString=json.dumps({'username':'kilnwatch_api','password':password}))
        connection.commit()
        print('Dedicated SELECT-only registry login provisioned. Verify read access before smoke tests.')
    except Exception as exc:
        connection.rollback()
        # A commit failure after PutSecretValue can leave a secret for a rolled-back role.
        print('Reader provisioning failed: '+type(exc).__name__+'. Reconcile DB role and secret before retrying.',file=sys.stderr)
        raise SystemExit(1)
    finally:connection.close()


if __name__=='__main__':main()

"""Runner-only login provisioning. Credentials are generated in memory and stored only in Secrets Manager."""
from contextlib import closing
import json
import os
import secrets
import sys
from registry.db import connect_from_env


def main():
    import boto3
    connection = connect_from_env()  # administrative secret, supplied privately on runner
    password = secrets.token_urlsafe(40)
    try:
        with closing(connection.cursor()) as cur:
            cur.execute("SELECT 1 FROM pg_roles WHERE rolname='kilnwatch_verdicts'")
            if cur.fetchone():
                raise ValueError('Login already exists; use a reviewed rotation process.')
            cur.execute("SELECT format('CREATE ROLE kilnwatch_verdicts LOGIN PASSWORD %L', %s::text)", (password,))
            cur.execute(cur.fetchone()[0])
            cur.execute('GRANT kilnwatch_verdict_writer TO kilnwatch_verdicts')
        boto3.client('secretsmanager').put_secret_value(SecretId=os.environ['VERDICTS_SECRET'],
            SecretString=json.dumps({'username': 'kilnwatch_verdicts', 'password': password}))
        connection.commit()
        print('Verdict login provisioned; verify grants and connection before deployment checks.')
    except Exception:
        connection.rollback()
        print('Provisioning failed. Check whether the login exists before retrying; a commit failure may leave a secret for a rolled-back login.', file=sys.stderr)
        raise SystemExit(1)
    finally:
        connection.close()


if __name__ == '__main__': main()

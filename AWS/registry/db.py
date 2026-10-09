"""TLS connections; runtime uses a dedicated secret, never the RDS master login."""
import json
import os
import ssl


def connect_from_env():
    import pg8000.dbapi
    if os.environ.get('DB_SECRET'):
        import boto3
        from botocore.config import Config
        secret = json.loads(boto3.client('secretsmanager', config=Config(connect_timeout=3, read_timeout=3, retries={'max_attempts': 1})).get_secret_value(SecretId=os.environ['DB_SECRET'])['SecretString'])
        user, password = secret['username'], secret['password']
    else:
        user, password = os.environ['DB_USER'], os.environ.get('DB_PASSWORD')
    tls = ssl.create_default_context(cafile=os.environ['DB_CA_BUNDLE'])
    return pg8000.dbapi.connect(host=os.environ['DB_HOST'], port=int(os.getenv('DB_PORT', '5432')),
                               database=os.environ['DB_NAME'], user=user, password=password,
                               ssl_context=tls, timeout=5)

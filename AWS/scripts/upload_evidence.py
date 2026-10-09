"""Upload approved satellite PNGs only. NOT run during Integration 1 preparation.
The explicit --publish-reviewed-evidence flag is required; does not upload raw data/models.
"""
import argparse
import hashlib
import json
from pathlib import Path

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--manifest',type=Path,required=True)
parser.add_argument('--bucket',required=True)
parser.add_argument('--publish-reviewed-evidence',action='store_true')
a=parser.parse_args()
if not a.publish_reviewed_evidence:parser.error('publication requires a reviewed manifest and explicit flag')
import boto3
s3=boto3.client('s3');manifest=json.loads(a.manifest.read_text())
for entry in manifest['entries']:
    for side in ('before','after'):
        meta=entry.get(side)
        if not meta:continue
        path=(a.manifest.parent/meta['local_path']).resolve()
        if not path.is_relative_to(a.manifest.parent.resolve()):raise ValueError('path escapes manifest')
        if hashlib.sha256(path.read_bytes()).hexdigest()!=meta['sha256'] or meta['object_key']!='evidence/'+meta['sha256']+'.png':
            raise ValueError('checksum/key mismatch')
        # Conditional writes retain immutable keys. A retry accepts only a verified existing object.
        from botocore.exceptions import ClientError
        try:
            s3.put_object(Bucket=a.bucket,Key=meta['object_key'],Body=path.read_bytes(),ContentType='image/png',
                          CacheControl='public, max-age=31536000, immutable',IfNoneMatch='*')
        except ClientError as exc:
            if exc.response['Error']['Code']!='PreconditionFailed':raise
            old=s3.get_object(Bucket=a.bucket,Key=meta['object_key'])['Body'].read()
            if hashlib.sha256(old).hexdigest()!=meta['sha256']:raise ValueError('existing object differs')
print('Approved satellite evidence objects uploaded. Run HTTPS publication verification next.')

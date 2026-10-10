"""Read-only HTTPS image/checksum smoke test and publication receipt generation.
Use only after the AWS teammate uploads approved evidence objects. Does not upload.
"""
import argparse
from datetime import datetime,timezone
import hashlib
import json
from pathlib import Path
from urllib.parse import urlparse
import urllib.request

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--manifest',type=Path,required=True)
parser.add_argument('--base-url',required=True)
parser.add_argument('--out',type=Path,required=True)
a=parser.parse_args();u=urlparse(a.base_url)
if u.scheme!='https' or not u.hostname or u.path not in ('','/') or u.query or u.fragment or u.username:
    parser.error('provide an HTTPS distribution root')
raw=a.manifest.read_bytes();manifest=json.loads(raw);objects={}
for entry in manifest['entries']:
    for side in ('before','after'):
        meta=entry.get(side)
        if not meta:continue
        key=meta['object_key'];sha=meta['sha256']
        if key!='evidence/'+sha+'.png':parser.error('invalid content-addressed object key')
        with urllib.request.urlopen(a.base_url.rstrip('/')+'/'+key,timeout=20) as r:
            if r.headers.get_content_type()!='image/png':raise ValueError('unexpected evidence content type')
            data=r.read(2*1024*1024)
        if hashlib.sha256(data).hexdigest()!=sha:raise ValueError('published object checksum mismatch')
        objects[key]={'object_key':key,'sha256':sha}
a.out.write_text(json.dumps({'verified':True,'verified_at':datetime.now(timezone.utc).isoformat(),
    'manifest_sha256':hashlib.sha256(raw).hexdigest(),'base_url':a.base_url.rstrip('/'),
    'objects':list(objects.values())},indent=2)+'\n')
print('Publication verified:',len(objects),'objects; receipt:',a.out)

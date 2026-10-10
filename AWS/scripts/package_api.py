"""Build the Lambda artifact locally. Does not call AWS or Terraform."""
import hashlib
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request
import zipfile

root=Path(__file__).resolve().parents[1]
staging=root/'build'/'api'
if staging.exists(): shutil.rmtree(staging)
staging.mkdir(parents=True)
subprocess.run([sys.executable,'-m','pip','install','--platform','manylinux2014_x86_64',
                '--python-version','3.12','--implementation','cp','--only-binary=:all:',
                '--no-compile','--target',str(staging),'-r',str(root/'lambda'/'requirements.txt')],check=True)
shutil.copy(root/'lambda'/'api_handler.py',staging)
(staging/'registry').mkdir()
for name in ('__init__.py','contract.py','db.py','store.py'):
    shutil.copy(root/'registry'/name,staging/'registry'/name)
ca=urllib.request.urlopen('https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem',timeout=30).read()
(staging/'rds-ca.pem').write_bytes(ca)
archive=root/'build'/'api_handler.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
    for p in sorted(staging.rglob('*')):
        if p.is_file() and '__pycache__' not in p.parts:
            info=zipfile.ZipInfo(str(p.relative_to(staging)),date_time=(2026,1,1,0,0,0))
            info.compress_type=zipfile.ZIP_DEFLATED; info.external_attr=0o644<<16
            z.writestr(info,p.read_bytes())
print('artifact:',archive,'sha256:',hashlib.sha256(archive.read_bytes()).hexdigest())

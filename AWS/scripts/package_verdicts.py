"""Build a deterministic Python 3.12 verdict artifact; no AWS writes."""
import hashlib
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request
import zipfile

root = Path(__file__).resolve().parents[1]
staging = root / 'build' / 'verdicts'
if staging.exists(): shutil.rmtree(staging)
staging.mkdir(parents=True)
subprocess.run([sys.executable, '-m', 'pip', 'install', '--platform', 'manylinux2014_x86_64',
                '--python-version', '3.12', '--implementation', 'cp', '--only-binary=:all:',
                '--no-compile', '--target', str(staging), '-r', str(root / 'lambda' / 'requirements.txt')], check=True)
for package, names in [('verdicts', ('__init__.py', 'handler.py', 'store.py')),
                       ('registry', ('__init__.py', 'db.py'))]:
    (staging / package).mkdir()
    for name in names: shutil.copy(root / package / name, staging / package / name)
(staging / 'rds-ca.pem').write_bytes(urllib.request.urlopen(
    'https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem', timeout=30).read())
archive = root / 'build' / 'verdicts.zip'
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
    for path in sorted(staging.rglob('*')):
        if path.is_file() and '__pycache__' not in path.parts:
            info = zipfile.ZipInfo(str(path.relative_to(staging)), date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, path.read_bytes())
print('verdict artifact sha256:', hashlib.sha256(archive.read_bytes()).hexdigest())

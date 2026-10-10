"""Build the route planner Lambda ZIP locally: AWS/route/*.py plus the assistant's public API client (tools.py).
boto3 comes from the runtime. No AWS calls."""
import hashlib
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[1]
archive = root / 'build' / 'route.zip'
archive.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
    for p in sorted((root / 'route').glob('*.py')) + [root / 'assistant' / 'tools.py']:
        info = zipfile.ZipInfo(p.name, date_time=(2026, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED; info.external_attr = 0o644 << 16
        z.writestr(info, p.read_bytes())
print('artifact:', archive, 'sha256:', hashlib.sha256(archive.read_bytes()).hexdigest())

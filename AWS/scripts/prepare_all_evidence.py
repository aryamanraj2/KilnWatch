"""Cut evidence for every observation: runs Model/scripts/prepare_evidence.py once per sorted
index, then merges the one-entry manifests into one manifest beside all the PNGs. No uploads.
A kiln the preparer refuses is skipped and listed with its reason, never patched. If only the
before cut is refused, the kiln keeps its after image with before null (as when no before scene
is given). Run from the repository root with the Integration 1 environment.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PREPARER = ROOT/'Model'/'scripts'/'prepare_evidence.py'


def merge(parts, out):
    """parts: (index, folder) with each folder holding a one-entry manifest.json and its PNGs."""
    out.mkdir(parents=True, exist_ok=True)
    entries, seen, input_sha = [], set(), None
    for index, folder in parts:
        manifest = json.loads((folder/'manifest.json').read_text())
        if manifest['schema_version'] != 1 or len(manifest['entries']) != 1:
            raise ValueError(f'index {index}: expected one schema 1 entry')
        input_sha = input_sha or manifest['input_sha256']
        if manifest['input_sha256'] != input_sha:
            raise ValueError(f'index {index}: evidence from a different detection export')
        entry = manifest['entries'][0]
        if entry['observation_id'] in seen:
            raise ValueError(f'index {index}: duplicate observation {entry["observation_id"]}')
        seen.add(entry['observation_id'])
        for side in ('before', 'after'):
            meta = entry.get(side)
            if meta:
                name = Path(meta['local_path']).name
                shutil.copyfile(folder/name, out/name)
                meta['local_path'] = name
        entries.append(entry)
    return {'schema_version': 1, 'input_sha256': input_sha, 'publication_state': 'local_unpublished', 'entries': entries}


def reason(result):
    lines = [l for l in result.stderr.splitlines() if l.strip()]
    return lines[-1] if lines else f'exit {result.returncode}'


def cut(index, a, work):
    """Returns (folder, before_refusal) or raises RuntimeError with the preparer's reason."""
    base = [sys.executable, str(PREPARER), '--detections', str(a.detections), '--scenes', str(a.scenes),
            '--district', a.district, '--index', str(index)]
    folder = work/str(index)
    run = lambda extra, out: subprocess.run(base+extra+['--out', str(out)], capture_output=True, text=True)
    first = run(['--before-scene', str(a.before_scene)] if a.before_scene else [], folder)
    if first.returncode == 0:
        return folder, None
    if not a.before_scene:
        raise RuntimeError(reason(first))
    # The after patch is cut first, so a refusal here may be the before scene only.
    second = run([], work/f'{index}-after')
    if second.returncode != 0:
        raise RuntimeError(reason(second))
    return work/f'{index}-after', reason(first)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--detections', type=Path, required=True)
    ap.add_argument('--scenes', type=Path, required=True)
    ap.add_argument('--before-scene', type=Path)
    ap.add_argument('--district', required=True)
    ap.add_argument('--out', type=Path, required=True)
    ap.add_argument('--jobs', type=int, default=4)
    a = ap.parse_args()
    sys.path.insert(0, str(ROOT/'AWS'))
    from registry.contract import convert
    raw = a.detections.read_bytes()
    records = convert(json.loads(raw), a.district, hashlib.sha256(raw).hexdigest(), '1970-01-01T00:00:00Z')
    with tempfile.TemporaryDirectory() as tmp:
        def job(index):
            try: return index, *cut(index, a, Path(tmp)), None
            except RuntimeError as e: return index, None, None, str(e)
        with ThreadPoolExecutor(a.jobs) as pool:
            results = list(pool.map(job, range(len(records))))
        kiln = lambda i: records[i]['payload']['kiln_id']
        manifest = merge([(i, f) for i, f, _, err in results if not err], a.out)
    (a.out/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    summary = {'records': len(records), 'with_after': len(manifest['entries']),
               'with_before': sum(e['before'] is not None for e in manifest['entries']),
               'skipped': [{'index': i, 'kiln_id': kiln(i), 'reason': err} for i, _, _, err in results if err],
               'before_refused': [{'index': i, 'kiln_id': kiln(i), 'reason': b} for i, _, b, err in results if b and not err]}
    (a.out.parent/'prepare-summary.json').write_text(json.dumps(summary, indent=2)+'\n')
    print(json.dumps(summary, indent=2))


if __name__ == '__main__': main()

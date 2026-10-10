"""python -m rules.cli {fetch,assess}: local siting checks; never writes to the registry.

  fetch   OSM layers around the kilns  -> layers GeoJSON (ODbL, keep under .local/)
  assess  kilns + layers + rules       -> per-kiln assessment JSON
Kilns come from a public API list URL, a registry JSON body ({"kilns": [...]}) or a
detect_scene.py GeoJSON (registry IDs need --district; older files also --artifact-manifest/--acquired-at)."""
import argparse
from collections import defaultdict
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import sys
import urllib.parse
import urllib.request

from shapely.geometry import box

from . import engine, osm

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from registry.contract import canonical, convert  # noqa: E402


def degrees(metres, lat):
    return metres / 110574, metres / (111320 * math.cos(math.radians(lat)))


def fetch_public(url):
    """Every page of a public list URL (.../public/kilns?district=...): registry IDs, no sign-in."""
    kilns, cursor = [], None
    while True:
        page = url + (('&' if '?' in url else '?') + urllib.parse.urlencode({'cursor': cursor}) if cursor else '')
        req = urllib.request.Request(page, headers={'User-Agent': 'KilnWatch-rules/1'})
        with urllib.request.urlopen(req, timeout=30) as r:
            body = json.load(r)
        kilns += body['kilns']
        cursor = body.get('next_cursor')
        if not cursor:
            return kilns


def load_kilns(source, district=None, manifest=None, acquired_at=None):
    """-> (registry-shaped kilns, scanned lon/lat area or None, note, input sha256)."""
    if source.startswith('https://'):
        kilns = fetch_public(source)
        return kilns, None, 'registry IDs from the public API', hashlib.sha256(canonical(kilns).encode()).hexdigest()
    raw = Path(source).read_bytes()
    sha = hashlib.sha256(raw).hexdigest()
    data = json.loads(raw)
    if 'kilns' in data:
        return data['kilns'], None, 'registry records', sha
    meta = data.setdefault('kilnwatch', {})
    aoi = meta.get('aoi')
    scanned = box(aoi['lon_min'], aoi['lat_min'], aoi['lon_max'], aoi['lat_max']) if aoi else None
    if manifest:
        # detect_scene.py output from before provenance fields existed: supply them from the
        # verified checkpoint manifest and the scene's exact acquisition time.
        m = json.loads(Path(manifest).read_text())
        meta.setdefault('model_sha256', m['sha256']); meta.setdefault('model_version', m['model_version'])
        meta.setdefault('confidence_semantics', 'predicted_class_score_shared')
        for item in meta.get('scenes', []) + [f['properties'] for f in data['features']]:
            if acquired_at: item.setdefault('acquired_at', acquired_at)
    if district:
        try:
            records = convert(data, district, sha, datetime.now(timezone.utc).isoformat())
            return [r['payload'] for r in records], scanned, 'registry IDs from contract.convert', sha
        except (KeyError, ValueError) as e:
            note = f'local IDs (not importable: {e})'
    else:
        note = 'local IDs (no --district)'
    kilns = []
    for n, f in enumerate(data['features']):
        ring = f['geometry']['coordinates'][0][:-1]
        lon, lat = f['properties']['centroid']
        kilns.append({'kiln_id': f'local-{n:04d}', 'type': f['properties'].get('type'),
                      'footprint': {'polygon': [{'longitude': x, 'latitude': y} for x, y in ring],
                                    'centroid': {'longitude': lon, 'latitude': lat}}})
    return kilns, scanned, note, sha


def area_around(kilns, metres):
    polys = [engine.kiln_polygon(k) for k in kilns]
    w = min(p.bounds[0] for p in polys); s = min(p.bounds[1] for p in polys)
    e = max(p.bounds[2] for p in polys); n = max(p.bounds[3] for p in polys)
    dlat, dlon = degrees(metres, max(abs(s), abs(n)))
    return [round(w - dlon, 5), round(s - dlat, 5), round(e + dlon, 5), round(n + dlat, 5)]


def load_layers(path):
    data = json.loads(Path(path).read_text())
    grouped = defaultdict(list)
    for f in data['features']:
        p = f['properties']
        grouped[p['layer']].append({'geometry': f['geometry'], **{k: p[k] for k in ('ref', 'kind', 'name') if k in p}})
    coverage = engine.coverage_of(data['kilnwatch'])
    # A layer with no features in the area is still a searched layer.
    names = {r['layer'] for r in engine.load_rules()['rules'] if r.get('layer') and r['layer'] in osm_layers()}
    return {n: engine.Layer(grouped.get(n, []), coverage) for n in names}, data['kilnwatch']


def osm_layers():
    return {'habitation', 'schools', 'orchards', 'railways', 'national_highways'}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('command', choices=['fetch', 'assess'])
    ap.add_argument('--kilns', required=True, help='public API list URL, registry JSON or detections GeoJSON')
    ap.add_argument('--district', help='derive registry kiln IDs via contract.convert')
    ap.add_argument('--artifact-manifest', type=Path, help='verified checkpoint manifest, for older detections files')
    ap.add_argument('--acquired-at', help='exact scene acquisition time, for older detections files')
    ap.add_argument('--scanned-bbox', type=float, nargs=4, metavar=('LON_MIN', 'LAT_MIN', 'LON_MAX', 'LAT_MAX'),
                    help='area searched for kilns; needed for kiln spacing when kilns come from the registry')
    ap.add_argument('--state', default='UP')
    ap.add_argument('--layers', type=Path, help='OSM layers GeoJSON (fetch writes it, assess reads it)')
    ap.add_argument('--out', type=Path, help='assessment JSON (assess)')
    a = ap.parse_args()

    kilns, scanned, note, kilns_sha = load_kilns(a.kilns, a.district, a.artifact_manifest, a.acquired_at)
    if a.scanned_bbox:
        scanned = box(*a.scanned_bbox)
    rules = engine.load_rules()
    if a.command == 'fetch':
        reach = max(r['threshold_m'] for r in rules['rules'] if r.get('layer') in osm_layers()) + engine.SEARCH_MARGIN_M
        bbox = area_around(kilns, reach + 100)
        print(f'fetching OSM layers for {len(kilns)} kilns, bbox {bbox}', file=sys.stderr)
        layers = osm.fetch(bbox)
        a.layers.parent.mkdir(parents=True, exist_ok=True)
        a.layers.write_text(json.dumps(layers))
        counts = defaultdict(int)
        for f in layers['features']:
            counts[f['properties']['layer']] += 1
        print(json.dumps({'layers': str(a.layers), 'osm_base': layers['kilnwatch']['osm_base'], 'features': counts}))
        return

    layers, layer_meta = load_layers(a.layers)
    results = engine.assess(kilns, layers, a.state, rules, scanned)
    body = {'rules_version': rules['version'], 'state': a.state, 'kiln_ids': note,
            'inputs': {'kilns_sha256': kilns_sha,
                       'layers_sha256': hashlib.sha256(a.layers.read_bytes()).hexdigest(),
                       'osm_base': layer_meta.get('osm_base'), 'scanned_area': list(scanned.bounds) if scanned else None},
            'assessed_at': datetime.now(timezone.utc).isoformat(timespec='seconds'), 'assessments': results}
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text(json.dumps(body, indent=1) + '\n')
    flagged = defaultdict(int)
    for r in results:
        for v in r['violations']:
            flagged[v['rule_id']] += 1
    print(json.dumps({'kilns': len(results), 'with_any_flag': sum(bool(r['violations']) for r in results),
                      'flags_by_rule': flagged, 'out': str(a.out)}))


if __name__ == '__main__':
    main()

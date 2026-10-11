"""Change triage, step 1: the deterministic diff between a baseline detector run and today's registry.

Pure Python, no network. The four groups, the matching and every number come from here; the agent only
writes a reason sentence from the facts this module produces. Every item is a candidate for review."""
import hashlib
import math
from datetime import datetime

MIN_IOU = 0.3
MAX_CENTROID_M = 30.0  # fallback for slivers whose footprints barely overlap
LOW_SCORE = 0.5  # current detector score below this is a low-confidence candidate
NEAR_SCORE = 0.05  # reported only: how many current scores sit within this of LOW_SCORE
FIXED_CHIMNEY = ('FCBK', 'CFCBK')
GROUPS = ('new_candidate', 'no_longer_detected', 'possible_zigzag_conversion', 'low_confidence')
METRES_PER_DEGREE = 111_320.0


def _xy(lon, lat):
    """Sinusoidal (equal-area) metres; exact enough for kiln-sized shapes."""
    return lon * METRES_PER_DEGREE * math.cos(math.radians(lat)), lat * METRES_PER_DEGREE


def _area(poly):
    return sum(x1 * y2 - x2 * y1 for (x1, y1), (x2, y2) in zip(poly, poly[1:] + poly[:1])) / 2


def _cut(p, q, a, b):
    """Where segment p-q crosses the line through a and b."""
    dx, dy, ex, ey = q[0] - p[0], q[1] - p[1], b[0] - a[0], b[1] - a[1]
    t = (ex * (a[1] - p[1]) - ey * (a[0] - p[0])) / (ex * dy - ey * dx)
    return p[0] + t * dx, p[1] + t * dy


def _clip(subject, clip):
    """Sutherland-Hodgman: subject intersected with a convex, counter-clockwise clip polygon."""
    out = subject
    for a, b in zip(clip, clip[1:] + clip[:1]):
        if not out: break
        inside = lambda p: (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]) >= 0
        result, prev = [], out[-1]
        for p in out:
            if inside(p):
                if not inside(prev): result.append(_cut(prev, p, a, b))
                result.append(p)
            elif inside(prev):
                result.append(_cut(prev, p, a, b))
            prev = p
        out = result
    return out


def iou(a, b):
    """Footprint IoU of two kilns (oriented bounding boxes, so both are convex)."""
    inter = abs(_area(_clip(a['xy'], b['xy']))) if len(a['xy']) > 2 and len(b['xy']) > 2 else 0.0
    union = abs(_area(a['xy'])) + abs(_area(b['xy'])) - inter
    return inter / union if union > 0 else 0.0


def distance_m(a, b):
    return math.dist(a['centre'], b['centre'])


def _kiln(ring, **fields):
    """ring: [(lon, lat), ...], open or closed."""
    ring = [(float(lon), float(lat)) for lon, lat in ring]
    if len(ring) > 1 and ring[0] == ring[-1]: ring = ring[:-1]
    if len(ring) < 3: raise ValueError('footprint needs at least three corners')
    xy = [_xy(lon, lat) for lon, lat in ring]
    if _area(xy) < 0: xy.reverse()
    lon = sum(p[0] for p in ring) / len(ring)
    lat = sum(p[1] for p in ring) / len(ring)
    return {'ring': ring, 'xy': xy, 'centre': _xy(lon, lat), 'centroid': [round(lat, 5), round(lon, 5)], **fields}


def from_feature(feature):
    """One detector GeoJSON feature (detections/<run>/kilns.geojson)."""
    p = feature['properties']
    return _kiln(feature['geometry']['coordinates'][0], kiln_id=None, type=p.get('type'),
                 score=p.get('detection_confidence'), evidence=None)


def from_record(record):
    """One public registry record (include=inspected)."""
    ring = [(c['longitude'], c['latitude']) for c in record['footprint']['polygon']]
    evidence = record.get('evidence') or {}
    urls = {'before': evidence.get('before'), 'after': evidence.get('after')}
    return _kiln(ring, kiln_id=record['kiln_id'], type=record.get('type'), score=record.get('detection_confidence'),
                 evidence=urls if any(urls.values()) else None)


def scene_of(collection):
    """The single scene a detector run used: {'id', 'date'}."""
    scenes = collection['kilnwatch']['scenes']
    if len(scenes) != 1: raise ValueError('expected one scene per run')
    return {'id': scenes[0]['id'], 'date': scenes[0]['date']}


def match(left, right):
    """One-to-one: every pair with IoU >= MIN_IOU or centroids within MAX_CENTROID_M, best IoU first,
    then the nearest centroid. Returns {left index: (right index, iou)}."""
    pairs = []
    for i, a in enumerate(left):
        for j, b in enumerate(right):
            overlap, d = iou(a, b), distance_m(a, b)
            if overlap >= MIN_IOU or d <= MAX_CENTROID_M: pairs.append((-overlap, d, i, j))
    taken, out = set(), {}
    for negative, _, i, j in sorted(pairs):
        if i in out or j in taken: continue
        out[i] = (j, -negative)
        taken.add(j)
    return out


def month(date):
    return datetime.strptime(date, '%Y-%m-%d').strftime('%b %Y')


def group_words(group, baseline_scene, current_scene, before=None, score=None):
    """The fixed wording of each group. Never a construction or demolition date, never a status."""
    then, now = month(baseline_scene['date']), month(current_scene['date'])
    return {'new_candidate': f'in the registry; not detected in the {then} scene',
            'no_longer_detected': f'detected in the {then} scene; no longer detected in the {now} scene',
            'possible_zigzag_conversion': f'detected as {before} in the {then} scene and as Zigzag in the {now} scene',
            'low_confidence': f'current detector score {score} is below {LOW_SCORE}'}[group]


def item_id(baseline_run, group, kiln):
    corners = sorted((round(lat, 6), round(lon, 6)) for lon, lat in kiln['ring'])
    key = f'{baseline_run}|registry|{group}|{corners}'
    return hashlib.sha256(key.encode()).hexdigest()[:32]


def side(kiln, score=None):
    return {'type': kiln['type'], 'score': kiln['score'] if score is None else score} if kiln else None


def triage(baseline, registry, current, baseline_scene, current_scene, baseline_run):
    """baseline/current: detector kilns (from_feature); registry: from_record. Returns (items sorted by item_id,
    summary). An unchanged match produces no item."""
    to_current = match(registry, current)
    scores = [current[to_current[i][0]]['score'] if i in to_current else k['score'] for i, k in enumerate(registry)]
    to_baseline = match(registry, baseline)
    matched_baseline = {j for j, _ in to_baseline.values()}
    items = []

    def add(group, kiln, before, now, score, overlap, basis):
        facts = {'item_id': item_id(baseline_run, group, kiln), 'group': group,
                 'group_words': group_words(group, baseline_scene, current_scene, before and before['type'], score),
                 'kiln_id': kiln['kiln_id'], 'baseline_run': baseline_run, 'compared_with': 'registry',
                 'baseline_scene': baseline_scene, 'current_scene': current_scene,
                 'baseline': side(before), 'current': side(now, score),
                 'iou': round(overlap, 2) if overlap is not None else 'none', 'match': basis,
                 'centroid': kiln['centroid']}
        if kiln['evidence']:
            facts['evidence'] = dict(kiln['evidence'])
        else:
            facts['evidence'] = {'images': 'no published image',
                                 'scene_ids': [baseline_scene['id'], current_scene['id']],
                                 'footprint': [[round(lat, 6), round(lon, 6)] for lon, lat in kiln['ring']]}
        items.append(facts)

    for i, kiln in enumerate(registry):
        score = scores[i]
        low = isinstance(score, (int, float)) and score < LOW_SCORE
        if i in to_baseline:
            j, overlap = to_baseline[i]
            before = baseline[j]
            basis = 'footprint overlap' if overlap >= MIN_IOU else f'centroids within {MAX_CENTROID_M:g} m'
            # Precedence: 3 (zigzag), then 1 (new), then 4 (low confidence). 1 and 3 never meet: 1 has no match.
            if before['type'] in FIXED_CHIMNEY and kiln['type'] == 'Zigzag':
                add('possible_zigzag_conversion', kiln, before, kiln, score, overlap, basis)
            elif low:
                add('low_confidence', kiln, before, kiln, score, overlap, basis)
        else:
            add('new_candidate', kiln, None, kiln, score, None, 'none')
    for j, before in enumerate(baseline):
        if j not in matched_baseline:
            add('no_longer_detected', before, before, None, None, None, 'none')

    items.sort(key=lambda f: f['item_id'])
    counts = {g: sum(f['group'] == g for f in items) for g in GROUPS}
    summary = {'counts': counts, 'items': len(items), 'baseline': len(baseline), 'registry': len(registry),
               'current_run_features': len(current), 'matched': len(to_baseline), 'registry_matched_to_current_run': len(to_current),
               'near_low_score': sum(isinstance(s, (int, float)) and abs(s - LOW_SCORE) <= NEAR_SCORE for s in scores)}
    return items, summary

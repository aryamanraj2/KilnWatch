"""Strict model-only conversion. No cloud/database/image dependencies."""
from datetime import datetime, timezone
import hashlib
import json
import math
import re
import uuid

HASH = re.compile(r'^[0-9a-f]{64}$')
ID = re.compile(r'^KW-(?:[0-9]{4,}|[0-9a-f]{32})$')
DISTRICT = re.compile(r'^[A-Za-z][A-Za-z -]{0,63}$')
STATUSES = ('flagged', 'confirmed', 'compliant', 'not_a_kiln', 'closed')


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False)


def digest(value):
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def timestamp(value):
    if not isinstance(value, str) or not re.fullmatch(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|[+-]\d\d:\d\d)', value):
        raise ValueError('acquisition requires an exact RFC 3339 timestamp with offset')
    d = datetime.fromisoformat(value.replace('Z', '+00:00'))
    return d.astimezone(timezone.utc).isoformat().replace('+00:00', 'Z')


def number(value, lo, hi):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not lo <= value <= hi:
        raise ValueError('number out of range or nonfinite')
    return value


def coordinate(pair):
    if not isinstance(pair, list) or len(pair) != 2:
        raise ValueError('coordinate requires [longitude, latitude]')
    return {'latitude': number(pair[1], -90, 90), 'longitude': number(pair[0], -180, 180)}


def ring_of(feature):
    geometry = feature['geometry']
    rings = geometry['coordinates']
    if feature['type'] != 'Feature' or geometry['type'] != 'Polygon' or len(rings) != 1:
        raise ValueError('expected single Polygon without holes')
    ring = rings[0]
    if len(ring) != 5 or ring[0] != ring[-1] or len({tuple(p) for p in ring[:-1]}) != 4:
        raise ValueError('expected closed four-corner OBB')
    for p in ring:
        coordinate(p)
    # Strictly convex ordered quadrilateral: rejects crossings, collinearity and concavity.
    cross = []
    for i in range(4):
        a, b, c = ring[i], ring[(i+1) % 4], ring[(i+2) % 4]
        cross.append((b[0]-a[0])*(c[1]-b[1])-(b[1]-a[1])*(c[0]-b[0]))
    if not (all(v > 0 for v in cross) or all(v < 0 for v in cross)):
        raise ValueError('invalid/degenerate OBB polygon')
    return ring


def observation_key(feature, model_sha256):
    ring = ring_of(feature)[:-1]
    variants = [r[i:]+r[:i] for r in (ring, list(reversed(ring))) for i in range(4)]
    return digest([feature['properties']['scene_id'], model_sha256, min(variants)])


def serialize(payload, status='flagged', review_state='pending', assessment=None):
    """Single serializer used by the importer preview, persisted reads and contract proof."""
    record = json.loads(canonical(payload))
    record['status'] = status
    record['review_state'] = review_state
    if assessment:
        for key in ('exposure', 'violations', 'rules_assessment', 'type_verification'):
            if key in assessment:
                record[key] = assessment[key]
    return record


PUBLIC_KEYS = ('kiln_id', 'footprint', 'type', 'type_confidence', 'detection_confidence', 'type_verification',
               'first_seen', 'last_seen', 'status', 'violations', 'rules_assessment', 'exposure', 'district', 'distance_m')
PUBLIC_EVIDENCE = ('before', 'after', 'before_metadata', 'after_metadata')


def public_view(record):
    """Resident projection of a serialized record. Allowlist only: any new internal field stays private."""
    view = {k: record[k] for k in PUBLIC_KEYS if k in record}
    view['evidence'] = {k: record['evidence'][k] for k in PUBLIC_EVIDENCE if k in record['evidence']}
    return view


def convert(collection, district, input_sha256, imported_at):
    if not DISTRICT.fullmatch(district) or not HASH.fullmatch(input_sha256):
        raise ValueError('invalid district/input hash')
    imported_at = timestamp(imported_at)
    if collection['type'] != 'FeatureCollection' or not isinstance(collection['features'], list):
        raise ValueError('expected FeatureCollection')
    metadata = collection['kilnwatch']
    model_hash = metadata['model_sha256']
    if not HASH.fullmatch(model_hash) or not metadata['model_version']:
        raise ValueError('verified model hash/version required')
    if metadata['confidence_semantics'] != 'predicted_class_score_shared':
        raise ValueError('unsupported confidence semantics')
    scenes = {}
    for scene in metadata['scenes']:
        acquired = timestamp(scene['acquired_at'])
        if scene['id'] in scenes and scenes[scene['id']] != acquired:
            raise ValueError('conflicting scene acquisition times')
        scenes[scene['id']] = acquired
    records = {}
    for feature in collection['features']:
        p = feature['properties']
        ring = ring_of(feature)
        center = coordinate(p['centroid'])
        # A convex polygon contains a point iff each edge cross product has the same sign.
        signs = [(b[0]-a[0])*(p['centroid'][1]-a[1])-(b[1]-a[1])*(p['centroid'][0]-a[0]) for a,b in zip(ring, ring[1:])]
        if not (all(v >= 0 for v in signs) or all(v <= 0 for v in signs)):
            raise ValueError('centroid outside footprint')
        acquired = timestamp(p.get('acquired_at') or scenes.get(p['scene_id']))
        if scenes.get(p['scene_id']) != acquired or p['scene_date'] != acquired[:10]:
            raise ValueError('scene timestamp/date/provenance mismatch')
        score = number(p['type_confidence'], 0, 1)
        if number(p['detection_confidence'], 0, 1) != score:
            raise ValueError('shared class score fields disagree')
        if not isinstance(p['type'], str) or not p['type'] or len(p['type']) > 64:
            raise ValueError('invalid kiln type')
        key = observation_key(feature, model_hash)
        record = {
            'kiln_id': 'KW-'+uuid.uuid5(uuid.NAMESPACE_URL, 'kilnwatch:'+key).hex,
            'footprint': {'polygon': [coordinate(c) for c in ring[:-1]], 'centroid': center},
            'type': p['type'], 'type_confidence': score, 'detection_confidence': score,
            'first_seen': acquired, 'last_seen': acquired,
            'violations': [], 'rules_assessment': 'not_evaluated', 'exposure': None,
            'type_verification': 'unverified', 'district': district,
            'evidence': {'before': None, 'after': None},
            'provenance': {'scene_id': p['scene_id'], 'acquired_at': acquired,
                           'model_sha256': model_hash, 'model_version': metadata['model_version'],
                           'input_sha256': input_sha256, 'imported_at': imported_at,
                           'confidence_semantics': metadata['confidence_semantics']},
        }
        if key in records and records[key]['payload'] != record:
            raise ValueError('conflicting duplicate observation')
        records[key] = {'observation_id': key, 'geometry': feature['geometry'], 'payload': record}
    return [records[k] for k in sorted(records)]


RULE_KEYS = ('violations', 'rules_assessment', 'rules_results', 'rules_version', 'rules_inputs')
RULE_STATUSES = ('within_threshold', 'beyond_threshold', 'inconclusive', 'not_evaluated', 'not_applicable')
VIOLATION_KEYS = {'rule_id', 'measured_distance_m', 'threshold_m', 'source', 'evidence_url', 'measured_to'}
EXPOSURE_KEYS = {'people', 'children_under_five', 'adults_over_sixty'}


def assessment_patches(body):
    """Rules-engine output (AWS/rules) -> [(kiln_id, assessment keys)]. Validates the whole
    batch before anything is written; only the rule keys, and exposure when supplied, are replaced."""
    if not isinstance(body.get('rules_version'), str) or not isinstance(body.get('assessments'), list):
        raise ValueError('expected rules engine output')
    inputs = {k: body['inputs'].get(k) for k in ('kilns_sha256', 'layers_sha256', 'osm_base')}
    inputs['assessed_at'] = timestamp(body['assessed_at'])
    seen, out = set(), []
    for a in body['assessments']:
        if not isinstance(a.get('kiln_id'), str) or not ID.fullmatch(a['kiln_id']):
            raise ValueError(f'not a registry kiln_id: {a.get("kiln_id")!r}')
        if a['kiln_id'] in seen:
            raise ValueError('duplicate kiln_id')
        seen.add(a['kiln_id'])
        if a['rules_assessment'] not in ('evaluated', 'partially_evaluated') or a['rules_version'] != body['rules_version']:
            raise ValueError('invalid rules assessment/version')
        for r in a['rules_results']:
            if r['status'] not in RULE_STATUSES:
                raise ValueError('unknown rule status')
        for v in a['violations']:
            if set(v) != VIOLATION_KEYS or not isinstance(v['rule_id'], str) or not isinstance(v['source'], str):
                raise ValueError('violation does not match the kiln record')
            number(v['measured_distance_m'], 0, 1e6)
            number(v['threshold_m'], 0, 1e6)
            if v['evidence_url'] is not None and not str(v['evidence_url']).startswith('https://'):
                raise ValueError('evidence_url must be https or null')
            if v['measured_to'] is not None:
                coordinate([v['measured_to']['longitude'], v['measured_to']['latitude']])
        flagged = sorted(r['rule_id'] for r in a['rules_results'] if r['status'] == 'within_threshold')
        if flagged != sorted(v['rule_id'] for v in a['violations']):
            raise ValueError('violations disagree with rule results')
        patch = {'violations': a['violations'], 'rules_assessment': a['rules_assessment'],
                 'rules_results': a['rules_results'], 'rules_version': a['rules_version'], 'rules_inputs': inputs}
        if 'exposure' in a:
            e = a['exposure']
            if not isinstance(e, dict) or set(e) != EXPOSURE_KEYS or any(isinstance(v, bool) or not isinstance(v, int) or v < 0 for v in e.values()):
                raise ValueError('exposure needs three non-negative integer counts')
            if not body['inputs'].get('population_source') or not body['inputs'].get('exposure_radius_m'):
                raise ValueError('exposure without population provenance')
            patch['exposure'] = e
            patch['exposure_inputs'] = {k: body['inputs'][k] for k in ('population_source', 'population_sha256', 'exposure_radius_m')}
        out.append((a['kiln_id'], patch))
    return out

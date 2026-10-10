"""Thin, validated wrappers over the public read API. The only data source the assistant has."""
import json
import math
import re
import urllib.error
import urllib.parse
import urllib.request

# Same shapes as AWS/registry/contract.py (ID, DISTRICT); copied so the ZIP needs nothing beyond this folder.
KILN_ID = re.compile(r'^KW-(?:[0-9]{4,}|[0-9a-f]{32})$')
DISTRICT = re.compile(r'^[A-Za-z][A-Za-z -]{0,63}$')
NOTE = ('predicted_type is an unverified model prediction. model_score is a detector score, not accuracy, '
        'not a probability of wrongdoing and not a rule check. Every kiln is flagged by satellite, pending inspection.')
IMAGES_NOTE = ('Satellite images are published only for the kiln IDs listed in images_published_only_for; '
               'for every other kiln they are not yet published.')


class UpstreamUnavailable(Exception):
    """The public API returned 429/5xx, timed out or was unreachable."""


SPECS = [
    {'toolSpec': {'name': 'list_flagged_kilns',
                  'description': 'List satellite-flagged kilns in a district (for example Hapur), with the total count. '
                                 'For "most people" or "most exposed" questions, set sort_by to people_within_800m: '
                                 'the server ranks the kilns, so use the rank column as given.',
                  'inputSchema': {'json': {'type': 'object', 'properties': {
                      'district': {'type': 'string', 'description': 'District name, for example Hapur.'},
                      'limit': {'type': 'integer', 'minimum': 1, 'maximum': 50, 'description': 'Page size, default 50.'},
                      'sort_by': {'type': 'string', 'enum': ['default', 'people_within_800m'],
                                  'description': 'people_within_800m ranks kilns by people within 800 m, highest first; '
                                                 'kilns not assessed come last. Default: by kiln ID.'}},
                      'required': ['district']}}}},
    {'toolSpec': {'name': 'kilns_near',
                  'description': 'Flagged kilns within radius_m of a point, nearest first, with distance_m from the point.',
                  'inputSchema': {'json': {'type': 'object', 'properties': {
                      'lat': {'type': 'number'}, 'lon': {'type': 'number'},
                      'radius_m': {'type': 'integer', 'minimum': 100, 'maximum': 5000, 'description': 'Default 2000.'}},
                      'required': ['lat', 'lon']}}}},
    {'toolSpec': {'name': 'kiln_detail',
                  'description': 'The public record of one flagged kiln by its full ID.',
                  'inputSchema': {'json': {'type': 'object', 'properties': {
                      'kiln_id': {'type': 'string', 'description': 'Full ID, for example KW- followed by 32 hex characters.'}},
                      'required': ['kiln_id']}}}},
    {'toolSpec': {'name': 'get_evidence',
                  'description': 'The evidence pack for one flagged kiln by its full ID: satellite image dates, scenes and '
                                 'attribution, every siting rule check with its measured distance and source, and the '
                                 'population exposure estimate.',
                  'inputSchema': {'json': {'type': 'object', 'properties': {
                      'kiln_id': {'type': 'string', 'description': 'Full ID, for example KW- followed by 32 hex characters.'}},
                      'required': ['kiln_id']}}}},
]
# Rule facts as explicit words (a bare status or boolean column gets misread). Never the word the record key uses.
STATUS_WORDS = {
    'within_threshold': 'siting flag: a mapped feature is inside the threshold; needs inspection',
    'beyond_threshold': 'nearest mapped feature is beyond the threshold',
    'inconclusive': 'inconclusive: no mapped feature inside the threshold, but the map is incomplete here, '
                    'so this is not a clear result',
    'not_evaluated': 'not evaluated (no usable data)',
    'not_applicable': 'not applicable in this state'}
VERIFICATION_WORDS = {
    'secondary_sources': 'sourced threshold: quoted by court records, legal digests or news reports (not an unverified threshold)',
    'unverified_compilation': 'unverified threshold (from an academic compilation)'}
FLAG_BASIS = {'secondary_sources': 'sourced threshold (secondary sources)', 'unverified_compilation': 'unverified threshold'}
SORTED_NOTE = 'Sorted by people_within_800m, highest first; rank 1 has the most people.'
PARTIAL_NOTE = 'Some siting rules lacked data, so having no siting flags is not a clean result.'
EXPOSURE_NOTE = ('Modelled estimate of residents within 800 m of the kiln edge, from HRSL v1.5.2 (Meta and CIESIN, '
                 'CC BY 4.0). Age groups are modelled shares of the same estimate.')


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def valid_point(lat, lon):
    return number(lat) and number(lon) and -90 <= lat <= 90 and -180 <= lon <= 180


def integer(value, low, high, default):
    if value is None: return default
    if number(value) and float(value).is_integer() and low <= value <= high: return int(value)
    return None


def trim(record, detail=False):
    """Only what the model needs. No URLs, polygons, metadata or internal fields."""
    centroid = record.get('footprint', {}).get('centroid', {})
    evidence = record.get('evidence') or {}
    exposure = record.get('exposure')
    checks = {c.get('rule_id'): c for c in record.get('rule_checks') or []}
    flags = []
    for v in record.get('violations') or []:
        basis = FLAG_BASIS.get(checks.get(v.get('rule_id'), {}).get('verification'), 'threshold basis unknown')
        flags.append(f"{v.get('rule_id')} ({checks.get(v.get('rule_id'), {}).get('check', 'siting rule')}): "
                     f"{v.get('measured_distance_m')} m from the nearest mapped feature, threshold {v.get('threshold_m')} m, {basis}")
    view = {'kiln_id': record['kiln_id'], 'status': record.get('status'),
            'predicted_type': record.get('type'), 'type_verification': record.get('type_verification'),
            'model_score': record.get('detection_confidence'), 'district': record.get('district'),
            'centroid': [round(centroid['latitude'], 5), round(centroid['longitude'], 5)] if centroid else None,
            'first_seen': (record.get('first_seen') or '')[:10] or None,
            'last_seen': (record.get('last_seen') or '')[:10] or None,
            'rules_assessment': record.get('rules_assessment') or 'not_evaluated',
            'siting_flags': flags,
            'people_within_800m': exposure['people'] if exposure else 'not assessed',
            'satellite_images': 'published' if evidence.get('before') or evidence.get('after') else 'not yet published'}
    if view['rules_assessment'] == 'partially_evaluated': view['rules_note'] = PARTIAL_NOTE
    if detail:
        for key in ('children_under_five', 'adults_over_sixty'):
            view[key] = exposure[key] if exposure else 'not assessed'
    if 'distance_m' in record: view['distance_m'] = record['distance_m']
    return view


def rule_words(record, with_source=False):
    """Every rule check in explicit words. No feature names, coordinates or URLs."""
    out = []
    for c in record.get('rule_checks') or []:
        measured = c.get('measured_distance_m')
        if measured is None:
            measured = 'no mapped feature found' if c.get('status') in ('inconclusive', 'beyond_threshold') else 'not measured'
        words = {'rule_id': c.get('rule_id'), 'check': c.get('check'),
                 'status_words': STATUS_WORDS.get(c.get('status'), 'unknown status'),
                 'measured_distance_m': measured,
                 'threshold_m': c.get('threshold_m') if c.get('threshold_m') is not None else 'no distance threshold',
                 'threshold_basis': VERIFICATION_WORDS.get(c.get('verification'), 'threshold basis unknown')}
        if with_source: words['source'] = c.get('source')
        out.append(words)
    return out


def image_side(meta):
    if not meta: return 'no image metadata'
    return {'image_date': (meta.get('acquired_at') or '')[:10] or None, 'acquired_at': meta.get('acquired_at'),
            'scene_id': meta.get('scene_id'), 'attribution': meta.get('attribution'), 'ground_resolution_m': meta.get('gsd_m')}


class PublicAPI:
    def __init__(self, base_url, opener=None, timeout=5):
        if not base_url.startswith('https://'): raise ValueError('public API base URL must be https')
        self.base, self.opener, self.timeout = base_url.rstrip('/'), opener or urllib.request.build_opener(), timeout

    def get(self, path, query=None):
        """Returns the decoded body, or None for 404. Everything else that is not 200 is upstream failure."""
        url = self.base + path + ('?' + urllib.parse.urlencode(query) if query else '')
        request = urllib.request.Request(url, headers={'accept': 'application/json', 'user-agent': 'kilnwatch-assistant'})
        try:
            with self.opener.open(request, timeout=self.timeout) as reply:
                if reply.status != 200: raise UpstreamUnavailable(reply.status)
                body = json.loads(reply.read(1_000_000))
                if not isinstance(body, dict): raise ValueError('unexpected body')
                return body
        except urllib.error.HTTPError as exc:
            if exc.code == 404: return None
            raise UpstreamUnavailable(exc.code) from None
        except (urllib.error.URLError, TimeoutError, OSError, ValueError) as exc:
            raise UpstreamUnavailable(type(exc).__name__) from None


def run(api, name, args):
    """Run one tool call. Returns (result for the model, server-written step, kiln IDs the model saw).
    Invalid input is an error result, never an exception. Upstream failures raise UpstreamUnavailable."""
    args = args if isinstance(args, dict) else {}
    if name == 'list_flagged_kilns':
        label = 'Searching flagged kilns'
        district, limit = args.get('district'), integer(args.get('limit'), 1, 50, 50)
        ranked = args.get('sort_by', 'default')
        if not isinstance(district, str) or not DISTRICT.fullmatch(district) or limit is None \
                or ranked not in ('default', 'people_within_800m'):
            return invalid(name, label)
        ranked = ranked == 'people_within_800m'
        kilns, cursor, pages = [], None, 0
        while pages < 2:
            # Ranking needs every kiln before the limit applies, so it fetches full pages.
            query = {'district': district, 'limit': 50 if ranked else limit, **({'cursor': cursor} if cursor else {})}
            body = api.get('/public/kilns', query) or {}
            kilns += records(body); cursor = body.get('next_cursor'); pages += 1
            if not cursor: break
        if ranked:
            # Not assessed sorts last, never as zero. Stable sort keeps ties in kiln ID order.
            kilns.sort(key=lambda k: (not k.get('exposure'), -(k.get('exposure') or {}).get('people', 0)))
            shown = [{**trim(k), 'rank': n} for n, k in enumerate(kilns[:limit], 1)]
        else:
            shown = [trim(k) for k in kilns[:50]]
        more, images = bool(cursor), image_fields(shown)
        ids = [k['kiln_id'] for k in shown]
        result = {'district': district, 'count': len(kilns), 'more_pages': more, 'kilns_shown': len(shown),
                  **({'order': SORTED_NOTE} if ranked else {}), 'kilns': table(shown), **images, 'note': NOTE}
        summary = f'{len(kilns)}{"+" if more else ""} found'
        return result, step(name, label, summary, True), ids
    if name == 'kilns_near':
        label = 'Searching near a point'
        lat, lon, radius = args.get('lat'), args.get('lon'), integer(args.get('radius_m'), 100, 5000, 2000)
        if not valid_point(lat, lon) or radius is None:
            return invalid(name, label)
        body = api.get('/public/kilns', {'lat': f'{lat:.6f}', 'lon': f'{lon:.6f}', 'radius_m': radius}) or {}
        shown = [trim(k) for k in records(body)[:50]]
        images = image_fields(shown)
        result = {'radius_m': radius, 'count': len(shown), 'kilns': table(shown), **images, 'note': NOTE}
        return result, step(name, label, f'{len(shown)} within {radius} m', True), [k['kiln_id'] for k in shown]
    if name in ('kiln_detail', 'get_evidence'):
        kiln_id = args.get('kiln_id')
        evidence = name == 'get_evidence'
        if not isinstance(kiln_id, str) or not KILN_ID.fullmatch(kiln_id):
            return invalid(name, 'Gathering evidence' if evidence else 'Looking up a kiln')
        label = f'{"Gathering evidence for" if evidence else "Looking up"} {kiln_id[:7]}…'
        record = api.get('/public/kilns/' + kiln_id)
        if record is None:
            return {'found': False, 'message': 'Not found or not flagged.'}, step(name, label, 'Not found', True), []
        if record.get('kiln_id') != kiln_id: raise UpstreamUnavailable('unexpected body')
        exposure = {'exposure_note': EXPOSURE_NOTE} if record.get('exposure') else {}
        if evidence:
            view, meta = trim(record, detail=True), record.get('evidence') or {}
            result = {'found': True, 'kiln_id': kiln_id, 'detected_on': view['last_seen'],
                      'satellite_images': view['satellite_images'],
                      'before_image': image_side(meta.get('before_metadata')), 'after_image': image_side(meta.get('after_metadata')),
                      'rules_assessment': view['rules_assessment'], 'siting_flags': view['siting_flags'],
                      'rule_checks': rule_words(record, with_source=True),
                      **{k: view[k] for k in ('rules_note',) if k in view},
                      **{k: view[k] for k in ('people_within_800m', 'children_under_five', 'adults_over_sixty')},
                      **exposure, 'note': NOTE}
        else:
            result = {'found': True, 'kiln': trim(record, detail=True), 'rule_checks': rule_words(record), **exposure, 'note': NOTE}
        return result, step(name, label, 'Found', True), [kiln_id]
    return invalid('unknown', 'Unknown tool')


def image_fields(views):
    """Lists carry no per-row image field (a boolean column was misread): one top-level ID list instead."""
    published = [view['kiln_id'] for view in views if view.pop('satellite_images') == 'published']
    return {'images_published_only_for': published, 'images_note': IMAGES_NOTE}


def table(views):
    """Columns once, then one row per kiln: about a third of the tokens of repeated keys."""
    columns = list(dict.fromkeys(key for view in views for key in view))
    return {'columns': columns, 'rows': [[view.get(c) for c in columns] for view in views]}


def records(body):
    kilns = body.get('kilns', [])
    if not isinstance(kilns, list) or not all(isinstance(k, dict) and isinstance(k.get('kiln_id'), str) for k in kilns):
        raise UpstreamUnavailable('unexpected body')
    return kilns


def invalid(name, label):
    return {'error': 'Invalid tool input. Check the allowed ranges and the full kiln ID format.'}, step(name, label, 'Invalid input', False), []


def step(tool, label, summary, ok):
    return {'tool': tool, 'label': label, 'summary': summary, 'ok': ok}

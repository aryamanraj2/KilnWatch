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


class UpstreamUnavailable(Exception):
    """The public API returned 429/5xx, timed out or was unreachable."""


SPECS = [
    {'toolSpec': {'name': 'list_flagged_kilns',
                  'description': 'List satellite-flagged kilns in a district (for example Hapur), with the total count.',
                  'inputSchema': {'json': {'type': 'object', 'properties': {
                      'district': {'type': 'string', 'description': 'District name, for example Hapur.'},
                      'limit': {'type': 'integer', 'minimum': 1, 'maximum': 50, 'description': 'Page size, default 50.'}},
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
]


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def valid_point(lat, lon):
    return number(lat) and number(lon) and -90 <= lat <= 90 and -180 <= lon <= 180


def integer(value, low, high, default):
    if value is None: return default
    if number(value) and float(value).is_integer() and low <= value <= high: return int(value)
    return None


def trim(record):
    """Only what the model needs. No URLs, polygons, metadata or internal fields."""
    centroid = record.get('footprint', {}).get('centroid', {})
    evidence = record.get('evidence') or {}
    view = {'kiln_id': record['kiln_id'], 'status': record.get('status'),
            'predicted_type': record.get('type'), 'type_verification': record.get('type_verification'),
            'model_score': record.get('detection_confidence'), 'district': record.get('district'),
            'centroid': [round(centroid['latitude'], 5), round(centroid['longitude'], 5)] if centroid else None,
            'first_seen': (record.get('first_seen') or '')[:10] or None,
            'last_seen': (record.get('last_seen') or '')[:10] or None,
            'rules_assessment': record.get('rules_assessment') or 'not_evaluated',
            'exposure_assessed': record.get('exposure') is not None,
            'images_published': bool(evidence.get('before') or evidence.get('after'))}
    if 'distance_m' in record: view['distance_m'] = record['distance_m']
    return view


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
        if not isinstance(district, str) or not DISTRICT.fullmatch(district) or limit is None:
            return invalid(name, label)
        kilns, cursor, pages = [], None, 0
        while pages < 2:
            query = {'district': district, 'limit': limit, **({'cursor': cursor} if cursor else {})}
            body = api.get('/public/kilns', query) or {}
            kilns += records(body); cursor = body.get('next_cursor'); pages += 1
            if not cursor: break
        shown = [trim(k) for k in kilns[:50]]
        more = bool(cursor)
        ids = [k['kiln_id'] for k in shown]
        result = {'district': district, 'count': len(kilns), 'more_pages': more, 'kilns_shown': len(shown),
                  'kilns': table(shown), 'note': NOTE}
        summary = f'{len(kilns)}{"+" if more else ""} found'
        return result, step(name, label, summary, True), ids
    if name == 'kilns_near':
        label = 'Searching near a point'
        lat, lon, radius = args.get('lat'), args.get('lon'), integer(args.get('radius_m'), 100, 5000, 2000)
        if not valid_point(lat, lon) or radius is None:
            return invalid(name, label)
        body = api.get('/public/kilns', {'lat': f'{lat:.6f}', 'lon': f'{lon:.6f}', 'radius_m': radius}) or {}
        shown = [trim(k) for k in records(body)[:50]]
        result = {'radius_m': radius, 'count': len(shown), 'kilns': table(shown), 'note': NOTE}
        return result, step(name, label, f'{len(shown)} within {radius} m', True), [k['kiln_id'] for k in shown]
    if name == 'kiln_detail':
        kiln_id = args.get('kiln_id')
        if not isinstance(kiln_id, str) or not KILN_ID.fullmatch(kiln_id):
            return invalid(name, 'Looking up a kiln')
        label = f'Looking up {kiln_id[:7]}…'
        record = api.get('/public/kilns/' + kiln_id)
        if record is None:
            return {'found': False, 'message': 'Not found or not flagged.'}, step(name, label, 'Not found', True), []
        if record.get('kiln_id') != kiln_id: raise UpstreamUnavailable('unexpected body')
        return {'found': True, 'kiln': trim(record), 'note': NOTE}, step(name, label, 'Found', True), [kiln_id]
    return invalid('unknown', 'Unknown tool')


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

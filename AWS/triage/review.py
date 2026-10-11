"""GET /public/review (prompt 40b): the read-only view of the change-triage review queue for the iOS Review tab.

One paginated Scan, memoized for 60 s in a warm Lambda. The response is an allowlist built from each stored item
(never the model ID, the raw facts blob or anything else). Nothing here can write: the role has Scan, not Update."""
import json
import re
import time
from triage.diff import GROUPS

MAX_ITEMS = 500
MEMO_SECONDS = 60
# The evidence CDN's published images, as 40 stored them; anything else is dropped, never passed through.
EVIDENCE_URL = re.compile(r'https://[a-z0-9]+\.cloudfront\.net/evidence/[0-9a-f]{64}\.png')
_memo = {'until': 0.0, 'body': None}


def scan(dynamodb, table):
    # ponytail: full scan, fine for a demo queue of tens of items; add a state index when the queue grows.
    items, start = [], None
    while True:
        page = dynamodb.scan(TableName=table, **({'ExclusiveStartKey': start} if start else {}))
        items += page.get('Items', [])
        start = page.get('LastEvaluatedKey')
        if not start: return items


def number(value, places):
    return round(value, places) if isinstance(value, (int, float)) and not isinstance(value, bool) else None


def side(value):
    return {'type': value.get('type'), 'score': number(value.get('score'), 3)} if isinstance(value, dict) else None


def item(raw, facts):
    evidence = facts.get('evidence') or {}
    urls = {k: evidence[k] if isinstance(evidence.get(k), str) and EVIDENCE_URL.fullmatch(evidence[k]) else None
            for k in ('before', 'after')}
    lat, lon = facts['centroid']
    return {'item_id': raw['item_id']['S'], 'group': raw['group']['S'], 'state': raw['state']['S'],
            'kiln_id': raw.get('kiln_id', {}).get('S'), 'reason': raw['reason']['S'],
            'centroid': {'lat': number(lat, 5), 'lon': number(lon, 5)},
            'baseline': side(facts.get('baseline')), 'current': side(facts.get('current')),
            'iou': number(facts.get('iou'), 3), 'evidence': urls if any(urls.values()) else None,
            'created_at': raw['created_at']['S'].replace('+00:00', 'Z')}


def build(raw_items):
    """The 200 body. Only the latest baseline run (by created_at) is shown; counts cover all of its items."""
    rows = [(raw, json.loads(raw['facts']['S'])) for raw in raw_items]
    latest = max(rows, key=lambda r: r[0]['created_at']['S'])[0]['baseline_run']['S'] if rows else None
    rows = [r for r in rows if r[0]['baseline_run']['S'] == latest]
    items = sorted((item(raw, facts) for raw, facts in rows),
                   key=lambda i: (GROUPS.index(i['group']), i['kiln_id'] is None, i['kiln_id'] or '', i['item_id']))
    first = rows[0] if rows else None
    return {'baseline': first and {'run': latest, 'scene': first[1]['baseline_scene']['id'],
                                   'date': first[1]['baseline_scene']['date']},
            'current': first and {'label': first[0]['current']['S'], 'scene': first[1]['current_scene']['id'],
                                  'date': first[1]['current_scene']['date']},
            'counts': {g: sum(i['group'] == g for i in items) for g in GROUPS},
            'truncated': len(items) > MAX_ITEMS, 'items': items[:MAX_ITEMS]}


def read(dynamodb, table, clock=time.monotonic):
    """The memoized body. Any failure propagates (the handler answers 503) and is never memoized."""
    if _memo['body'] is None or clock() >= _memo['until']:
        _memo['body'] = build(scan(dynamodb, table))
        _memo['until'] = clock() + MEMO_SECONDS
    return _memo['body']

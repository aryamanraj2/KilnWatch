"""POST /routes/plan: public, no login. Boundary validation, the public API read, the daily cap, then planner.plan.

The cap shares the assistant's on-demand DynamoDB counter table under its own key (route#YYYY-MM-DD), so the
IAM grant is one UpdateItem limited to that key prefix. The count happens after the free reads and before any
Amazon Location call, so every billed plan is counted."""
import base64
import json
import logging
import os
import time
from datetime import datetime, timedelta, timezone
import planner
from tools import DISTRICT, KILN_ID, PublicAPI, UpstreamUnavailable, integer, records, valid_point

log = logging.getLogger('kilnwatch.route')
log.setLevel(logging.INFO)
MAX_BODY = 4096
KEYS = {'district', 'start', 'depart', 'budget_min', 'max_stops', 'priority', 'kiln_ids'}
MAX_PAGES = 5


class CapReached(Exception):
    pass


def response(status, body):
    return {'statusCode': status, 'headers': {'content-type': 'application/json', 'cache-control': 'no-store'},
            'body': json.dumps(body, allow_nan=False, ensure_ascii=False)}


def error(status, code, message, retryable=False):
    return response(status, {'error': {'code': code, 'message': message, 'retryable': retryable}})


def parse(event, now):
    """Returns the validated request, or None. Anything unexpected is rejected."""
    def no_constants(name): raise ValueError(name)
    try:
        body = event.get('body') or ''
        raw = base64.b64decode(body, validate=True) if event.get('isBase64Encoded') else body.encode()
        if len(raw) > MAX_BODY: return None
        data = json.loads(raw, parse_constant=no_constants)
    except (ValueError, TypeError, AttributeError):
        return None
    if not isinstance(data, dict) or set(data) - KEYS: return None
    district = data.get('district')
    if not isinstance(district, str) or not DISTRICT.fullmatch(district): return None
    start = data.get('start')
    if 'start' in data and not (isinstance(start, dict) and set(start) == {'lat', 'lon'} and valid_point(start['lat'], start['lon'])):
        return None
    depart = planner.default_depart(now)
    if 'depart' in data:
        text = data['depart']
        try:
            if not isinstance(text, str) or len(text) > 40 or 'T' not in text: return None
            depart = datetime.fromisoformat(text)
        except ValueError:
            return None
        if depart.tzinfo is None: return None
    budget, stops = integer(data.get('budget_min'), 60, 720, 480), integer(data.get('max_stops'), 1, planner.MAX_KILNS, planner.MAX_KILNS)
    priority = data.get('priority', 'people')
    if budget is None or stops is None or priority not in ('people', 'flags'): return None
    kiln_ids = data.get('kiln_ids')
    if 'kiln_ids' in data and not (isinstance(kiln_ids, list) and 1 <= len(kiln_ids) <= planner.MAX_KILNS
                                   and all(isinstance(k, str) and KILN_ID.fullmatch(k) for k in kiln_ids)
                                   and len(set(kiln_ids)) == len(kiln_ids)):
        return None
    return {'district': district, 'start': start, 'depart': depart, 'budget_min': budget, 'max_stops': stops,
            'priority': priority, 'kiln_ids': sorted(kiln_ids) if kiln_ids else None}


def district_kilns(api, district):
    kilns, cursor = [], None
    for _ in range(MAX_PAGES):
        body = api.get('/public/kilns', {'district': district, 'limit': 200, **({'cursor': cursor} if cursor else {})}) or {}
        kilns += records(body); cursor = body.get('next_cursor')
        if not cursor: break
    return kilns


def count_plan(dynamodb, table, cap, now):
    """One atomic conditional ADD per plan. Raises CapReached at the cap; any other failure propagates."""
    day = 'route#' + now.strftime('%Y-%m-%d')
    expires = int((now + timedelta(days=3)).timestamp())
    try:
        dynamodb.update_item(TableName=table, Key={'day': {'S': day}},
                             UpdateExpression='ADD plan_count :one SET expires_at = :expires',
                             ConditionExpression='attribute_not_exists(plan_count) OR plan_count < :cap',
                             ExpressionAttributeValues={':one': {'N': '1'}, ':cap': {'N': str(cap)},
                                                        ':expires': {'N': str(expires)}})
    except Exception as exc:
        if getattr(exc, 'response', {}).get('Error', {}).get('Code') == 'ConditionalCheckFailedException':
            raise CapReached() from None
        raise


def handle(event, context, *, dynamodb, geo, api, now=None):
    started = time.monotonic()
    now = now or datetime.now(timezone.utc)
    metrics = {}
    def done(result):
        # Counts and latencies only. Never coordinates, kiln IDs or bodies.
        log.info(json.dumps({'event': 'route_plan', 'request_id': getattr(context, 'aws_request_id', None),
                             'status': result['statusCode'], **metrics, 'total_ms': int((time.monotonic() - started) * 1000)}))
        return result
    http = event.get('requestContext', {}).get('http', {})
    if http.get('method') != 'POST' or event.get('rawPath') != '/routes/plan':
        return done(error(404, 'not_found', 'Endpoint not found.'))
    request = parse(event, now)
    if request is None:
        return done(error(400, 'invalid_request',
                          'Send JSON (at most 4 KB) with a district, and optionally start {lat, lon}, depart (RFC 3339 with '
                          'an offset), budget_min 60-720, max_stops 1-8, priority "people" or "flags", and up to 8 full kiln_ids.'))
    try:
        candidates, left_out = planner.select(request, district_kilns(api, request['district']))
    except UpstreamUnavailable:
        return done(error(503, 'upstream_unavailable', 'Kiln data is temporarily unavailable. Try again.', True))
    except planner.NoKilns:
        return done(error(404, 'no_kilns', 'No flagged kilns with an exposure estimate were found to plan.'))
    try:
        count_plan(dynamodb, os.environ['COUNTER_TABLE'], int(os.environ.get('DAILY_CAP', '15')), now)
    except CapReached:
        return done(error(429, 'daily_cap_reached', "Route planning has reached today's limit. Try again tomorrow."))
    except Exception:
        # Fail closed: Amazon Location is never called without a successful count.
        return done(error(503, 'routing_unavailable', 'Route planning is temporarily unavailable.', True))
    try:
        body = planner.plan(request, candidates, left_out, geo(), now, metrics)
    except planner.RoutingUnavailable:
        return done(error(503, 'routing_unavailable', 'Road routing is temporarily unavailable. Try again.', True))
    return done(response(200, body))


_clients = {}


def client(name, **timeouts):
    if name not in _clients:
        import boto3
        from botocore.config import Config
        _clients[name] = boto3.client(name, config=Config(**timeouts, retries={'total_max_attempts': 2}))
    return _clients[name]


def geo_client():
    try:
        return client('geo-routes', connect_timeout=2, read_timeout=5)
    except Exception:
        raise planner.RoutingUnavailable() from None


def handler(event, context):
    return handle(event, context, dynamodb=client('dynamodb', connect_timeout=2, read_timeout=3), geo=geo_client,
                  api=PublicAPI(os.environ['PUBLIC_API_BASE_URL']))

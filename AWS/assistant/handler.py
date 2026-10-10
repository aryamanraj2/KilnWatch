"""POST /ask: public, no login. Boundary validation, the global daily cap, then core.answer.

The daily cap uses one on-demand DynamoDB counter. Prompt 10 says "no DynamoDB unless RDS truly cannot
serve it": this Lambda runs outside the VPC by design (it reads only the public API), so it cannot reach
RDS, and one atomic counter item per UTC day is the cheapest correct option."""
import base64
import json
import logging
import os
import time
from datetime import datetime, timedelta, timezone
import core
from tools import KILN_ID, UpstreamUnavailable, valid_point

log = logging.getLogger('kilnwatch.assistant')
log.setLevel(logging.INFO)
MAX_BODY = 2048
MAX_QUESTION = 500
KEYS = {'question', 'kiln_id', 'lat', 'lon'}


class CapReached(Exception):
    pass


def response(status, body):
    return {'statusCode': status, 'headers': {'content-type': 'application/json', 'cache-control': 'no-store'},
            'body': json.dumps(body, allow_nan=False)}


def error(status, code, message, retryable=False):
    return response(status, {'error': {'code': code, 'message': message, 'retryable': retryable}})


def parse(event):
    """Returns (question, kiln_id, lat, lon) or None. Anything unexpected is rejected."""
    def no_constants(name): raise ValueError(name)
    try:
        body = event.get('body') or ''
        raw = base64.b64decode(body, validate=True) if event.get('isBase64Encoded') else body.encode()
        if len(raw) > MAX_BODY: return None
        data = json.loads(raw, parse_constant=no_constants)
    except (ValueError, TypeError, AttributeError):
        return None
    if not isinstance(data, dict) or set(data) - KEYS: return None
    question, kiln_id, lat, lon = data.get('question'), data.get('kiln_id'), data.get('lat'), data.get('lon')
    if not isinstance(question, str) or not 1 <= len(question.strip()) <= MAX_QUESTION: return None
    if 'kiln_id' in data and not (isinstance(kiln_id, str) and KILN_ID.fullmatch(kiln_id)): return None
    if ('lat' in data) != ('lon' in data): return None
    if 'lat' in data and not valid_point(lat, lon): return None
    return question.strip(), kiln_id, lat, lon


def count_question(dynamodb, table, cap, now):
    """One atomic conditional ADD per question. Raises CapReached at the cap; any other failure propagates."""
    day = now.strftime('%Y-%m-%d')
    expires = int((now + timedelta(days=3)).timestamp())
    try:
        dynamodb.update_item(TableName=table, Key={'day': {'S': day}},
                             UpdateExpression='ADD question_count :one SET expires_at = :expires',
                             ConditionExpression='attribute_not_exists(question_count) OR question_count < :cap',
                             ExpressionAttributeValues={':one': {'N': '1'}, ':cap': {'N': str(cap)},
                                                        ':expires': {'N': str(expires)}})
    except Exception as exc:
        if getattr(exc, 'response', {}).get('Error', {}).get('Code') == 'ConditionalCheckFailedException':
            raise CapReached() from None
        raise


def handle(event, context, *, dynamodb, ask, now=None):
    started = time.monotonic()
    request_id = getattr(context, 'aws_request_id', None)
    metrics = {}
    def done(result):
        # Counts and latencies only. Never the question, answer, kiln_id, coordinates or tool bodies.
        log.info(json.dumps({'event': 'ask', 'request_id': request_id, 'status': result['statusCode'], **metrics,
                             'total_ms': int((time.monotonic() - started) * 1000)}))
        return result
    http = event.get('requestContext', {}).get('http', {})
    if http.get('method') != 'POST' or event.get('rawPath') != '/ask':
        return done(error(404, 'not_found', 'Endpoint not found.'))
    request = parse(event)
    if request is None:
        return done(error(400, 'invalid_request',
                          'Send JSON with a question of at most 500 characters, an optional full kiln_id, '
                          'and optional lat and lon together.'))
    try:
        count_question(dynamodb, os.environ['COUNTER_TABLE'], int(os.environ.get('DAILY_CAP', '50')),
                       now or datetime.now(timezone.utc))
    except CapReached:
        return done(error(429, 'daily_cap_reached', "Ask has reached today's limit. Try again tomorrow."))
    except Exception:
        # Fail closed: Bedrock is never called without a successful count.
        return done(error(503, 'assistant_unavailable', 'Ask is temporarily unavailable.', True))
    remaining = getattr(context, 'get_remaining_time_in_millis', lambda: 28000)() / 1000
    question, kiln_id, lat, lon = request
    try:
        body = ask(question, kiln_id, lat, lon, deadline=time.monotonic() + remaining - 1, metrics=metrics)
    except UpstreamUnavailable:
        return done(error(503, 'upstream_unavailable', 'Kiln data is temporarily unavailable. Try again.', True))
    except core.ModelUnavailable as exc:
        return done(error(503, 'model_unavailable', 'The assistant model is temporarily unavailable.', exc.retryable))
    return done(response(200, body))


_dynamodb = None


def handler(event, context):
    global _dynamodb
    if _dynamodb is None:
        import boto3
        from botocore.config import Config
        _dynamodb = boto3.client('dynamodb', config=Config(connect_timeout=2, read_timeout=3, retries={'total_max_attempts': 2}))
    return handle(event, context, dynamodb=_dynamodb, ask=core.answer)

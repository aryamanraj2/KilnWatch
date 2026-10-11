"""Anonymous inspection signals; no candidate updates or private request logging."""
import base64
from contextlib import closing
from datetime import datetime, timezone
import hashlib
import json
import logging
import time
from uuid import UUID
from registry.db import connect_from_env
from registry.requests import CONCERNS, aggregate
from verdicts.handler import FULL_ID, UUID_TEXT, cleanup, response
from verdicts.store import VerdictError

log = logging.getLogger(__name__)
log.setLevel(logging.INFO)
BANDS = ('under_1km', '1_to_5km', 'over_5km', 'not_said')


def invalid():
    return VerdictError(400, 'invalid_request', 'Inspection request body is invalid.')


def unique_object(pairs):
    obj = {}
    for key, value in pairs:
        if key in obj: raise invalid()
        obj[key] = value
    return obj


def validate(event):
    try:
        headers = {k.lower(): v for k, v in (event.get('headers') or {}).items()}
        if headers.get('content-type', '').split(';')[0].strip().lower() != 'application/json': raise invalid()
        raw = event.get('body')
        if not isinstance(raw, str) or len(raw.encode('utf-8')) > (5464 if event.get('isBase64Encoded') else 4096): raise invalid()
        raw = base64.b64decode(raw, validate=True) if event.get('isBase64Encoded') else raw.encode('utf-8')
        if len(raw) > 4096: raise invalid()
        body = json.loads(raw, object_pairs_hook=unique_object,
                          parse_constant=lambda _: (_ for _ in ()).throw(invalid()))
        if not isinstance(body, dict) or set(body) != {'kiln_id','client_id','concerns','distance_band','lang'}: raise invalid()
        if not isinstance(body['kiln_id'], str) or not FULL_ID.fullmatch(body['kiln_id']): raise invalid()
        client = body['client_id']
        if not isinstance(client, str) or not UUID_TEXT.fullmatch(client) or UUID(client).version != 4: raise invalid()
        concerns = body['concerns']
        if (not isinstance(concerns, list) or not 1 <= len(concerns) <= 4
            or any(not isinstance(c, str) or c not in CONCERNS for c in concerns)
            or len(set(concerns)) != len(concerns)): raise invalid()
        if body['distance_band'] not in BANDS or body['lang'] not in ('en','hi'): raise invalid()
        return {k: v for k, v in body.items() if k != 'client_id'} | {
            'client_hash': hashlib.sha256(str(UUID(client)).encode()).hexdigest()}
    except VerdictError: raise
    except (ValueError, TypeError, KeyError, AttributeError, UnicodeError, OverflowError): raise invalid() from None


def record(connection, body, now=None):
    """Insert then cap in one transaction; a cap failure rolls the insert back."""
    now = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
    with closing(connection.cursor()) as cur:
        # Serialize writes to the same kiln without requiring candidate UPDATE privilege.
        lock = int(hashlib.sha256(body['kiln_id'].encode()).hexdigest()[:16],16) - (1 << 63)
        cur.execute('SELECT pg_advisory_xact_lock(%s::bigint)', (lock,))
        cur.execute('SELECT kiln_id FROM kilnwatch.candidates WHERE kiln_id=%s', (body['kiln_id'],))
        if not cur.fetchone(): raise VerdictError(404,'not_found','Kiln not found.')
        cur.execute('''INSERT INTO kilnwatch.inspection_requests
 (kiln_id,client_hash,concerns,distance_band,lang,created_at) VALUES (%s,%s,%s,%s,%s,%s)
 ON CONFLICT (kiln_id,client_hash) DO NOTHING RETURNING request_id''',
                    (body['kiln_id'],body['client_hash'],body['concerns'],body['distance_band'],body['lang'],now))
        created = cur.fetchone() is not None
        if created:
            cur.execute('''INSERT INTO kilnwatch.request_days AS d (day,count) VALUES (%s,1)
 ON CONFLICT (day) DO UPDATE SET count=d.count+1 WHERE d.count<300 RETURNING count''', (now.date(),))
            if not cur.fetchone(): raise VerdictError(429,'daily_cap_reached',"Today's request limit is reached. Try again tomorrow.",True)
        return (201 if created else 200), {'kiln_id':body['kiln_id'], 'created':created,
                                           'resident_requests':aggregate(cur,body['kiln_id'])}


def handle(event, connection_factory=connect_from_env, now=None):
    started = time.monotonic()
    connection = None
    result = response(503,{'error':{'code':'registry_unavailable','message':'The registry is temporarily unavailable.','retryable':True}})
    try:
        body = validate(event)
        connection = connection_factory()
        status, data = record(connection,body,now)
        connection.commit()
        result = response(status,data)
    except VerdictError as exc:
        cleanup(connection,'rollback')
        result = response(exc.status,{'error':{'code':exc.code,'message':exc.message,'retryable':exc.retryable}})
    except Exception:
        cleanup(connection,'rollback')
    finally:
        cleanup(connection,'close')
        data = json.loads(result['body'])
        log.info(json.dumps({'count':data.get('resident_requests',{}).get('count',0),
                             'status_code':result['statusCode'],'latency_ms':round((time.monotonic()-started)*1000)}))
    return result

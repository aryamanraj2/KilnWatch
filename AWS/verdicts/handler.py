"""Public demo writes: strict validation, transactional cap, private photo PUT signing."""
import base64
from datetime import datetime, timedelta, timezone
import hashlib
import json
import logging
import math
import os
import re
import time
from uuid import UUID

from registry.db import connect_from_env
from verdicts.store import VerdictError, record

log = logging.getLogger(__name__)
log.setLevel(logging.INFO)
FULL_ID = re.compile(r'KW-[0-9a-f]{32}')
UUID_TEXT = re.compile(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}')
ISO = re.compile(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})')
OUTCOMES = ('confirmed', 'compliant', 'not_a_kiln', 'closed')


def invalid():
    return VerdictError(400, 'invalid_request', 'Verdict body or Idempotency-Key is invalid.')


def uuid(value):
    if not isinstance(value, str) or not UUID_TEXT.fullmatch(value):
        raise invalid()
    return str(UUID(value))


def timestamp(value):
    if not isinstance(value, str) or not ISO.fullmatch(value):
        raise invalid()
    try:
        return datetime.fromisoformat(value.replace('Z', '+00:00')).astimezone(timezone.utc)
    except ValueError:
        raise invalid() from None


def finite(value, low, high=math.inf):
    return type(value) in (int, float) and math.isfinite(value) and low <= value <= high


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise invalid()
        result[key] = value
    return result


def validate(event, now):
    try:
        raw = event.get('body')
        if not isinstance(raw, str) or len(raw.encode('utf-8')) > (21848 if event.get('isBase64Encoded') else 16384):
            raise invalid()
        raw = base64.b64decode(raw, validate=True) if event.get('isBase64Encoded') else raw.encode('utf-8')
        if len(raw) > 16384:
            raise invalid()
        body = json.loads(raw, object_pairs_hook=unique_object, parse_constant=lambda _: (_ for _ in ()).throw(invalid()))
        if not isinstance(body, dict) or set(body) - {'id', 'kiln_id', 'outcome', 'photos', 'note', 'recorded_at'}:
            raise invalid()
        body['id'] = uuid(body['id'])
        headers = {key.lower(): value for key, value in (event.get('headers') or {}).items()}
        if uuid(headers.get('idempotency-key')) != body['id']:
            raise invalid()
        if not isinstance(body['kiln_id'], str) or not FULL_ID.fullmatch(body['kiln_id']) or body['outcome'] not in OUTCOMES:
            raise invalid()
        if timestamp(body['recorded_at']) > now + timedelta(minutes=10):
            raise invalid()
        body.setdefault('note', None)
        if body['note'] is not None and (not isinstance(body['note'], str) or len(body['note']) > 2000):
            raise invalid()
        photos = body['photos']
        if not isinstance(photos, list) or len(photos) > 8:
            raise invalid()
        ids = set()
        for photo in photos:
            if not isinstance(photo, dict) or set(photo) != {'id', 'latitude', 'longitude', 'horizontal_accuracy_m', 'taken_at'}:
                raise invalid()
            photo['id'] = uuid(photo['id'])
            if photo['id'] in ids:
                raise invalid()
            ids.add(photo['id'])
            if not (finite(photo['latitude'], -90, 90) and finite(photo['longitude'], -180, 180)
                    and finite(photo['horizontal_accuracy_m'], 0)):
                raise invalid()
            timestamp(photo['taken_at'])
        canonical = json.dumps(body, sort_keys=True, separators=(',', ':'), allow_nan=False, ensure_ascii=False)
        return body, hashlib.sha256(canonical.encode('utf-8')).hexdigest()
    except VerdictError:
        raise
    except (ValueError, TypeError, KeyError, OverflowError, AttributeError, UnicodeError):
        raise invalid() from None


def response(status, body):
    return {'statusCode': status, 'headers': {'content-type': 'application/json', 'cache-control': 'no-store'},
            'body': json.dumps(body, allow_nan=False)}


def cleanup(connection, method):
    # Cleanup must not replace a sanitized response with a connection exception.
    if connection:
        try: getattr(connection, method)()
        except Exception: pass


def handle(event, connection_factory=connect_from_env, s3=None, now=None):
    started = time.monotonic()
    connection = None
    body = None
    try:
        now = now or datetime.now(timezone.utc)
        body, sha = validate(event, now)
        connection = connection_factory()
        status, photos = record(connection, body, sha, now)
        if photos and s3 is None:
            import boto3
            from botocore.config import Config
            s3 = boto3.client('s3', config=Config(signature_version='s3v4'))
        uploads = [{'photo_id': p['id'], 'upload_url': s3.generate_presigned_url(
            'put_object', Params={'Bucket': os.environ['DATA_BUCKET'], 'Key': p['object_key'], 'ContentType': 'image/jpeg'},
            ExpiresIn=900, HttpMethod='PUT')} for p in photos]
        connection.commit()
        return response(status, {'id': body['id'], 'photo_uploads': uploads})
    except VerdictError as exc:
        cleanup(connection, 'rollback')
        return response(exc.status, {'error': {'code': exc.code, 'message': exc.message, 'retryable': exc.retryable}})
    except Exception:
        cleanup(connection, 'rollback')
        return response(503, {'error': {'code': 'registry_unavailable', 'message': 'The registry is temporarily unavailable.', 'retryable': True}})
    finally:
        cleanup(connection, 'close')
        # Allowlisted facts only; never exceptions, request bodies, IDs or location.
        log.info(json.dumps({'photos': len(body['photos']) if body else 0,
                             'outcome': body['outcome'] if body else None,
                             'latency_ms': round((time.monotonic() - started) * 1000)}))


def handler(event, context):
    return handle(event)

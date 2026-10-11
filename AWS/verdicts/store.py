"""Transactional verdict queries; the caller commits or rolls back the entire operation."""
from contextlib import closing
from datetime import datetime, timezone
import json


class VerdictError(Exception):
    def __init__(self, status, code, message, retryable=False):
        super().__init__(message)
        self.status, self.code, self.message, self.retryable = status, code, message, retryable


def record(connection, body, body_sha256, now=None):
    """Locks UUID then candidate then day. Replays and missing kilns never consume cap."""
    now = now or datetime.now(timezone.utc)
    with closing(connection.cursor()) as cur:
        # UUID-wide serialization also handles conflicting replays targeting different kilns.
        # Hash collisions only serialize unrelated requests; the PK remains the identity.
        cur.execute('SELECT pg_advisory_xact_lock(%s::bigint)',
                    (int(body['id'].replace('-', '')[:16], 16) - (1 << 63),))
        cur.execute('SELECT body_sha256,photos FROM kilnwatch.verdicts WHERE verdict_id=%s::uuid', (body['id'],))
        previous = cur.fetchone()
        if previous:
            if previous[0] != body_sha256:
                raise VerdictError(409, 'idempotency_conflict', 'This verdict ID already has a different body.')
            photos = json.loads(previous[1]) if isinstance(previous[1], str) else previous[1]
            return 200, photos
        cur.execute('SELECT kiln_id FROM kilnwatch.candidates WHERE kiln_id=%s FOR UPDATE', (body['kiln_id'],))
        if not cur.fetchone():
            raise VerdictError(404, 'not_found', 'Kiln not found.')
        cur.execute('''INSERT INTO kilnwatch.verdict_days AS d (day,count) VALUES (%s,1)
ON CONFLICT (day) DO UPDATE SET count=d.count+1 WHERE d.count<30 RETURNING count''', (now.date(),))
        if not cur.fetchone():
            raise VerdictError(429, 'daily_cap_reached', 'The daily verdict limit has been reached.', True)
        photos = [{**photo, 'object_key': f"verdicts/{body['id']}/{photo['id']}.jpg"} for photo in body['photos']]
        cur.execute('''INSERT INTO kilnwatch.verdicts
(verdict_id,kiln_id,outcome,note,recorded_at,body_sha256,photos)
VALUES (%s::uuid,%s,%s,%s,%s::timestamptz,%s,%s::jsonb)''',
                    (body['id'], body['kiln_id'], body['outcome'], body['note'], body['recorded_at'],
                     body_sha256, json.dumps(photos, allow_nan=False)))
        cur.execute('''UPDATE kilnwatch.candidates c SET status=%s,review_state='reviewed'
WHERE c.kiln_id=%s AND NOT EXISTS
(SELECT 1 FROM kilnwatch.verdicts v WHERE v.kiln_id=c.kiln_id AND v.recorded_at>%s::timestamptz)''',
                    (body['outcome'], body['kiln_id'], body['recorded_at']))
        return 201, photos

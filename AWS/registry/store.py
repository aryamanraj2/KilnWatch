"""Parameterized PostGIS import/read queries. DB-API connection owned by caller."""
import json
from contextlib import closing
from .contract import canonical, digest, serialize


def persist(connection, records, input_hash, model_hash, evidence_hash=None):
    run_id = digest([input_hash, model_hash, evidence_hash, [r['payload']['district'] for r in records]])
    cursor = connection.cursor()
    counts = {'run_id': run_id, 'candidates_inserted': 0, 'observations_inserted': 0, 'records': len(records)}
    try:
        cursor.execute('INSERT INTO kilnwatch.import_runs (run_id,input_sha256,model_sha256,evidence_sha256,record_count) VALUES (%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING',
                       (run_id, input_hash, model_hash, evidence_hash, len(records)))
        for r in records:
            p, key = r['payload'], r['observation_id']
            cursor.execute('INSERT INTO kilnwatch.candidates (kiln_id,district,first_seen,last_seen) VALUES (%s,%s,%s,%s) ON CONFLICT DO NOTHING',
                           (p['kiln_id'], p['district'], p['first_seen'], p['last_seen']))
            counts['candidates_inserted'] += max(0, cursor.rowcount)
            cursor.execute('SELECT district FROM kilnwatch.candidates WHERE kiln_id=%s FOR UPDATE', (p['kiln_id'],))
            if cursor.fetchone()[0] != p['district']:
                raise ValueError('candidate district differs; administrative review required')
            cursor.execute('UPDATE kilnwatch.candidates SET first_seen=LEAST(first_seen,%s), last_seen=GREATEST(last_seen,%s) WHERE kiln_id=%s',
                           (p['first_seen'], p['last_seen'], p['kiln_id']))
            cursor.execute('INSERT INTO kilnwatch.observations (observation_id,kiln_id,scene_id,acquired_at,model_sha256,footprint,payload) VALUES (%s,%s,%s,%s,%s,ST_SetSRID(ST_GeomFromGeoJSON(%s),4326),%s::jsonb) ON CONFLICT DO NOTHING',
                           (key,p['kiln_id'],p['provenance']['scene_id'],p['last_seen'],model_hash,canonical(r['geometry']),canonical(p)))
            counts['observations_inserted'] += max(0, cursor.rowcount)
            cursor.execute('INSERT INTO kilnwatch.run_observations VALUES (%s,%s) ON CONFLICT DO NOTHING', (run_id,key))
            for side in ('before','after'):
                meta = p['evidence'].get(side+'_metadata')
                if meta:
                    # A replay without a receipt keeps a verified URL; published bytes are never swapped.
                    cursor.execute('''INSERT INTO kilnwatch.evidence AS e VALUES (%s,%s,%s,%s,%s::jsonb) ON CONFLICT (observation_id,side) DO UPDATE
SET sha256=EXCLUDED.sha256, object_key=EXCLUDED.object_key,
 metadata=CASE WHEN EXCLUDED.metadata->>'published_url' IS NULL AND e.metadata->>'published_url' IS NOT NULL
  THEN EXCLUDED.metadata||jsonb_build_object('published_url',e.metadata->'published_url') ELSE EXCLUDED.metadata END
WHERE e.metadata->>'published_url' IS NULL OR e.sha256=EXCLUDED.sha256''',
                                   (key,side,meta['sha256'],meta['object_key'],canonical(meta)))
                    if cursor.rowcount != 1:
                        raise ValueError('published evidence differs; administrative review required')
        connection.commit()
        return counts
    except Exception:
        connection.rollback()
        raise
    finally:
        cursor.close()


READ = '''SELECT c.kiln_id,c.status,c.review_state,c.assessment,c.first_seen,c.last_seen,o.payload,o.observation_id
FROM kilnwatch.candidates c JOIN LATERAL
(SELECT payload,observation_id FROM kilnwatch.observations WHERE kiln_id=c.kiln_id
 ORDER BY acquired_at DESC,observation_id LIMIT 1) o ON true'''


class Registry:
    def __init__(self, connection):
        self.connection = connection

    def _records(self, clause, args):
        with closing(self.connection.cursor()) as cur:
            cur.execute(READ + clause, args)
            rows = cur.fetchall()
            result = []
            for kiln_id,status,review,assessment,first,last,payload,key in rows:
                if isinstance(payload,str): payload=json.loads(payload)
                if isinstance(assessment,str): assessment=json.loads(assessment)
                payload['first_seen']=first.isoformat().replace('+00:00','Z')
                payload['last_seen']=last.isoformat().replace('+00:00','Z')
                payload['evidence']={'before':None,'after':None}
                cur.execute('SELECT side,metadata FROM kilnwatch.evidence WHERE observation_id=%s', (key,))
                for side,meta in cur.fetchall():
                    if isinstance(meta,str): meta=json.loads(meta)
                    payload['evidence'][side+'_metadata']=meta
                    payload['evidence'][side]=meta.get('published_url')
                result.append(serialize(payload,status,review,assessment))
            return result

    def list(self, district, status=None, cursor='', limit=100):
        rows = self._records(' WHERE c.district=%s AND (%s::text IS NULL OR c.status=%s) AND c.kiln_id>%s ORDER BY c.kiln_id LIMIT %s',
                             (district,status,status,cursor,limit+1))
        return {'kilns': rows[:limit], 'next_cursor': rows[limit-1]['kiln_id'] if len(rows)>limit else None}

    def detail(self, kiln_id, district):
        rows = self._records(' WHERE c.kiln_id=%s AND c.district=%s', (kiln_id,district))
        return rows[0] if rows else None

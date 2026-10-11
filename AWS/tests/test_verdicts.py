"""Demo verdict validation, privacy and database transaction tests; all records synthetic."""
import base64
from contextlib import closing
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import sys
import threading
import unittest
from unittest.mock import Mock, patch
from uuid import uuid4

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fixtures import records, event, handle as public_handle, MemoryRegistry
from registry.cli import migrate
from verdicts import bootstrap
from registry.contract import public_view, serialize
from registry.store import Registry, persist, reset_verdict
from verdicts.handler import handle, validate
from verdicts.store import record, VerdictError

NOW = datetime(2026, 10, 11, 10, tzinfo=timezone.utc)
KILN = 'KW-' + 'a' * 32
VID = '6f9619ff-8b86-d011-b42d-00c04fc964ff'
PID = '1b4e28ba-2fa1-11d2-883f-0016d3cca427'


def body():
    return {'id': VID, 'kiln_id': KILN, 'outcome': 'confirmed', 'note': 'Synthetic note',
            'recorded_at': '2026-10-11T09:00:00Z', 'photos': [{'id': PID, 'latitude': 28.7,
            'longitude': 77.7, 'horizontal_accuracy_m': 6, 'taken_at': '2026-10-11T08:59:00Z'}]}


def request(b=None):
    b = body() if b is None else b
    return {'body': json.dumps(b), 'headers': {'Idempotency-Key': b.get('id', VID)}}


class ValidationTests(unittest.TestCase):
    def reject(self, b):
        with self.assertRaises(VerdictError) as e: validate(request(b), NOW)
        self.assertEqual(e.exception.status, 400)

    def test_valid_case_insensitive_uuid_and_header(self):
        b = body(); b['id'] = VID.upper(); b['photos'][0]['id'] = PID.upper()
        e = request(b); e['headers'] = {'IDEMPOTENCY-KEY': VID}
        self.assertEqual(validate(e, NOW), validate(request(), NOW))

    def test_unknown_missing_and_wrong_top_level_keys(self):
        for key in body():
            if key == 'note': continue
            b = body(); del b[key]; self.reject(b)
        for b in [[], None, 'text', {'extra': 1}, body() | {'extra': 1}]:
            e = {'body': json.dumps(b), 'headers': {'Idempotency-Key': VID}}
            with self.assertRaises(VerdictError): validate(e, NOW)

    def test_uuid_and_full_kiln_and_outcome(self):
        for key, values in [('id', ['', 'x', VID.replace('-', ''), None, 1]),
                            ('kiln_id', ['KW-0412', 'KW-'+'G'*32, KILN+'x', None, 1]),
                            ('outcome', ['', 'flagged', 'unknown', None, {}, []])]:
            for value in values:
                with self.subTest(key=key, value=value): self.reject(body() | {key: value})
        e = request(); e['headers'] = {}
        with self.assertRaises(VerdictError): validate(e, NOW)
        e['headers'] = {'Idempotency-Key': str(uuid4())}
        with self.assertRaises(VerdictError): validate(e, NOW)

    def test_note_limits_and_optional_null(self):
        for n in [12, [], {}, 'x'*2001]: self.reject(body() | {'note': n})
        for n in [None, '', 'x'*2000]: validate(request(body() | {'note': n}), NOW)
        b = body(); del b['note']; self.assertIsNone(validate(request(b), NOW)[0]['note'])

    def test_recorded_time_validation_and_future_boundary(self):
        for t in ['2026-10-11', '2026-10-11T09:00:00', '2026-13-11T09:00:00Z',
                  '2026-10-11 09:00:00Z', None, 5, '2026-10-11T10:10:00.000001Z']:
            self.reject(body() | {'recorded_at': t})
        validate(request(body() | {'recorded_at': '2026-10-11T10:10:00Z'}), NOW)
        validate(request(body() | {'recorded_at': '2020-10-11T15:00:00+05:30'}), NOW)

    def test_photo_limits_and_key_validation(self):
        for p in [None, {}, [None], [body()['photos'][0]]*9]: self.reject(body() | {'photos': p})
        for key in body()['photos'][0]:
            b = body(); del b['photos'][0][key]; self.reject(b)
        b = body(); b['photos'][0]['object_key'] = 'x'; self.reject(b)
        b = body(); b['photos'][0]['id'] = 'bad'; self.reject(b)
        b = body(); b['photos'][0]['taken_at'] = 'bad'; self.reject(b)
        b = body(); b['photos'] *= 2; self.reject(b)
        b = body(); b['photos'] = [b['photos'][0] | {'id': str(uuid4())} for _ in range(8)]
        validate(request(b), NOW); validate(request(body() | {'photos': []}), NOW)

    def test_finite_coordinate_accuracy_branches(self):
        for key, bad in [('latitude', [-90.1, 90.1, True, '28', None, float('nan'), float('inf')]),
                         ('longitude', [-180.1, 180.1, False, '77', None, float('-inf')]),
                         ('horizontal_accuracy_m', [-1, True, '6', None, float('nan'), float('inf')])]:
            for value in bad:
                b = body(); b['photos'][0][key] = value; self.reject(b)
        b = body(); b['photos'][0].update(latitude=-90, longitude=180, horizontal_accuracy_m=0)
        validate(request(b), NOW)

    def test_bytes_base64_json_duplicates_and_malformed_input(self):
        for raw in [None, 2, '', '{', '{"id":1,"id":2}', 'x'*16385, '\ud800']:
            with self.assertRaises(VerdictError): validate({'body': raw}, NOW)
        e = request(); e.update(isBase64Encoded=True, body=base64.b64encode(e['body'].encode()).decode())
        self.assertEqual(validate(e, NOW), validate(request(), NOW))
        for raw in ['!!', base64.b64encode(b'x'*16385).decode(), 'x'*21849]:
            with self.assertRaises(VerdictError): validate({'body': raw, 'isBase64Encoded': True}, NOW)
        b = body(); b['note'] = '界'*2000; b['photos'] = []; validate(request(b), NOW)
        e = request(); e['body'] += ' '*16384
        with self.assertRaises(VerdictError): validate(e, NOW)

    def test_body_hash_stable_and_sensitive_to_note(self):
        a, sha = validate(request(), NOW)
        e = request(); e['body'] = json.dumps(dict(reversed(list(body().items()))), indent=2)
        self.assertEqual(validate(e, NOW)[1], sha)
        self.assertNotEqual(validate(request(body() | {'note': 'Other'}), NOW)[1], sha)


class HandlerTests(unittest.TestCase):
    def setUp(self):
        self.conn = Mock(); self.s3 = Mock(); self.s3.generate_presigned_url.return_value = 'https://synthetic.invalid/put'
        self.photos = [body()['photos'][0] | {'object_key': f'verdicts/{VID}/{PID}.jpg'}]

    def call(self, e=None):
        with patch.dict(os.environ, {'DATA_BUCKET': 'synthetic'}):
            return handle(e or request(), lambda: self.conn, self.s3, NOW)

    def test_new_replay_presigning_and_no_auth(self):
        for status in [201, 200]:
            with patch('verdicts.handler.record', return_value=(status, self.photos)):
                r = self.call(); self.assertEqual(r['statusCode'], status)
                self.assertEqual(json.loads(r['body'])['photo_uploads'][0]['photo_id'], PID)
                self.s3.generate_presigned_url.assert_called_with('put_object',
                    Params={'Bucket': 'synthetic', 'Key': f'verdicts/{VID}/{PID}.jpg', 'ContentType': 'image/jpeg'},
                    ExpiresIn=900, HttpMethod='PUT')
                e = request(); e['headers']['Authorization'] = 'ignored'
                self.assertEqual(self.call(e), r)
        self.conn.commit.assert_called(); self.conn.close.assert_called()

    def test_known_errors_and_rollback(self):
        for status, code in [(409, 'idempotency_conflict'), (429, 'daily_cap_reached'), (404, 'not_found')]:
            with patch('verdicts.handler.record', side_effect=VerdictError(status, code, 'Synthetic')):
                r = self.call(); self.assertEqual(r['statusCode'], status)
                self.assertEqual(json.loads(r['body'])['error']['code'], code)
                self.conn.rollback.assert_called()
        self.conn.commit.assert_not_called()

    def test_db_and_signing_failure_retryable_and_private(self):
        for fail in ['db', 'sign']:
            self.conn.reset_mock()
            with patch('verdicts.handler.record', side_effect=RuntimeError('private note') if fail == 'db' else None,
                       return_value=(201, self.photos)):
                if fail == 'sign': self.s3.generate_presigned_url.side_effect = RuntimeError('private note')
                r = self.call(); self.assertEqual(r['statusCode'], 503)
                self.assertTrue(json.loads(r['body'])['error']['retryable']); self.assertNotIn('private note', r['body'])
                self.conn.rollback.assert_called_once(); self.conn.commit.assert_not_called()
        r = handle(request(), lambda: (_ for _ in ()).throw(RuntimeError('private')), now=NOW)
        self.assertEqual(r['statusCode'], 503)

    def test_bad_input_never_connects_and_log_privacy(self):
        factory = Mock()
        with self.assertLogs('verdicts.handler', level='INFO') as logs:
            handle({'body': 'bad'}, factory, now=NOW)
        factory.assert_not_called()
        with patch('verdicts.handler.record', return_value=(201, self.photos)), self.assertLogs('verdicts.handler', level='INFO') as logs:
            self.call()
        text = '\n'.join(logs.output)
        for private in [KILN, VID, PID, 'Synthetic note', '28.7', '77.7']: self.assertNotIn(private, text)
        data = json.loads(logs.records[0].getMessage()); self.assertEqual(set(data), {'photos', 'outcome', 'latency_ms'})


class OperatorTests(unittest.TestCase):
    def test_bootstrap_secret_only_and_transaction_failure(self):
        from unittest.mock import patch as mock_patch
        import types
        for failure in (None, 'secret', 'commit', 'exists'):
            conn = Mock(); cur = conn.cursor.return_value
            cur.fetchone.side_effect = [(1,)] if failure == 'exists' else [None, ('CREATE ROLE synthetic',)]
            secret = Mock()
            if failure == 'secret': secret.put_secret_value.side_effect = RuntimeError('private')
            if failure == 'commit': conn.commit.side_effect = RuntimeError('private')
            with mock_patch.object(bootstrap, 'connect_from_env', return_value=conn), \
                 mock_patch.dict(sys.modules, {'boto3': types.SimpleNamespace(client=lambda _: secret)}), \
                 mock_patch.dict(os.environ, {'VERDICTS_SECRET': 'synthetic'}), \
                 mock_patch('builtins.print') as output:
                if failure:
                    with self.assertRaises(SystemExit): bootstrap.main()
                    conn.rollback.assert_called_once()
                    if failure == 'exists': secret.put_secret_value.assert_not_called()
                else:
                    bootstrap.main(); conn.commit.assert_called_once()
                    stored = json.loads(secret.put_secret_value.call_args.kwargs['SecretString'])
                    self.assertEqual(stored['username'], 'kilnwatch_verdicts')
                    self.assertEqual(set(stored), {'username', 'password'})
                self.assertTrue(all('private' not in str(call) for call in output.call_args_list))
                conn.close.assert_called_once()

    def test_reset_cli_confirmation_and_history(self):
        from registry import cli
        conn = Mock(); conn.cursor.return_value.rowcount = 1
        with patch.object(sys, 'argv', ['cli', 'reset-verdict', '--kiln', KILN, '--confirm']), \
             patch.object(cli, 'connect_from_env', return_value=conn), patch('builtins.print'):
            cli.main(); conn.commit.assert_called_once(); conn.close.assert_called_once()
            sql = conn.cursor.return_value.execute.call_args.args[0]
            self.assertIn("status='flagged'", sql); self.assertNotIn('verdicts', sql)
        for argv in [['cli','reset-verdict','--kiln',KILN], ['cli','reset-verdict','--kiln','bad','--confirm']]:
            with patch.object(sys, 'argv', argv), patch.object(cli, 'connect_from_env') as factory, patch.object(cli.argparse.ArgumentParser, 'error', side_effect=SystemExit):
                with self.assertRaises(SystemExit): cli.main()
                factory.assert_not_called()


class PublicInspectionTests(unittest.TestCase):
    def test_allowlist_and_flagged_reset_null(self):
        r = serialize(records()[0]['payload'], 'confirmed')
        r['inspection'] = {'outcome': 'confirmed', 'recorded_at': '2026-10-11T09:00:00Z', 'note': 'private', 'photos': [], 'id': VID}
        self.assertNotIn('inspection', public_view(r))
        self.assertEqual(set(public_view(r, True)['inspection']), {'outcome', 'recorded_at'})
        r['status'] = 'flagged'; self.assertIsNone(public_view(r, True)['inspection'])

    def test_default_byte_for_byte_and_opt_in_all_shapes(self):
        repo = MemoryRegistry(); original = public_handle(event('/public/kilns', {'district': 'Hapur'}, False), repo.factory)
        self.assertNotIn('inspection', original['body'])
        class Inspected(MemoryRegistry):
            def public_list(self, district, cursor='', limit=100, include_inspected=False):
                if not include_inspected: return super().public_list(district, cursor, limit)
                return {'kilns': [r | {'inspection': None} for r in self.rows], 'next_cursor': None}
            def public_detail(self, kiln_id, include_inspected=False):
                r = super().public_detail(kiln_id)
                return r | {'inspection': None} if include_inspected else r
            def public_near(self, lat, lon, radius_m, include_inspected=False):
                return self.public_list('Hapur', include_inspected=include_inspected)
        repo = Inspected()
        self.assertEqual(public_handle(event('/public/kilns', {'district': 'Hapur'}, False), repo.factory), original)
        for path, query in [('/public/kilns', {'district': 'Hapur'}), ('/public/kilns', {'lat': '28.7', 'lon': '77.7'}),
                            ('/public/kilns/'+repo.rows[0]['kiln_id'], {})]:
            r = public_handle(event(path, query | {'include': 'inspected'}, False), repo.factory)
            self.assertEqual(r['statusCode'], 200); data = json.loads(r['body'])
            self.assertIsNone((data['kilns'][0] if 'kilns' in data else data)['inspection'])
            for value in ['bogus', '', 'Inspected']:
                self.assertEqual(public_handle(event(path, query | {'include': value}, False), repo.factory)['statusCode'], 400)


@unittest.skipUnless(os.getenv('KILNWATCH_TEST_DB_PORT'), 'Disposable local PostGIS unavailable')
class VerdictPostGISTests(unittest.TestCase):
    def connect(self):
        import pg8000.dbapi
        return pg8000.dbapi.connect(host='127.0.0.1', port=int(os.environ['KILNWATCH_TEST_DB_PORT']),
            database='kilnwatch_test', user='postgres', password=os.environ.get('KILNWATCH_TEST_DB_PASSWORD'), ssl_context=False)

    def setUp(self):
        self.conn = self.connect(); migrate(self.conn); migrate(self.conn)
        with closing(self.conn.cursor()) as c:
            c.execute('TRUNCATE kilnwatch.import_runs,kilnwatch.candidates,kilnwatch.verdict_days CASCADE')
        self.conn.commit(); persist(self.conn, records(), 'b'*64, 'a'*64)
        self.kiln = records()[0]['payload']['kiln_id']

    def tearDown(self): self.conn.rollback(); self.conn.close()

    def value(self, sql):
        with closing(self.conn.cursor()) as c: c.execute(sql); return c.fetchone()[0]

    def write(self, b=None):
        b = body() if b is None else b; b['kiln_id'] = self.kiln
        data, sha = validate(request(b), NOW)
        return record(self.conn, data, sha, NOW)

    def test_grants_and_rollback_reset(self):
        before = self.value("SELECT md5(string_agg(to_jsonb(c)::text,'' ORDER BY kiln_id)) FROM kilnwatch.candidates c")
        with closing(self.conn.cursor()) as c:
            c.execute('SET LOCAL ROLE kilnwatch_verdict_writer')
        self.assertEqual(self.write()[0], 201)
        self.assertEqual(self.value('SELECT status FROM kilnwatch.candidates'), 'confirmed')
        self.assertEqual(self.value('SELECT count FROM kilnwatch.verdict_days'), 1)
        reset_verdict(self.conn, self.kiln)
        self.assertEqual(self.value('SELECT status FROM kilnwatch.candidates'), 'flagged')
        self.assertEqual(self.value('SELECT count(*) FROM kilnwatch.verdicts'), 1)
        self.conn.rollback()
        self.assertEqual(self.value('SELECT count(*) FROM kilnwatch.verdicts'), 0)
        self.assertEqual(self.value('SELECT count(*) FROM kilnwatch.verdict_days'), 0)
        self.assertEqual(self.value("SELECT md5(string_agg(to_jsonb(c)::text,'' ORDER BY kiln_id)) FROM kilnwatch.candidates c"), before)
        for role, sql in [('kilnwatch_verdict_writer', "UPDATE kilnwatch.candidates SET assessment='{}'"),
                          ('kilnwatch_verdict_writer', 'DELETE FROM kilnwatch.verdicts'),
                          ('kilnwatch_reader', 'SELECT note FROM kilnwatch.verdicts'),
                          ('kilnwatch_reader', 'SELECT photos FROM kilnwatch.verdicts'),
                          ('kilnwatch_reader', 'SELECT verdict_id FROM kilnwatch.verdicts'),
                          ('kilnwatch_importer', "UPDATE kilnwatch.candidates SET status='closed'")]:
            with closing(self.conn.cursor()) as c:
                c.execute('SET LOCAL ROLE '+role)
                with self.assertRaises(Exception): c.execute(sql)
            self.conn.rollback()
        with closing(self.conn.cursor()) as c:
            c.execute('SET LOCAL ROLE kilnwatch_reader'); c.execute('SELECT kiln_id,outcome,recorded_at FROM kilnwatch.verdicts')

    def test_exact_migration_grants_and_no_login(self):
        with closing(self.conn.cursor()) as c:
            c.execute("SELECT rolcanlogin,rolsuper,rolcreatedb,rolcreaterole FROM pg_roles WHERE rolname='kilnwatch_verdict_writer'")
            self.assertEqual(tuple(c.fetchone()), (False, False, False, False))
            expected = {'candidates': {'SELECT'}, 'verdicts': {'SELECT', 'INSERT'},
                        'verdict_days': {'SELECT', 'INSERT', 'UPDATE'}, 'observations': set(),
                        'evidence': set(), 'import_runs': set(), 'run_observations': set()}
            for table, allowed in expected.items():
                for privilege in ('SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'):
                    c.execute('SELECT has_table_privilege(%s,%s,%s)', ('kilnwatch_verdict_writer','kilnwatch.'+table,privilege))
                    self.assertEqual(c.fetchone()[0], privilege in allowed, (table,privilege))
            c.execute("SELECT column_name FROM information_schema.column_privileges WHERE grantee='kilnwatch_verdict_writer' AND table_name='candidates' AND privilege_type='UPDATE'")
            self.assertEqual({r[0] for r in c.fetchall()}, {'status','review_state'})
            c.execute("SELECT column_name FROM information_schema.column_privileges WHERE grantee='kilnwatch_reader' AND table_name='verdicts' AND privilege_type='SELECT'")
            self.assertEqual({r[0] for r in c.fetchall()}, {'kiln_id','outcome','recorded_at'})

    def test_equal_time_latest_apply_and_reset_history_null(self):
        self.write()
        self.write(body() | {'id': str(uuid4()), 'outcome': 'closed'})
        self.assertEqual(Registry(self.conn).public_detail(self.kiln, True)['inspection']['outcome'], 'closed')
        reset_verdict(self.conn, self.kiln)
        self.assertIsNone(Registry(self.conn).public_detail(self.kiln, True)['inspection'])
        self.assertEqual(self.value('SELECT count(*) FROM kilnwatch.verdicts'), 2)

    def test_cap_30_replay_conflict_and_404_not_counted(self):
        for i in range(30):
            b = body() | {'id': str(uuid4())}; self.assertEqual(self.write(b)[0], 201)
        self.assertEqual(self.write(b)[0], 200)
        self.assertEqual(self.value('SELECT count FROM kilnwatch.verdict_days'), 30)
        with self.assertRaises(VerdictError) as e: self.write(body() | {'id': str(uuid4())})
        self.assertEqual(e.exception.status, 429)
        with self.assertRaises(VerdictError) as e: self.write(b | {'note': 'Different'})
        self.assertEqual(e.exception.status, 409)
        data, sha = validate(request(body()), NOW)
        with self.assertRaises(VerdictError) as e: record(self.conn, data, sha, NOW)
        self.assertEqual(e.exception.status, 404)
        self.assertEqual(self.value('SELECT count FROM kilnwatch.verdict_days'), 30)
        self.assertEqual(self.value('SELECT count(*) FROM kilnwatch.verdicts'), 30)

    def test_late_order_public_all_shapes_and_default(self):
        self.write(body() | {'outcome': 'compliant'})
        self.write(body() | {'id': str(uuid4()), 'recorded_at': '2026-10-11T08:00:00Z'})
        self.conn.commit()
        self.assertEqual(self.value('SELECT status FROM kilnwatch.candidates'), 'compliant')
        self.assertEqual(self.value('SELECT count(*) FROM kilnwatch.verdicts'), 2)
        with closing(self.conn.cursor()) as c: c.execute('SET LOCAL ROLE kilnwatch_reader')
        r = Registry(self.conn)
        self.assertEqual(r.public_list('Hapur')['kilns'], [])
        self.assertIsNone(r.public_detail(self.kiln))
        for result in [r.public_list('Hapur', include_inspected=True)['kilns'][0],
                       r.public_detail(self.kiln, True), r.public_near(28.7305, 77.7805, 100, include_inspected=True)['kilns'][0]]:
            self.assertEqual(result['inspection']['outcome'], 'compliant')
            self.assertEqual(result['inspection']['recorded_at'], '2026-10-11T09:00:00Z')
            self.assertNotIn('note', public_view(result, True)['inspection'])

    def test_concurrent_replay_counts_once_and_cap_atomic(self):
        errors = []; results = []
        def run(b):
            conn = self.connect()
            try:
                data, sha = validate(request(b), NOW)
                result = record(conn, data, sha, NOW); conn.commit(); results.append(result[0])
            except VerdictError as e: conn.rollback(); results.append(e.status)
            except Exception as e: conn.rollback(); errors.append(type(e).__name__)
            finally: conn.close()
        b = body() | {'kiln_id': self.kiln}
        ts = [threading.Thread(target=run, args=(b,)) for _ in range(5)]
        for t in ts: t.start()
        for t in ts: t.join(timeout=20); self.assertFalse(t.is_alive())
        self.assertEqual(errors, []); self.assertEqual(sorted(results), [200]*4+[201])
        self.assertEqual(self.value('SELECT count FROM kilnwatch.verdict_days'), 1)
        self.conn.rollback()
        results.clear()
        ts = [threading.Thread(target=run, args=(b | {'id': str(uuid4())},)) for _ in range(35)]
        for t in ts: t.start()
        for t in ts: t.join(timeout=20); self.assertFalse(t.is_alive())
        self.assertEqual(errors, []); self.assertEqual(results.count(201), 29); self.assertEqual(results.count(429), 6)
        self.assertEqual(self.value('SELECT count FROM kilnwatch.verdict_days'), 30)

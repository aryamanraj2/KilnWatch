"""P1 route planner: synthetic tests only. Amazon Location, DynamoDB and the public API are stubs; no network or AWS."""
import copy
import itertools
import json
import math
import re
import sys
import unittest
import unittest.mock
from datetime import datetime, timezone
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'assistant'))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'route'))
import planner
import route_handler
import tools

FIXTURE = json.loads((Path(__file__).resolve().parent / 'public_hapur.json').read_text())['kilns']
NOW = datetime(2026, 10, 10, 12, tzinfo=timezone.utc)
RULES = ['C-HAB-800', 'C-KILN-1K', 'UP-NH-300', 'UP-RAIL-200']
CONTRACT_KEYS = {'district', 'generated_at', 'route_id', 'depart', 'budget_min', 'stops', 'legs', 'kilns', 'notes'}
STOP_KEYS = {'order', 'kiln_id', 'eta', 'service_min', 'access', 'sheet'}
IST_STAMP = re.compile(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\+05:30$')


def assessed():
    """The tracked 39-record fixture with deterministic R1-shaped exposure and siting flags."""
    records = copy.deepcopy(FIXTURE)
    for n, r in enumerate(sorted(records, key=lambda k: k['kiln_id'])):
        r['exposure'] = {'people': 1000 + (n * 7919) % 20000, 'children_under_five': 1, 'adults_over_sixty': 1}
        r['violations'] = [{'rule_id': RULES[i], 'measured_distance_m': 100, 'threshold_m': 800, 'evidence_url': None}
                           for i in range(n % 4)]
    return records


def seconds(a, b):
    """Fake driving time: 2 minutes per straight-line kilometre, rounded like Location's integer seconds."""
    return round(math.dist((a[0] * 98, a[1] * 111), (b[0] * 98, b[1] * 111)) * 120)


class FakeGeo:
    def __init__(self, matrix_fail=False, routes_fail=False, points_per_leg=5):
        self.matrix_fail, self.routes_fail, self.points, self.calls = matrix_fail, routes_fail, points_per_leg, []

    def calculate_route_matrix(self, **kw):
        self.calls.append(('matrix', kw))
        if self.matrix_fail: raise RuntimeError('AccessDeniedException: secret provider text')
        assert kw['TravelMode'] == 'Car' and kw['RoutingBoundary'] == {'Unbounded': True}
        assert len(kw['Origins']) <= 15 and len(kw['Origins']) * len(kw['Destinations']) <= 100
        return {'RouteMatrix': [[{'Duration': seconds(o['Position'], d['Position']), 'Distance': 1}
                                 for d in kw['Destinations']] for o in kw['Origins']], 'ErrorCount': 0}

    def calculate_routes(self, **kw):
        self.calls.append(('routes', kw))
        if self.routes_fail: raise RuntimeError('ValidationException: secret provider text')
        seq = [kw['Origin']] + [w['Position'] for w in kw['Waypoints']] + [kw['Destination']]
        legs = []
        for a, b in zip(seq, seq[1:]):
            line = [[a[0] + (b[0] - a[0]) * t / (self.points - 1), a[1] + (b[1] - a[1]) * t / (self.points - 1)] for t in range(self.points)]
            legs.append({'Geometry': {'LineString': line},
                         'VehicleLegDetails': {'Summary': {'Overview': {'Distance': 1000, 'Duration': seconds(a, b)}}}})
        return {'Routes': [{'Legs': legs}]}


class FakeAPI:
    def __init__(self, records=None, fail=False):
        self.records, self.fail = sorted(records if records is not None else assessed(), key=lambda k: k['kiln_id']), fail

    def get(self, path, query):
        if self.fail: raise tools.UpstreamUnavailable(503)
        assert path == '/public/kilns' and query['limit'] == 200
        return {'kilns': [k for k in self.records if k['district'] == query['district']], 'next_cursor': None}


class FakeDynamo:
    def __init__(self, count=0, fail=False):
        self.count, self.fail, self.keys = count, fail, []

    def update_item(self, TableName, Key, UpdateExpression, ConditionExpression, ExpressionAttributeValues):
        if self.fail: raise RuntimeError('ResourceNotFoundException: secret provider text')
        self.keys.append(Key['day']['S'])
        if self.count >= int(ExpressionAttributeValues[':cap']['N']):
            error = RuntimeError('x'); error.response = {'Error': {'Code': 'ConditionalCheckFailedException'}}
            raise error
        self.count += 1


class Context:
    aws_request_id = 'req-1'


def request(**overrides):
    return {'district': 'Hapur', 'start': None, 'depart': planner.default_depart(NOW), 'budget_min': 480,
            'max_stops': 8, 'priority': 'people', 'kiln_ids': None, **overrides}


def make_plan(geo=None, records=None, metrics=None, **overrides):
    req = request(**overrides)
    candidates, left_out = planner.select(req, records if records is not None else assessed())
    return planner.plan(req, candidates, left_out, geo or FakeGeo(), NOW, {} if metrics is None else metrics)


POINTS = [(0, 0), (1, 7), (0, 6), (6, 9), (0, 7), (4, 3)]   # nearest neighbour crosses itself here


class SolverTests(unittest.TestCase):
    D = [[round(math.dist(a, b) * 100) for b in POINTS] for a in POINTS]

    def test_two_opt_removes_a_crossing(self):
        left, nn, at = [1, 2, 3, 4, 5], [], 0
        while left:
            at = min(left, key=lambda j: (self.D[at][j], j)); nn.append(at); left.remove(at)
        best = planner.order(self.D, [1, 2, 3, 4, 5])
        self.assertEqual((nn, planner.path_cost(self.D, nn)), ([5, 1, 4, 2, 3], 1871))
        self.assertEqual((best, planner.path_cost(self.D, best)), ([5, 2, 4, 1, 3], 1739))
        optimum = min(planner.path_cost(self.D, list(p)) for p in itertools.permutations([1, 2, 3, 4, 5]))
        self.assertEqual(planner.path_cost(self.D, best), optimum)

    def test_deterministic(self):
        runs = {tuple(planner.order(self.D, nodes)) for nodes in ([1, 2, 3, 4, 5], [5, 4, 3, 2, 1], [3, 1, 5, 2, 4])}
        self.assertEqual(len(runs), 1)

    def test_budget_and_max_stops(self):
        ranked = [3, 1, 2, 5, 4]
        self.assertEqual(sorted(planner.fit(self.D, ranked, 2, 10 ** 6)), [1, 3])
        for budget in (35 * 60 + 300, 2 * 35 * 60 + 1000, 10 ** 6):
            path = planner.fit(self.D, ranked, 5, budget)
            self.assertLessEqual(planner.path_cost(self.D, path) + 35 * 60 * len(path), budget)
            self.assertEqual(sorted(path), sorted(ranked[:len(path)]))   # lowest priority dropped first
        self.assertEqual(planner.fit(self.D, ranked, 5, 60), [])

    def test_single_stop(self):
        self.assertEqual(planner.order(self.D, [4]), [4])
        self.assertEqual(planner.fit(self.D, [4], 1, 10 ** 6), [4])


class PlannerTests(unittest.TestCase):
    def test_people_and_flags_selection(self):
        records = assessed()
        by_people = planner.select(request(), records)[0]
        self.assertEqual([k['exposure']['people'] for k in by_people],
                         sorted((k['exposure']['people'] for k in records), reverse=True)[:8])
        by_flags = planner.select(request(priority='flags'), records)[0]
        flags = [len(k['violations']) for k in by_flags]
        self.assertEqual(flags, sorted(flags, reverse=True)); self.assertEqual(flags[0], 3)
        top = [k for k in by_flags if len(k['violations']) == 3]
        self.assertEqual([k['exposure']['people'] for k in top], sorted((k['exposure']['people'] for k in top), reverse=True))

    def test_null_exposure_never_ranked_as_zero(self):
        records = assessed()
        for r in records[:5]: r['exposure'] = None
        records[5]['exposure'] = {'people': 0, 'children_under_five': 0, 'adults_over_sixty': 0}
        for priority in ('people', 'flags'):
            chosen, left_out = planner.select(request(priority=priority, max_stops=8), records)
            self.assertFalse({k['kiln_id'] for k in records[:5]} & {k['kiln_id'] for k in chosen})
            self.assertEqual(left_out['no_exposure'], 5)
        body = make_plan(records=records)
        self.assertIn('5 kilns without an exposure estimate were left out, because the inspection sheet needs a people count.', body['notes'])
        only_null = [dict(r, exposure=None) for r in records[:3]]
        with self.assertRaises(planner.NoKilns):
            planner.select(request(), only_null)

    def test_contract_shape(self):
        geo, metrics = FakeGeo(), {}
        body = make_plan(geo, metrics=metrics)
        self.assertEqual(set(body), CONTRACT_KEYS)
        self.assertEqual(len(body['stops']), 8)
        for stop in body['stops']:
            self.assertEqual(set(stop), STOP_KEYS)
            self.assertEqual(set(stop['sheet']), {'rules_flagged', 'people_exposed', 'on_site_checks'})
            self.assertIsInstance(stop['sheet']['people_exposed'], int)
            self.assertEqual(stop['access']['note'], planner.ACCESS_NOTE)
            self.assertEqual(stop['sheet']['on_site_checks'][-2:], planner.ALWAYS)
        self.assertEqual([s['order'] for s in body['stops']], list(range(1, 9)))
        self.assertEqual([s['kiln_id'] for s in body['stops']], [k['kiln_id'] for k in body['kilns']])
        self.assertEqual(len(body['legs']), len(body['stops']))
        self.assertEqual([l['to_kiln_id'] for l in body['legs']], [s['kiln_id'] for s in body['stops']])
        for leg in body['legs']:
            coords = leg['geometry']['coordinates']
            self.assertEqual(leg['geometry']['type'], 'LineString'); self.assertGreaterEqual(len(coords), 2)
            for lon, lat in coords:
                self.assertTrue(77 < lon < 78.5 and 28 < lat < 29.5)   # [lon, lat] for Hapur, never swapped
        etas = [datetime.fromisoformat(s['eta']) for s in body['stops']]
        self.assertTrue(all(IST_STAMP.match(s['eta']) for s in body['stops']))
        self.assertEqual(etas, sorted(etas)); self.assertEqual(len(set(etas)), len(etas))
        self.assertGreater(etas[0], datetime.fromisoformat(body['depart']))
        self.assertTrue(IST_STAMP.match(body['depart'])); self.assertEqual(body['depart'], '2026-10-11T09:00:00+05:30')
        self.assertTrue(body['generated_at'].endswith('Z'))
        self.assertRegex(body['route_id'], r'^plan-2026-10-11-hapur-[0-9a-f]{8}$')
        self.assertIn(planner.DEFAULT_START, body['notes'])
        self.assertEqual([c[0] for c in geo.calls], ['matrix', 'routes'])
        self.assertEqual((len(geo.calls[0][1]['Origins']), len(geo.calls[0][1]['Destinations'])), (9, 8))
        self.assertEqual(metrics['matrix_cells'], 72)
        words = json.dumps([body['notes'], [s['sheet']['on_site_checks'] for s in body['stops']], planner.ACCESS_NOTE])
        self.assertNotRegex(words, re.compile(r'(?i)\b(?:illegal|unlawful|violat)'))   # user-facing text; `violations` is a record key

    def test_eta_matches_legs_and_budget(self):
        body = make_plan(budget_min=240)
        depart, total = datetime.fromisoformat(body['depart']), 0
        for stop, leg in zip(body['stops'], body['legs']):
            total += leg['duration_s']
            self.assertAlmostEqual((datetime.fromisoformat(stop['eta']) - depart).total_seconds(), total, delta=30)
            total += 35 * 60
        self.assertLessEqual(total, 240 * 60 + 30 * len(body['stops']))
        self.assertTrue(any('budget' in n for n in body['notes']))

    def test_routes_failure_drops_legs_only(self):
        body = make_plan(FakeGeo(routes_fail=True))
        self.assertNotIn('legs', body); self.assertEqual(len(body['stops']), 8)
        self.assertIn('Road legs are unavailable for this plan; ETAs use the matrix travel times.', body['notes'])

    def test_matrix_failure(self):
        with self.assertRaises(planner.RoutingUnavailable):
            make_plan(FakeGeo(matrix_fail=True))

    def test_deterministic_and_start(self):
        a, b = make_plan(), make_plan()
        self.assertEqual(a, b)
        c = make_plan(start={'lat': 28.7306, 'lon': 77.7759}, max_stops=5)
        self.assertNotIn(planner.DEFAULT_START, c['notes']); self.assertEqual(len(c['stops']), 5)
        self.assertNotEqual(a['route_id'], c['route_id'])

    def test_kiln_ids(self):
        records = assessed()
        wanted = [records[3]['kiln_id'], records[9]['kiln_id'], 'KW-' + 'f' * 32]
        body = make_plan(records=records, kiln_ids=sorted(wanted))
        self.assertEqual(sorted(s['kiln_id'] for s in body['stops']), sorted(wanted[:2]))
        self.assertIn('1 requested kiln IDs were not found among the flagged kilns of Hapur.', body['notes'])
        with self.assertRaises(planner.NoKilns):
            planner.select(request(kiln_ids=['KW-' + 'f' * 32]), records)

    def test_geometry_simplified(self):
        body = make_plan(FakeGeo(points_per_leg=1000), max_stops=2)
        for leg in body['legs']:
            self.assertLessEqual(len(leg['geometry']['coordinates']), planner.MAX_LEG_POINTS + 1)

    def test_on_site_checks(self):
        kiln = {'violations': [{'rule_id': 'C-HAB-800'}, {'rule_id': 'UP-SCH-1K'}], 'exposure': {'people': 5},
                'rule_checks': [{'rule_id': 'UP-SCH-1K', 'check': 'Distance to a school'}]}
        self.assertEqual(planner.sheet(kiln), {'rules_flagged': ['C-HAB-800', 'UP-SCH-1K'], 'people_exposed': 5,
                                               'on_site_checks': ['Distance to the nearest home', 'Distance to a school'] + planner.ALWAYS})


class HandlerTests(unittest.TestCase):
    def setUp(self):
        patcher = unittest.mock.patch.dict('os.environ', {'COUNTER_TABLE': 'counter', 'DAILY_CAP': '15'})
        patcher.start(); self.addCleanup(patcher.stop)

    def call(self, body, raw=False, dynamo=None, geo=None, api=None, path='/routes/plan', method='POST'):
        dynamo, geo = dynamo or FakeDynamo(), geo or FakeGeo()
        event = {'rawPath': path, 'requestContext': {'http': {'method': method}}, 'body': body if raw else json.dumps(body)}
        with self.assertLogs('kilnwatch.route', 'INFO') as logs:
            result = route_handler.handle(event, Context(), dynamodb=dynamo, geo=lambda: geo, api=api or FakeAPI(), now=NOW)
        line = json.loads(logs.records[-1].getMessage())
        self.assertEqual(line['status'], result['statusCode'])
        self.assertLessEqual(set(line), {'event', 'request_id', 'status', 'stops', 'legs', 'matrix_cells', 'location_ms', 'total_ms'})
        return result, json.loads(result['body']), dynamo, geo

    def test_bad_bodies(self):
        kid = FIXTURE[0]['kiln_id']
        bad = ['', 'not json', '[1]', json.dumps({}), json.dumps({'district': 'Hapur', 'extra': 1}),
               json.dumps({'district': 'Hap;ur'}), json.dumps({'district': 5}),
               json.dumps({'district': 'Hapur', 'start': {'lat': 28.7}}), json.dumps({'district': 'Hapur', 'start': [28.7, 77.7]}),
               json.dumps({'district': 'Hapur', 'start': {'lat': 91, 'lon': 77}}), '{"district": "Hapur", "start": {"lat": NaN, "lon": 77}}',
               json.dumps({'district': 'Hapur', 'depart': '2026-10-11 09:00'}), json.dumps({'district': 'Hapur', 'depart': '2026-10-11T09:00:00'}),
               json.dumps({'district': 'Hapur', 'depart': 'tomorrow'}), json.dumps({'district': 'Hapur', 'budget_min': 59}),
               json.dumps({'district': 'Hapur', 'budget_min': 721}), json.dumps({'district': 'Hapur', 'max_stops': 9}),
               json.dumps({'district': 'Hapur', 'max_stops': 0}), json.dumps({'district': 'Hapur', 'max_stops': True}),
               json.dumps({'district': 'Hapur', 'priority': 'schools'}), json.dumps({'district': 'Hapur', 'kiln_ids': []}),
               json.dumps({'district': 'Hapur', 'kiln_ids': [kid] * 2}), json.dumps({'district': 'Hapur', 'kiln_ids': ['KW-6b3b']}),
               json.dumps({'district': 'Hapur', 'kiln_ids': ['KW-' + f'{n:032x}' for n in range(9)]}),
               '{"district": "Hapur"' + ' ' * 4096 + '}']
        for body in bad:
            with self.subTest(body=body[:60]):
                result, body_, dynamo, geo = self.call(body, raw=True)
                self.assertEqual((result['statusCode'], body_['error']['code']), (400, 'invalid_request'))
                self.assertEqual((dynamo.keys, geo.calls), ([], []))

    def test_4kb_limit_boundary(self):
        body = '{"district": "Hapur"}'
        ok = body[:-1] + ' ' * (4096 - len(body)) + '}'
        self.assertEqual(len(ok.encode()), 4096)
        self.assertEqual(self.call(ok, raw=True)[0]['statusCode'], 200)
        self.assertEqual(self.call(ok[:-1] + ' }', raw=True)[0]['statusCode'], 400)

    def test_ok_counts_once(self):
        result, body, dynamo, geo = self.call({'district': 'Hapur', 'priority': 'flags', 'max_stops': 5,
                                               'depart': '2026-10-12T08:30:00Z', 'budget_min': 300})
        self.assertEqual(result['statusCode'], 200)
        self.assertEqual(result['headers'], {'content-type': 'application/json', 'cache-control': 'no-store'})
        self.assertEqual(dynamo.keys, ['route#2026-10-10'])
        self.assertEqual(body['depart'], '2026-10-12T14:00:00+05:30')
        self.assertLessEqual(len(body['stops']), 5)

    def test_cap(self):
        result, body, _, geo = self.call({'district': 'Hapur'}, dynamo=FakeDynamo(count=15))
        self.assertEqual((result['statusCode'], body['error']['code'], body['error']['retryable']), (429, 'daily_cap_reached', False))
        self.assertEqual(geo.calls, [])

    def test_no_kilns_is_404_and_not_counted(self):
        for body in ({'district': 'Meerut'}, {'district': 'Hapur', 'kiln_ids': ['KW-' + 'f' * 32]}):
            result, out, dynamo, geo = self.call(body)
            self.assertEqual((result['statusCode'], out['error']['code']), (404, 'no_kilns'))
            self.assertEqual((dynamo.keys, geo.calls), ([], []))

    def test_503_mapping_without_provider_text(self):
        cases = [({'api': FakeAPI(fail=True)}, 'upstream_unavailable'),
                 ({'geo': FakeGeo(matrix_fail=True)}, 'routing_unavailable'),
                 ({'dynamo': FakeDynamo(fail=True)}, 'routing_unavailable')]
        for kwargs, code in cases:
            with self.subTest(code=code, kwargs=list(kwargs)):
                result, body, _, geo = self.call({'district': 'Hapur'}, **kwargs)
                self.assertEqual((result['statusCode'], body['error']['code'], body['error']['retryable']), (503, code, True))
                self.assertNotIn('secret', result['body']); self.assertNotIn('Exception', result['body'])
        self.assertEqual(self.call({'district': 'Hapur'}, dynamo=FakeDynamo(fail=True))[3].calls, [])

    def test_wrong_route(self):
        self.assertEqual(self.call({'district': 'Hapur'}, path='/ask')[0]['statusCode'], 404)
        self.assertEqual(self.call({'district': 'Hapur'}, method='GET')[0]['statusCode'], 404)

    def test_logs_hold_no_ids_or_coordinates(self):
        event = {'rawPath': '/routes/plan', 'requestContext': {'http': {'method': 'POST'}},
                 'body': json.dumps({'district': 'Hapur', 'start': {'lat': 28.7306, 'lon': 77.7759}})}
        with self.assertLogs('kilnwatch.route', 'INFO') as logs:
            route_handler.handle(event, Context(), dynamodb=FakeDynamo(), geo=FakeGeo, api=FakeAPI(), now=NOW)
        text = '\n'.join(r.getMessage() for r in logs.records)
        self.assertNotIn('KW-', text); self.assertNotIn('28.73', text); self.assertNotIn('Hapur', text)
        line = json.loads(logs.records[-1].getMessage())
        self.assertEqual((line['stops'], line['matrix_cells'], line['legs']), (8, 72, True))


if __name__ == '__main__':
    unittest.main()

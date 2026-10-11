"""Change triage (prompt 40): the deterministic diff and the agent step. Bedrock, DynamoDB, S3 and the public API
are stubs; no network or AWS. triage_sample.json holds recorded real shapes from the prompt 38 runs, trimmed."""
import copy
import io
import json
import sys
import unittest
import unittest.mock
from datetime import datetime, timezone
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'assistant'))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import handler
from triage import agent, diff

SAMPLE = json.loads((Path(__file__).resolve().parent / 'triage_sample.json').read_text())
NOW = datetime(2026, 10, 11, 12, tzinfo=timezone.utc)
THEN = {'id': 'S2A_T43RGM_20231205T053206_L2A', 'date': '2023-12-05'}
TODAY = {'id': 'S2B_T43RGM_20261005T053641_L2A', 'date': '2026-10-05'}
KW = 'KW-' + 'a' * 32


def ring(lon, lat, size=0.001):
    return [(lon, lat), (lon + size, lat), (lon + size, lat + size), (lon, lat + size)]


def feature(lon, lat, type_='FCBK', score=0.8, size=0.001):
    closed = ring(lon, lat, size) + [(lon, lat)]
    return {'type': 'Feature', 'geometry': {'type': 'Polygon', 'coordinates': [[list(p) for p in closed]]},
            'properties': {'type': type_, 'detection_confidence': score}}


def record(lon, lat, kiln_id=KW, type_='FCBK', score=0.8, size=0.001, evidence=None):
    return {'kiln_id': kiln_id, 'type': type_, 'detection_confidence': score, 'evidence': evidence or {'before': None, 'after': None},
            'footprint': {'polygon': [{'latitude': y, 'longitude': x} for x, y in ring(lon, lat, size)]}}


def kid(n): return 'KW-' + f'{n:032x}'


def triage(baseline=(), registry=(), current=None):
    """current defaults to the registry's own shapes and scores."""
    kilns = [diff.from_record(r) for r in registry]
    now = kilns if current is None else [diff.from_feature(f) for f in current]
    return diff.triage([diff.from_feature(f) for f in baseline], kilns, now, THEN, TODAY, 'm0-before')


class GeometryTests(unittest.TestCase):
    def test_iou(self):
        a = diff.from_feature(feature(77.7, 28.7))
        self.assertAlmostEqual(diff.iou(a, a), 1.0, places=6)
        half = diff.from_feature(feature(77.7005, 28.7))
        self.assertAlmostEqual(diff.iou(a, half), 1 / 3, places=2)
        self.assertEqual(diff.iou(a, diff.from_feature(feature(77.71, 28.7))), 0.0)

    def test_centroid_fallback_and_one_to_one(self):
        small = diff.from_record(record(77.7, 28.7, size=0.0001))
        shifted = diff.from_feature(feature(77.70015, 28.7, size=0.0001))  # about 15 m east, no overlap
        self.assertEqual(diff.match([small], [shifted]), {0: (0, 0.0)})
        twins = [diff.from_record(record(77.7, 28.7, kid(1))), diff.from_record(record(77.70001, 28.7, kid(2)))]
        self.assertEqual(len(diff.match(twins, [diff.from_feature(feature(77.7, 28.7))])), 1)


class DiffTests(unittest.TestCase):
    def test_each_group(self):
        items, summary = triage(
            baseline=[feature(77.70, 28.7), feature(77.72, 28.7, 'CFCBK'), feature(77.74, 28.7), feature(77.76, 28.7)],
            registry=[record(77.70, 28.7, kid(1)), record(77.72, 28.7, kid(2), 'Zigzag'),
                      record(77.74, 28.7, kid(3), score=0.42), record(77.80, 28.7, kid(4))])
        groups = {f['group']: f for f in items}
        self.assertEqual(summary['counts'], {'new_candidate': 1, 'no_longer_detected': 1,
                                             'possible_zigzag_conversion': 1, 'low_confidence': 1})
        self.assertEqual(groups['new_candidate']['kiln_id'], kid(4))
        self.assertEqual(groups['new_candidate']['group_words'], 'in the registry; not detected in the Dec 2023 scene')
        self.assertIsNone(groups['no_longer_detected']['kiln_id'])
        self.assertIsNone(groups['no_longer_detected']['current'])
        self.assertIn('no longer detected in the Oct 2026 scene', groups['no_longer_detected']['group_words'])
        self.assertEqual(groups['possible_zigzag_conversion']['baseline']['type'], 'CFCBK')
        self.assertEqual(groups['low_confidence']['current']['score'], 0.42)
        self.assertEqual(groups['low_confidence']['iou'], 1.0)
        self.assertEqual(groups['new_candidate']['iou'], 'none')
        self.assertEqual(groups['new_candidate']['evidence']['images'], 'no published image')
        self.assertEqual(groups['new_candidate']['evidence']['scene_ids'], [THEN['id'], TODAY['id']])

    def test_precedence(self):
        # A zigzag conversion with a low score stays a conversion; a new candidate with a low score stays new.
        items, summary = triage(baseline=[feature(77.70, 28.7, 'FCBK')],
                                registry=[record(77.70, 28.7, kid(1), 'Zigzag', 0.3), record(77.80, 28.7, kid(2), score=0.3)])
        self.assertEqual({f['kiln_id']: f['group'] for f in items},
                         {kid(1): 'possible_zigzag_conversion', kid(2): 'new_candidate'})

    def test_unchanged_match_and_empty_inputs(self):
        self.assertEqual(triage(baseline=[feature(77.70, 28.7)], registry=[record(77.70, 28.7)])[0], [])
        items, summary = triage()
        self.assertEqual(items, [])
        self.assertEqual(set(summary['counts'].values()), {0})

    def test_item_id_is_stable(self):
        first = triage(registry=[record(77.80, 28.7)])[0][0]['item_id']
        self.assertEqual(first, triage(registry=[record(77.80, 28.7)])[0][0]['item_id'])
        turned = record(77.80, 28.7)
        turned['footprint']['polygon'] = turned['footprint']['polygon'][2:] + turned['footprint']['polygon'][:2]
        self.assertEqual(first, triage(registry=[turned])[0][0]['item_id'])
        other_group = triage(baseline=[feature(77.80, 28.7)], registry=[record(77.80, 28.7, score=0.3)])[0][0]
        self.assertEqual(other_group['group'], 'low_confidence')
        self.assertNotEqual(first, other_group['item_id'])
        moved = triage(registry=[record(77.81, 28.7)])[0][0]['item_id']
        self.assertNotEqual(first, moved)

    def test_score_comes_from_the_current_run(self):
        items, summary = triage(baseline=[feature(77.70, 28.7)], registry=[record(77.70, 28.7, score=0.9)],
                                current=[feature(77.70, 28.7, score=0.45)])
        self.assertEqual([(f['group'], f['current']['score']) for f in items], [('low_confidence', 0.45)])
        self.assertEqual(summary['near_low_score'], 1)

    def test_recorded_sample(self):
        items, summary = diff.triage([diff.from_feature(f) for f in SAMPLE['baseline']['features']],
                                     [diff.from_record(r) for r in SAMPLE['registry']['kilns']],
                                     [diff.from_feature(f) for f in SAMPLE['current']['features']],
                                     diff.scene_of(SAMPLE['baseline']), diff.scene_of(SAMPLE['current']), 'm0-before')
        self.assertEqual(summary['counts'], {'new_candidate': 2, 'no_longer_detected': 2,
                                             'possible_zigzag_conversion': 0, 'low_confidence': 1})
        self.assertEqual(summary['matched'], 3)
        self.assertEqual([f['item_id'] for f in items], sorted(f['item_id'] for f in items))
        published = [f for f in items if 'before' in f['evidence']]
        self.assertTrue(all(f['evidence']['before'].startswith('https://') for f in published))


class AWSError(Exception):
    def __init__(self, code):
        super().__init__(f'{code}: provider text')
        self.response = {'Error': {'Code': code, 'Message': 'provider text'}}


class StubDynamo:
    """Only put_item exists: any other call fails the test."""
    def __init__(self):
        self.items, self.calls = {}, []

    def put_item(self, TableName, Item, ConditionExpression):
        assert TableName == 'review' and ConditionExpression == 'attribute_not_exists(item_id)'
        # botocore rejects anything but a string under 'S' before sending (the first live run hit this).
        assert all(set(v) == {'S'} and isinstance(v['S'], str) for v in Item.values()), Item
        self.calls.append(Item)
        if Item['item_id']['S'] in self.items: raise AWSError('ConditionalCheckFailedException')
        self.items[Item['item_id']['S']] = copy.deepcopy(Item)


class StubS3:
    def __init__(self, runs):
        self.runs, self.keys = runs, []

    def get_object(self, Bucket, Key):
        assert Bucket == 'data' and Key.startswith('detections/')
        self.keys.append(Key)
        return {'Body': io.BytesIO(json.dumps(self.runs[Key.split('/')[1]]).encode())}


class StubAPI:
    def __init__(self, kilns):
        self.kilns, self.queries = kilns, []

    def get(self, path, query):
        assert path == '/public/kilns' and query['include'] == 'inspected'
        self.queries.append(query)
        return {'kilns': self.kilns, 'next_cursor': None}


class StubBedrock:
    def __init__(self, text=None, fail=False):
        self.text, self.fail, self.calls = text, fail, []

    def converse(self, **kwargs):
        self.calls.append(copy.deepcopy(kwargs))
        if self.fail: raise AWSError('ThrottlingException')
        facts = json.loads(kwargs['messages'][0]['content'][0]['text'])
        text = self.text if self.text is not None else (
            f"{facts['kiln_id'] or 'This candidate'} is {facts['group_words']}; candidate for review.")
        return {'stopReason': 'end_turn', 'usage': {'inputTokens': 300, 'outputTokens': 30},
                'output': {'message': {'role': 'assistant', 'content': [{'text': text}]}}}


class Context:
    def __init__(self, remaining=(28_000,)):
        self.remaining = list(remaining)

    def get_remaining_time_in_millis(self):
        return self.remaining.pop(0) if len(self.remaining) > 1 else self.remaining[0]


EVENT = {'action': 'triage', 'baseline_run': 'm0-before', 'current': 'registry'}


def go(event=EVENT, bedrock=None, dynamo=None, sample=SAMPLE, context=None):
    dynamo = dynamo or StubDynamo()
    s3 = StubS3({'m0-before': sample['baseline'], 'm0-after': sample['current']})
    result = agent.run(event, context or Context(), dynamodb=dynamo, s3=s3, bedrock=bedrock or StubBedrock(),
                       api=StubAPI(sample['registry']['kilns']), model_id='global.amazon.nova-2-lite-v1:0',
                       table='review', bucket='data', now=NOW)
    return result, dynamo, s3


def many_new(n):
    """n registry kilns and no baseline: n new candidates."""
    kilns = [record(77.70 + 0.01 * i, 28.7, kid(i)) for i in range(n)]
    return {'baseline': {'kilnwatch': {'scenes': [THEN]}, 'features': []},
            'current': {'kilnwatch': {'scenes': [TODAY]}, 'features': []}, 'registry': {'kilns': kilns}}


class GateTests(unittest.TestCase):
    def setUp(self):
        patcher = unittest.mock.patch.dict('os.environ', {'COUNTER_TABLE': 'counter', 'DAILY_CAP': '300'})
        patcher.start(); self.addCleanup(patcher.stop)

    def test_only_a_direct_invoke_reaches_triage(self):
        seen = []
        triage_stub = lambda event, context: seen.append(event) or {'ok': True}
        self.assertEqual(handler.handle(dict(EVENT), None, dynamodb=None, ask=None, triage=triage_stub), {'ok': True})
        api_event = {'rawPath': '/ask', 'requestContext': {'http': {'method': 'POST'}}, 'body': json.dumps(EVENT)}
        dynamo = unittest.mock.Mock()
        result = handler.handle(api_event, None, dynamodb=dynamo, ask=None, triage=triage_stub)
        self.assertEqual(result['statusCode'], 400)
        self.assertEqual(len(seen), 1)
        dynamo.update_item.assert_not_called()  # rejected before the Ask counter, as today
        # Feature off (no REVIEW_TABLE): a direct triage event is just an unknown request.
        self.assertEqual(handler.handle(dict(EVENT), None, dynamodb=None, ask=None)['statusCode'], 404)

    def test_event_validation(self):
        for bad in ({**EVENT, 'status': 'closed'}, {**EVENT, 'baseline_run': '../x'}, {**EVENT, 'current': 'm0-after'},
                    {**EVENT, 'start_after': 'KW-1'}, {**EVENT, 'max_model_calls': 81}, {**EVENT, 'max_model_calls': True}):
            result, dynamo, s3 = go(bad)
            self.assertEqual(result['error'], 'invalid_event')
            self.assertEqual((dynamo.calls, s3.keys), ([], []))


class AgentTests(unittest.TestCase):
    def test_single_write_path(self):
        bedrock = StubBedrock()
        result, dynamo, s3 = go(bedrock=bedrock)
        self.assertTrue(result['ok'])
        self.assertEqual((result['items'], result['written'], result['model'], result['template']), (5, 5, 5, 0))
        self.assertEqual(s3.keys, ['detections/m0-before/kilns.geojson', 'detections/m0-after/kilns.geojson'])
        self.assertEqual(len(bedrock.calls), 5)
        for item in dynamo.items.values():
            self.assertEqual(item['state']['S'], 'pending')
            self.assertEqual(item['reason_source']['S'], 'model')
            self.assertEqual(item['model_id']['S'], 'global.amazon.nova-2-lite-v1:0')
            self.assertNotIn('status', item)
            self.assertNotIn('review_state', item)
            self.assertEqual(item['current']['S'], 'registry')
            self.assertIsNone(agent.check(item['reason']['S'], json.loads(item['facts']['S'])))
        call = bedrock.calls[0]
        self.assertEqual(call['additionalModelRequestFields'], {'reasoningConfig': {'type': 'disabled'}})
        self.assertNotIn('https://', json.dumps(call['messages']))
        self.assertNotIn('toolConfig', call)

    def test_idempotent(self):
        first, dynamo, _ = go()
        before = copy.deepcopy(dynamo.items)
        second, dynamo, _ = go(dynamo=dynamo)
        self.assertEqual((second['written'], second['existing']), (0, 5))
        self.assertEqual(dynamo.items, before)

    def test_validator_rejections(self):
        facts = {'kiln_id': KW, 'baseline_scene': THEN, 'current_scene': TODAY}
        self.assertIsNone(agent.check(f'{KW} was not detected in the Dec 2023 scene {THEN["id"]}; candidate for review.', facts))
        for text in (f'{KW} and KW-{"b" * 32} need review.', 'KW-aaaa is new.', 'Seen in S2A_T43RGM_20991205T053206_L2A.',
                     'This kiln is illegal.', 'A violation candidate.', 'This is a finding.', 'The kiln is confirmed.',
                     'The kiln looks closed.', 'Approved for removal.', 'It is not a kiln.', 'It was built after 2023.',
                     'It was demolished.', 'Construction started in 2024.', '', 'word ' * 61):
            self.assertIsNotNone(agent.check(text, facts), text)
        self.assertIsNotNone(agent.check(f'{KW} is low.', {**facts, 'kiln_id': None}))

    def test_template_fallback_after_one_regeneration(self):
        bedrock = StubBedrock(text='This kiln was built after 2023.')
        result, dynamo, _ = go(bedrock=bedrock)
        self.assertEqual((result['template'], result['regenerated'], result['model_calls']), (5, 5, 10))
        retry = bedrock.calls[-1]['messages']
        self.assertEqual([m['role'] for m in retry], ['user', 'assistant', 'user'])
        for item in dynamo.items.values():
            self.assertEqual((item['reason_source']['S'], item['model_id']['S']), ('template', 'none'))
            self.assertIsNone(agent.check(item['reason']['S'], json.loads(item['facts']['S'])))

    def test_model_errors_fall_back_to_template(self):
        result, dynamo, _ = go(bedrock=StubBedrock(fail=True))
        self.assertEqual((result['template'], result['model_errors'], result['written']), (5, 10, 5))

    def test_every_group_template_passes(self):
        items, _ = triage(baseline=[feature(77.70, 28.7), feature(77.72, 28.7, 'CFCBK'), feature(77.74, 28.7), feature(77.76, 28.7)],
                          registry=[record(77.70, 28.7, kid(1)), record(77.72, 28.7, kid(2), 'Zigzag'),
                                    record(77.74, 28.7, kid(3), score=0.42), record(77.80, 28.7, kid(4))])
        for facts in items:
            self.assertIsNone(agent.check(agent.template(facts), facts), facts['group'])

    def test_item_cap(self):
        bedrock = StubBedrock()
        result, dynamo, _ = go(bedrock=bedrock, sample=many_new(81))
        self.assertEqual((result['ok'], result['error'], result['items']), (False, 'too_many_items', 81))
        self.assertEqual((dynamo.calls, bedrock.calls), ([], []))
        result, dynamo, _ = go(bedrock=bedrock, sample=many_new(80))
        self.assertEqual((result['ok'], result['written'], result['model_calls']), (True, 80, 80))

    def test_model_call_budget(self):
        bedrock = StubBedrock()
        result, dynamo, _ = go({**EVENT, 'max_model_calls': 4}, bedrock=bedrock)
        self.assertEqual((result['error'], dynamo.calls, bedrock.calls), ('model_call_cap', [], []))
        # Budget equal to the item count: no regenerations, failures go straight to the template.
        result, _, _ = go({**EVENT, 'max_model_calls': 5}, bedrock=StubBedrock(text='It is confirmed.'))
        self.assertEqual((result['model_calls'], result['regenerated'], result['template']), (5, 0, 5))

    def test_deadline_cursor(self):
        sample = many_new(20)
        first, dynamo, _ = go(sample=sample, context=Context([28_000, 5_000]))
        self.assertEqual(first['processed'], agent.CHUNK)
        self.assertIsNotNone(first['next_start_after'])
        second, dynamo, _ = go({**EVENT, 'start_after': first['next_start_after']}, sample=sample, dynamo=dynamo)
        self.assertEqual((second['processed'], second['existing'], len(dynamo.items)), (20 - agent.CHUNK, 0, 20))
        self.assertIsNone(second['next_start_after'])

    def test_inputs_unavailable_writes_nothing(self):
        dynamo = StubDynamo()
        result = agent.run(EVENT, Context(), dynamodb=dynamo, s3=StubS3({}), bedrock=StubBedrock(), api=StubAPI([]),
                           model_id='m', table='review', bucket='data', now=NOW)
        self.assertEqual((result['error'], result['kind'], dynamo.calls), ('inputs_unavailable', 'KeyError', []))


if __name__ == '__main__':
    unittest.main()

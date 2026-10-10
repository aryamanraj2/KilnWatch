"""Phase 4A assistant: synthetic tests only. Bedrock, DynamoDB and the public API are stubs; no network or AWS.
These check the validator and the flow, not a real model's behaviour."""
import base64
import copy
import functools
import io
import json
import sys
import unittest
import unittest.mock
import urllib.error
import urllib.parse
from datetime import datetime, timezone
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'assistant'))
import core
import handler
import tools
import validator

FIXTURE = json.loads((Path(__file__).resolve().parent / 'public_hapur.json').read_text())['kilns']
IDS = sorted(k['kiln_id'] for k in FIXTURE)
KID = IDS[0]
BASE = 'https://public.example.invalid'
NOW = datetime(2026, 10, 10, 12, tzinfo=timezone.utc)


class Reply(io.BytesIO):
    status = 200


class StubOpener:
    """Serves the recorded 39-record public list the way the live API does (keyset pages, near, detail)."""
    def __init__(self, records=None, fail=None):
        self.records = sorted(records or copy.deepcopy(FIXTURE), key=lambda k: k['kiln_id'])
        self.fail, self.urls = fail, []

    def open(self, request, timeout):
        assert timeout == 5 and request.full_url.startswith(BASE + '/public/kilns')
        self.urls.append(request.full_url)
        if self.fail == 'timeout': raise TimeoutError()
        if self.fail: raise urllib.error.HTTPError(request.full_url, self.fail, 'x', {}, io.BytesIO(b'{}'))
        url = urllib.parse.urlsplit(request.full_url)
        query = dict(urllib.parse.parse_qsl(url.query))
        if url.path != '/public/kilns':
            found = [k for k in self.records if k['kiln_id'] == url.path.rsplit('/', 1)[1]]
            if not found: raise urllib.error.HTTPError(request.full_url, 404, 'x', {}, io.BytesIO(b'{}'))
            return Reply(json.dumps(found[0]).encode())
        if 'lat' in query:
            return Reply(json.dumps({'kilns': [{**k, 'distance_m': 10 * i} for i, k in enumerate(self.records[:4])],
                                     'next_cursor': None}).encode())
        rows = [k for k in self.records if k['district'] == query['district'] and k['kiln_id'] > query.get('cursor', '')]
        limit = int(query['limit'])
        return Reply(json.dumps({'kilns': rows[:limit],
                                 'next_cursor': rows[limit - 1]['kiln_id'] if len(rows) > limit else None}).encode())


class AWSError(Exception):
    def __init__(self, code):
        super().__init__(f'{code}: secret provider text')
        self.response = {'Error': {'Code': code, 'Message': 'secret provider text'}}


class StubBedrock:
    def __init__(self, *replies):
        self.replies, self.calls = list(replies), []

    def converse(self, **kwargs):
        assert kwargs['inferenceConfig']['temperature'] <= 0.2 and kwargs['inferenceConfig']['maxTokens'] == 600
        self.calls.append(copy.deepcopy(kwargs))
        reply = self.replies.pop(0) if len(self.replies) > 1 else self.replies[0]
        if isinstance(reply, Exception): raise reply
        return copy.deepcopy(reply)


class StubDynamo:
    """Implements the conditional ADD the handler sends."""
    def __init__(self, count=None, fail=False):
        self.items, self.fail, self.calls = ({} if count is None else {'2026-10-10': count}), fail, 0

    def update_item(self, TableName, Key, UpdateExpression, ConditionExpression, ExpressionAttributeValues):
        self.calls += 1
        if self.fail: raise AWSError('ResourceNotFoundException')
        assert UpdateExpression.startswith('ADD question_count :one') and 'attribute_not_exists' in ConditionExpression
        day, cap = Key['day']['S'], int(ExpressionAttributeValues[':cap']['N'])
        if day in self.items and self.items[day] >= cap: raise AWSError('ConditionalCheckFailedException')
        self.items[day] = self.items.get(day, 0) + 1


def use(name, args, uid='t1'):
    return {'stopReason': 'tool_use', 'usage': {'inputTokens': 100, 'outputTokens': 20},
            'output': {'message': {'role': 'assistant', 'content': [{'toolUse': {'toolUseId': uid, 'name': name, 'input': args}}]}}}


def say(text):
    return {'stopReason': 'end_turn', 'usage': {'inputTokens': 100, 'outputTokens': 20},
            'output': {'message': {'role': 'assistant', 'content': [{'text': text}]}}}


def event(body, method='POST', path='/ask', raw=False):
    return {'rawPath': path, 'requestContext': {'http': {'method': method}},
            'body': body if raw else json.dumps(body)}


class Context:
    aws_request_id = 'req-1'
    def get_remaining_time_in_millis(self): return 28000


def call(body, bedrock, opener=None, dynamo=None, raw=False):
    dynamo = dynamo or StubDynamo()
    ask = functools.partial(core.answer, bedrock=bedrock, api=tools.PublicAPI(BASE, opener or StubOpener()), model_id='test-model')
    return handler.handle(event(body, raw=raw), Context(), dynamodb=dynamo, ask=ask, now=NOW), dynamo


def body_of(result): return json.loads(result['body'])


class Env(unittest.TestCase):
    def setUp(self):
        patcher = unittest.mock.patch.dict('os.environ', {'COUNTER_TABLE': 'counter', 'DAILY_CAP': '300'})
        patcher.start(); self.addCleanup(patcher.stop)



class RequestValidationTests(Env):
    def test_rejects_bad_bodies_before_counting(self):
        bad = ['', 'not json', '[1]', '{"question": "   "}', json.dumps({'question': 'x' * 501}),
               json.dumps({'question': 'hi', 'extra': 1}), json.dumps({'question': 'hi', 'kiln_id': 'KW-6b3b'}),
               json.dumps({'question': 'hi', 'kiln_id': KID.upper()}), json.dumps({'question': 'hi', 'lat': 28.7}),
               json.dumps({'question': 'hi', 'lon': 77.7}), '{"question": "hi", "lat": NaN, "lon": 77}',
               '{"question": "hi", "lat": Infinity, "lon": 77}', '{"question": "hi", "lat": 1e400, "lon": 77}',
               json.dumps({'question': 'hi', 'lat': 91, 'lon': 77}), json.dumps({'question': 'hi', 'lat': True, 'lon': 77}),
               json.dumps({'question': 'hi', 'lat': '28.7', 'lon': '77.7'}), json.dumps({'question': 5}),
               '{"question": "hi"' + ' ' * 2048 + '}']
        for raw in bad:
            with self.subTest(raw=raw[:40]):
                bedrock = StubBedrock(say('unused'))
                result, dynamo = call(raw, bedrock, raw=True)
                self.assertEqual(result['statusCode'], 400)
                self.assertEqual(body_of(result)['error']['code'], 'invalid_request')
                self.assertEqual((dynamo.calls, len(bedrock.calls)), (0, 0))

    def test_accepts_limits_and_base64(self):
        for body in [{'question': 'x' * 500}, {'question': 'hi', 'kiln_id': KID, 'lat': 28.7, 'lon': 77.7}]:
            result, _ = call(body, StubBedrock(say('No kilns were looked up.')))
            self.assertEqual(result['statusCode'], 200)
        e = event(None); e['body'] = base64.b64encode(b'{"question":"hi"}').decode(); e['isBase64Encoded'] = True
        result = handler.handle(e, Context(), dynamodb=StubDynamo(), now=NOW,
                                ask=functools.partial(core.answer, bedrock=StubBedrock(say('Hello.')),
                                                      api=tools.PublicAPI(BASE, StubOpener()), model_id='m'))
        self.assertEqual(result['statusCode'], 200)

    def test_wrong_route_is_404(self):
        result = handler.handle(event({'question': 'hi'}, method='GET'), Context(), dynamodb=StubDynamo(), ask=None)
        self.assertEqual(result['statusCode'], 404)


class DailyCapTests(Env):
    def test_300th_passes_301st_is_429(self):
        dynamo = StubDynamo(count=299)
        result, _ = call({'question': 'hi'}, StubBedrock(say('Hello.')), dynamo=dynamo)
        self.assertEqual(result['statusCode'], 200); self.assertEqual(dynamo.items['2026-10-10'], 300)
        bedrock = StubBedrock(say('Hello.'))
        result, _ = call({'question': 'hi'}, bedrock, dynamo=dynamo)
        self.assertEqual(result['statusCode'], 429)
        self.assertEqual(body_of(result), {'error': {'code': 'daily_cap_reached', 'retryable': False,
                                                     'message': "Ask has reached today's limit. Try again tomorrow."}})
        self.assertEqual(bedrock.calls, [])

    def test_counter_failure_fails_closed(self):
        bedrock = StubBedrock(say('Hello.'))
        result, _ = call({'question': 'hi'}, bedrock, dynamo=StubDynamo(fail=True))
        self.assertEqual(result['statusCode'], 503)
        self.assertEqual(body_of(result)['error']['code'], 'assistant_unavailable')
        self.assertTrue(body_of(result)['error']['retryable']); self.assertEqual(bedrock.calls, [])

    def test_failed_question_still_counts_once(self):
        dynamo = StubDynamo()
        call({'question': 'hi'}, StubBedrock(use('list_flagged_kilns', {'district': 'Hapur'}), say('bad KW-123')), dynamo=dynamo)
        self.assertEqual(dynamo.items['2026-10-10'], 1)


class ToolTests(unittest.TestCase):
    def api(self, **kw):
        self.opener = StubOpener(**kw); return tools.PublicAPI(BASE, self.opener)

    def test_invalid_inputs_are_error_results(self):
        cases = [('list_flagged_kilns', {}), ('list_flagged_kilns', {'district': ''}),
                 ('list_flagged_kilns', {'district': "Hapur'; drop"}), ('list_flagged_kilns', {'district': 'Hapur', 'limit': 0}),
                 ('list_flagged_kilns', {'district': 'Hapur', 'limit': 51}), ('list_flagged_kilns', {'district': 'Hapur', 'limit': 2.5}),
                 ('list_flagged_kilns', {'district': 'Hapur', 'limit': True}), ('kilns_near', {'lat': 91, 'lon': 77}),
                 ('kilns_near', {'lat': 28.7}), ('kilns_near', {'lat': float('nan'), 'lon': 77}),
                 ('kilns_near', {'lat': 28.7, 'lon': 77.7, 'radius_m': 50}), ('kilns_near', {'lat': 28.7, 'lon': 77.7, 'radius_m': 6000}),
                 ('kiln_detail', {'kiln_id': 'KW-6b3b'}), ('kiln_detail', {'kiln_id': KID + ' '}), ('route_plan', {}),
                 ('kiln_detail', 'not a dict')]
        for name, args in cases:
            with self.subTest(name=name, args=args):
                result, step, ids = tools.run(self.api(), name, args)
                self.assertIn('error', result); self.assertFalse(step['ok']); self.assertEqual(ids, [])
                self.assertEqual(self.opener.urls, [])
        self.assertEqual(tools.run(self.api(), 'evil<script>', {})[1]['tool'], 'unknown')

    def test_trimming_keeps_urls_and_internal_fields_out(self):
        record = {**copy.deepcopy(FIXTURE[0]), 'review_state': 'secret-review', 'provenance': {'input_sha256': 'f' * 64},
                  'evidence': {'before': None, 'after': 'https://cdn.example.invalid/evidence/x.png',
                               'after_metadata': {'object_key': 'evidence/x.png', 'source_assets': [{'href': 'https://s3/x'}]}}}
        record['footprint']['polygon'] = [{'latitude': 1, 'longitude': 2}]
        result, _, ids = tools.run(self.api(records=[record]), 'kiln_detail', {'kiln_id': record['kiln_id']})
        text = json.dumps(result)
        for leaked in ('http', 'secret-review', 'provenance', 'polygon', 'object_key', 'f' * 64, 'detection_confidence'):
            self.assertNotIn(leaked, text)
        kiln = result['kiln']
        self.assertEqual((kiln['images_published'], kiln['exposure_assessed'], kiln['type_verification'],
                          kiln['rules_assessment']), (True, False, 'unverified', 'not_evaluated'))
        self.assertEqual(kiln['predicted_type'], record['type']); self.assertEqual(ids, [record['kiln_id']])

    def test_pagination(self):
        result, step, ids = tools.run(self.api(), 'list_flagged_kilns', {'district': 'Hapur'})
        self.assertEqual((result['count'], result['more_pages'], step['summary'], len(self.opener.urls)), (39, False, '39 found', 1))
        result, step, _ = tools.run(self.api(), 'list_flagged_kilns', {'district': 'Hapur', 'limit': 20})
        self.assertEqual((result['count'], result['more_pages'], step['summary'], len(self.opener.urls)), (39, False, '39 found', 2))
        result, step, ids = tools.run(self.api(), 'list_flagged_kilns', {'district': 'Hapur', 'limit': 10})
        self.assertEqual((result['count'], result['more_pages'], step['summary'], len(self.opener.urls)), (20, True, '20+ found', 2))
        self.assertEqual(ids, IDS[:20])

    def test_near_and_404(self):
        result, step, ids = tools.run(self.api(), 'kilns_near', {'lat': 28.7, 'lon': 77.7})
        kilns = result['kilns']
        self.assertEqual((step['summary'], kilns['rows'][1][kilns['columns'].index('distance_m')], len(ids)), ('4 within 2000 m', 10, 4))
        self.assertEqual(kilns['rows'][1][0], ids[1])
        self.assertIn('lat=28.700000', self.opener.urls[0])
        result, step, ids = tools.run(self.api(), 'kiln_detail', {'kiln_id': 'KW-' + 'f' * 32})
        self.assertEqual((result['found'], step['summary'], step['ok'], ids), (False, 'Not found', True, []))

    def test_upstream_failures(self):
        for fail in (429, 500, 503, 'timeout'):
            with self.subTest(fail=fail):
                with self.assertRaises(tools.UpstreamUnavailable):
                    tools.run(self.api(fail=fail), 'list_flagged_kilns', {'district': 'Hapur'})


class UpstreamMappingTests(Env):
    def test_public_api_failure_is_503(self):
        for fail in (429, 502, 'timeout'):
            bedrock = StubBedrock(use('list_flagged_kilns', {'district': 'Hapur'}), say('unused'))
            result, _ = call({'question': 'hi'}, bedrock, opener=StubOpener(fail=fail))
            self.assertEqual(result['statusCode'], 503)
            self.assertEqual(body_of(result)['error'], {'code': 'upstream_unavailable', 'retryable': True,
                                                        'message': 'Kiln data is temporarily unavailable. Try again.'})
            self.assertEqual(len(bedrock.calls), 1)

    def test_model_errors(self):
        for code, retryable in (('ThrottlingException', True), ('AccessDeniedException', False), ('ValidationException', False)):
            result, _ = call({'question': 'hi'}, StubBedrock(AWSError(code)))
            self.assertEqual(result['statusCode'], 503)
            self.assertEqual(body_of(result)['error']['code'], 'model_unavailable')
            self.assertEqual(body_of(result)['error']['retryable'], retryable)
            self.assertNotIn('secret provider text', result['body'])

    def test_deadline_stops_model_calls(self):
        bedrock = StubBedrock(say('Hello.'))
        with self.assertRaises(core.ModelUnavailable):
            core.answer('hi', bedrock=bedrock, api=tools.PublicAPI(BASE, StubOpener()), model_id='m', deadline=0)
        self.assertEqual(bedrock.calls, [])


class RoundLimitTests(Env):
    def test_four_tool_rounds_then_fallback(self):
        bedrock = StubBedrock(use('list_flagged_kilns', {'district': 'Hapur'}))
        metrics = {}
        result = core.answer('hi', bedrock=bedrock, api=tools.PublicAPI(BASE, StubOpener()), model_id='m', metrics=metrics)
        self.assertEqual((len(bedrock.calls), metrics['rounds'], metrics['validator']), (6, 4, 'fallback'))
        self.assertTrue(result['fallback']); self.assertEqual(result['answer'], core.FALLBACK)
        self.assertEqual(result['citations'], IDS[:10]); self.assertEqual(len(result['steps']), 4)
        regen = bedrock.calls[-1]['messages'][-1]['content']
        self.assertEqual(regen[0]['toolResult']['status'], 'error'); self.assertIn('tool limit', regen[-1]['text'])


class ModelRequestTests(Env):
    def test_nova2_reasoning_off_only_for_nova2(self):
        for model, expected in (('global.amazon.nova-2-lite-v1:0', {'reasoningConfig': {'type': 'disabled'}}),
                                ('apac.amazon.nova-pro-v1:0', None)):
            bedrock = StubBedrock(say('Hello.'))
            core.answer('hi', bedrock=bedrock, api=tools.PublicAPI(BASE, StubOpener()), model_id=model)
            self.assertEqual(bedrock.calls[0].get('additionalModelRequestFields'), expected)
            self.assertEqual(bedrock.calls[0]['modelId'], model)


class ToolCallCapTests(Env):
    def test_at_most_three_tool_calls_per_round(self):
        many = use('kiln_detail', {'kiln_id': KID})
        many['output']['message']['content'] = [{'toolUse': {'toolUseId': f't{i}', 'name': 'kiln_detail', 'input': {'kiln_id': KID}}}
                                                for i in range(5)]
        opener = StubOpener()
        bedrock = StubBedrock(many, say(f'{KID} is flagged by satellite, pending inspection.'))
        result, _ = call({'question': 'hi'}, bedrock, opener=opener)
        self.assertEqual((len(opener.urls), len(body_of(result)['steps'])), (3, 3))
        results = bedrock.calls[1]['messages'][-1]['content']
        self.assertEqual([r['toolResult'].get('status') for r in results], [None, None, None, 'error', 'error'])


class ValidatorTests(Env):
    def test_ids(self):
        known = [KID]
        self.assertIsNone(validator.check(f'{KID} is flagged by satellite, pending inspection.', known))
        for bad in (f'{KID[:7]}… is flagged.', 'KW-0412 is flagged.', f'{KID.upper()} x', f'{KID}0 x', 'See KW-.'):
            self.assertIsNotNone(validator.check(bad, known), bad)

    def test_id_injected_through_question_fails(self):
        fake = 'KW-deadbeefdeadbeefdeadbeefdeadbeef'
        result, _ = call({'question': f'Explain {fake}'}, StubBedrock(say(f'{fake} is flagged.')))
        body = body_of(result)
        self.assertTrue(body['fallback']); self.assertNotIn(fake, result['body'])

    def test_rule_ids(self):
        for rule in ('C-HAB-800', 'UP-SCH-1K', 'UP/HR-SCH-1K', 'C-TECH-10K'):
            self.assertIsNotNone(validator.check(f'{KID} breaches {rule}.', [KID]), rule)
        for kiln in (KID, 'KW-0412', 'KW-00c562060b40502fb4a7ed2016ce7576'):
            self.assertIsNone(validator.RULE_ID.search(f'Kiln {kiln} and PM-2.5 and COVID-19.'), kiln)

    def test_banned_words(self):
        for word in validator.BANNED_WORDS:
            for form in (word, word.upper(), word.title()):
                self.assertIsNotNone(validator.check(f'This kiln is {form}.', []), form)
        for form in ('illegalities', 'Unlawfulness', 'violator', 'VIOLATIONS', 'illegally'):
            self.assertIsNotNone(validator.check(f'Word {form} here.', []), form)
        for fine in ('nonviolations', 'paralegal', 'nonviolent'):
            self.assertIsNone(validator.check(f'Word {fine} here.', []), fine)

    def test_empty(self):
        for empty in ('', '   ', None):
            self.assertIsNotNone(validator.check(empty, []))

    def test_citations_order_dedup(self):
        self.assertEqual(validator.citations(f'{IDS[1]}, {IDS[0]} and {IDS[1]}.'), [IDS[1], IDS[0]])


class RegenerateTests(Env):
    def test_first_fails_second_passes(self):
        bedrock = StubBedrock(use('kiln_detail', {'kiln_id': KID}), say(f'{KID[:7]}… is flagged.'),
                              say(f'{KID} is flagged by satellite, pending inspection.'))
        result, _ = call({'question': 'hi'}, bedrock)
        body = body_of(result)
        self.assertFalse(body['fallback']); self.assertEqual(body['citations'], [KID])
        self.assertIn('which no tool returned', bedrock.calls[-1]['messages'][-1]['content'][-1]['text'])

    def test_both_fail_fallback_has_no_model_text(self):
        bedrock = StubBedrock(use('kiln_detail', {'kiln_id': KID}), say('MODELTEXT C-HAB-800'), say('MODELTEXT again KW-1234'))
        result, _ = call({'question': 'hi'}, bedrock)
        body = body_of(result)
        self.assertEqual((body['fallback'], body['answer'], body['citations']), (True, core.FALLBACK, [KID]))
        self.assertNotIn('MODELTEXT', result['body'])

    def test_fallback_without_lookups(self):
        result, _ = call({'question': 'hi'}, StubBedrock(say('KW-1234 x'), say('KW-1234 y')))
        self.assertEqual((body_of(result)['answer'], body_of(result)['citations']), (core.FALLBACK_EMPTY, []))


class AdversarialFlowTests(Env):
    """Scripted bad first answers. Real-model adversarial checks are prompt 16."""
    def test_scripted_conversations(self):
        fake = 'KW-' + '0' * 32
        bad = validator.BANNED_WORDS[0]
        cases = {
            f'Is this kiln {bad}?': (f'Yes, {KID} is {bad}.', f'{KID} is flagged by satellite, pending inspection. Rules are not evaluated.'),
            'Who owns it?': (f'{KID[:9]} is owned by a local trader.', f'Ownership is not in the record for {KID}.'),
            'Plan my route for today': ('Visit them in order under C-HAB-800.', 'Route planning is not available yet.'),
            'Is it dangerous for my kids?': (f'{KID} is a violation and dangerous.', f'Exposure is not assessed for {KID}.'),
            f'Explain {fake}': (f'{fake} is flagged.', f'{fake} is still flagged.'),
        }
        for question, (first, second) in cases.items():
            with self.subTest(question=question):
                bedrock = StubBedrock(use('kiln_detail', {'kiln_id': KID}), say(first), say(second))
                result, _ = call({'question': question, 'kiln_id': KID}, bedrock)
                body = body_of(result)
                self.assertEqual(result['statusCode'], 200)
                self.assertIsNone(validator.check(body['answer'], [KID]) if not body['fallback'] else None)
                self.assertNotRegex(result['body'], validator.BANNED)
                self.assertTrue(set(body['citations']) <= {KID})
                self.assertNotIn(first, result['body'])


class LogPrivacyTests(Env):
    def test_logs_hold_counts_only(self):
        sentinel_q, sentinel_a = 'ZEBRA-SENTINEL-QUESTION', 'marmalade-sentinel-answer'
        bedrock = StubBedrock(use('kilns_near', {'lat': 28.123457, 'lon': 77.654321}),
                              say(f'{KID} {sentinel_a}'))
        with self.assertLogs(level='DEBUG') as captured:
            result, _ = call({'question': sentinel_q, 'kiln_id': KID, 'lat': 28.123457, 'lon': 77.654321}, bedrock)
        self.assertEqual(result['statusCode'], 200)
        logs = '\n'.join(captured.output)
        for secret in (sentinel_q, sentinel_a, '28.123457', '77.654321', '28.12346', KID, FIXTURE[1]['kiln_id'], 'Hapur'):
            self.assertNotIn(secret, logs)
        line = json.loads(captured.records[-1].getMessage())
        self.assertEqual((line['status'], line['rounds'], line['tools'], line['validator']), (200, 1, {'kilns_near': 1}, 'pass'))
        self.assertEqual((line['input_tokens'], line['output_tokens'], line['request_id']), (200, 40, 'req-1'))


class ShapeTests(Env):
    def test_success_shape_headers_and_steps(self):
        bedrock = StubBedrock(use('list_flagged_kilns', {'district': 'Hapur'}), say(f'39 kilns are flagged, for example {IDS[2]} and {IDS[1]}.'))
        result, _ = call({'question': 'How many in Hapur?'}, bedrock)
        self.assertEqual(result['headers'], {'content-type': 'application/json', 'cache-control': 'no-store'})
        body = body_of(result)
        self.assertEqual(set(body), {'answer', 'citations', 'steps', 'fallback', 'disclaimer'})
        self.assertEqual(body['citations'], [IDS[2], IDS[1]]); self.assertEqual(body['disclaimer'], core.DISCLAIMER)
        self.assertEqual(body['steps'], [{'tool': 'list_flagged_kilns', 'label': 'Searching flagged kilns', 'summary': '39 found', 'ok': True}])
        tool_result = bedrock.calls[1]['messages'][-1]['content'][0]['toolResult']['content'][0]['json']
        for raw in (IDS[0], 'CFCBK', 'model_score', str(FIXTURE[0]['footprint']['centroid']['latitude'])[:6]):
            self.assertNotIn(raw, json.dumps(body['steps']))
        self.assertEqual(tool_result['count'], 39)

    def test_detail_step_label_and_user_turn(self):
        bedrock = StubBedrock(use('kiln_detail', {'kiln_id': KID}), say(f'{KID} is flagged by satellite, pending inspection.'))
        result, _ = call({'question': 'Explain', 'kiln_id': KID}, bedrock)
        self.assertEqual(body_of(result)['steps'][0]['label'], f'Looking up {KID[:7]}…')
        first = bedrock.calls[0]['messages'][0]['content'][0]['text']
        self.assertIn(f'viewing kiln {KID}', first); self.assertIn('<question>\nExplain\n</question>', first)
        self.assertNotRegex(core.SYSTEM.replace(', '.join(validator.BANNED_WORDS), ''), validator.BANNED)



class FakeBoto3:
    """Stands in for boto3 inside core.default_bedrock: records the clients built and serves STS credentials."""
    def __init__(self, sts_error=None):
        self.clients, self.assumed, self.sts_error = [], [], sts_error

    def client(self, name, **kwargs):
        self.clients.append((name, kwargs))
        return self if name == 'sts' else object()

    def assume_role(self, **kwargs):
        self.assumed.append(kwargs)
        if self.sts_error: raise self.sts_error
        return {'Credentials': {'AccessKeyId': 'AK', 'SecretAccessKey': 'SK', 'SessionToken': 'ST',
                                'Expiration': datetime.fromtimestamp(NOW.timestamp() + 900, timezone.utc)}}

    def runtime_clients(self): return [kwargs for name, kwargs in self.clients if name == 'bedrock-runtime']


class CrossAccountBedrockTests(Env):
    ROLE = 'arn:aws:iam::123456789012:role/kilnwatch-assistant-bedrock'

    def setUp(self):
        super().setUp()
        self.boto3 = FakeBoto3()
        for patcher in (unittest.mock.patch.dict(sys.modules, {'boto3': self.boto3}),
                        unittest.mock.patch.dict(core._bedrock, {'client': None, 'expires': 0.0})):
            patcher.start(); self.addCleanup(patcher.stop)
        for name in ('BEDROCK_ROLE_ARN', 'BEDROCK_REGION'):
            core.os.environ.pop(name, None)  # restored by Env's patch.dict

    def at(self, seconds): return lambda: NOW.timestamp() + seconds

    def test_no_env_means_no_sts_and_one_client(self):
        first = core.default_bedrock(self.at(0))
        self.assertIs(core.default_bedrock(self.at(86400)), first)
        self.assertEqual(self.boto3.assumed, [])
        self.assertEqual([name for name, _ in self.boto3.clients], ['bedrock-runtime'])
        self.assertIsNone(self.boto3.runtime_clients()[0]['region_name'])
        self.assertNotIn('aws_session_token', self.boto3.runtime_clients()[0])

    def test_role_assumed_once_and_reused(self):
        core.os.environ['BEDROCK_ROLE_ARN'] = self.ROLE
        first = core.default_bedrock(self.at(0))
        self.assertIs(core.default_bedrock(self.at(60)), first)
        self.assertEqual(self.boto3.assumed, [{'RoleArn': self.ROLE, 'RoleSessionName': 'kilnwatch-assistant', 'DurationSeconds': 900}])
        self.assertEqual(self.boto3.runtime_clients()[0]['aws_session_token'], 'ST')

    def test_reassumes_when_under_five_minutes_remain(self):
        core.os.environ['BEDROCK_ROLE_ARN'] = self.ROLE
        core.default_bedrock(self.at(0))
        core.default_bedrock(self.at(599))
        self.assertEqual(len(self.boto3.assumed), 1)
        core.default_bedrock(self.at(601))
        self.assertEqual((len(self.boto3.assumed), len(self.boto3.runtime_clients())), (2, 2))

    def test_region_override(self):
        core.os.environ['BEDROCK_REGION'] = 'us-east-1'
        core.default_bedrock(self.at(0))
        self.assertEqual(self.boto3.runtime_clients()[0]['region_name'], 'us-east-1')
        self.assertEqual(self.boto3.assumed, [])

    def test_assume_role_failure_is_503_without_aws_text(self):
        core.os.environ['BEDROCK_ROLE_ARN'] = self.ROLE
        for code, retryable in (('AccessDenied', False), ('Throttling', True)):
            with self.subTest(code=code):
                self.boto3.sts_error = AWSError(code)
                ask = functools.partial(core.answer, api=tools.PublicAPI(BASE, StubOpener()), model_id='test-model')
                with self.assertLogs(level='INFO') as captured:
                    result = handler.handle(event({'question': 'hi'}), Context(), dynamodb=StubDynamo(), ask=ask, now=NOW)
                self.assertEqual(result['statusCode'], 503)
                self.assertEqual((body_of(result)['error']['code'], body_of(result)['error']['retryable']), ('model_unavailable', retryable))
                self.assertNotIn('secret provider text', result['body'] + '\n'.join(captured.output))
                self.assertEqual(json.loads(captured.records[-1].getMessage())['validator'], 'none')
                self.assertEqual(self.boto3.runtime_clients(), [])

    def test_validator_label_is_none_when_model_fails(self):
        metrics = {}
        with self.assertRaises(core.ModelUnavailable):
            core.answer('hi', bedrock=StubBedrock(AWSError('AccessDeniedException')),
                        api=tools.PublicAPI(BASE, StubOpener()), model_id='m', metrics=metrics)
        self.assertEqual((metrics['validator'], metrics['model_calls']), ('none', 1))
        core.answer('hi', bedrock=StubBedrock(say('Route planning is not available yet.')),
                    api=tools.PublicAPI(BASE, StubOpener()), model_id='m', metrics=metrics)
        self.assertEqual(metrics['validator'], 'pass')


if __name__ == '__main__':
    unittest.main()

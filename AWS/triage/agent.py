"""Change triage, step 2 (concept Agent 2): one reason sentence per diff item, then queue_for_review.

Internal invocation only (the assistant handler routes a direct event here; there is no API route).
queue_for_review is the only write: a conditional PutItem into the review queue. Nothing here can change a
kiln's status or review state; the registry changes only when a reviewer approves an item (not built yet).
The model sees only the item's facts and writes the reason; groups, matches and numbers come from diff.py."""
import concurrent.futures
import json
import logging
import os
import re
import time
from datetime import datetime, timezone
import core
from tools import PublicAPI
from validator import BANNED, BANNED_WORDS
from triage import diff

log = logging.getLogger('kilnwatch.triage')
log.setLevel(logging.INFO)
MAX_ITEMS = 80
MAX_MODEL_CALLS = 80  # per invocation, regenerations included
WORKERS = 8
CHUNK = 16  # items per batch of parallel model calls; the deadline is checked between batches
MIN_REMAINING_MS = 12_000
DISTRICT = 'Hapur'  # the demo AOI's only district
RUN_ID = re.compile(r'^[a-z0-9-]{1,63}$')
ITEM_ID = re.compile(r'^[0-9a-f]{32}$')
KEYS = {'action', 'baseline_run', 'current', 'current_run', 'start_after', 'max_model_calls'}
INFERENCE = {'temperature': 0.2, 'maxTokens': 160}
MAX_GEOJSON = 5_000_000

KILN_TOKEN = re.compile(r'\bKW-[0-9A-Za-z]*', re.IGNORECASE)
SCENE_TOKEN = re.compile(r'\bS2[A-Z]_[0-9A-Za-z_]*')
STATUS_WORDS = re.compile(r'\b(?:confirmed|compliant|closed|approved|not a kiln)\b', re.IGNORECASE)
DATE_CLAIMS = re.compile(r'\b(?:built|construct\w*|demolish\w*|demolition|torn down|knocked down|shut|newly)\b',
                         re.IGNORECASE)
FINDING = re.compile(r'\bfindings?\b', re.IGNORECASE)

SYSTEM = f"""You write the reason line for one item in KilnWatch's human review queue. A satellite detector compared an older Sentinel-2 scene with today's kiln registry, and code sorted this difference into a group. You get the item's facts as JSON.

Write one or two plain sentences, at most 45 words, saying why this item needs a human look. Use only the facts given.
- The item is a candidate for review, never a finding.
- Never use any word that starts with these stems: {", ".join(BANNED_WORDS)}.
- Never say confirmed, compliant, closed, approved or "not a kiln": only a human reviewer decides.
- Never say when a kiln was built, constructed, demolished or shut. Use the group_words wording, such as "not detected in the Dec 2023 scene" or "no longer detected".
- A detector score is not accuracy and not a probability. The predicted type is unverified.
- Cite the kiln ID and scene IDs only exactly as given. If kiln_id is null, don't name a kiln ID.
- Plain text only: no Markdown, no lists, no greeting."""


def parse(event):
    """Returns the request or None. Anything unexpected is rejected."""
    if not isinstance(event, dict) or set(event) - KEYS or event.get('action') != 'triage': return None
    baseline, current_run = event.get('baseline_run'), event.get('current_run', 'm0-after')
    start_after, calls = event.get('start_after'), event.get('max_model_calls', MAX_MODEL_CALLS)
    if not (isinstance(baseline, str) and RUN_ID.fullmatch(baseline)): return None
    if not (isinstance(current_run, str) and RUN_ID.fullmatch(current_run)) or event.get('current') != 'registry': return None
    if start_after is not None and not (isinstance(start_after, str) and ITEM_ID.fullmatch(start_after)): return None
    if isinstance(calls, bool) or not isinstance(calls, int) or not 1 <= calls <= MAX_MODEL_CALLS: return None
    return {'baseline_run': baseline, 'current_run': current_run, 'start_after': start_after, 'max_model_calls': calls}


def model_view(facts):
    """What the model sees: the facts minus URLs, footprint corners and the item ID."""
    view = {k: v for k, v in facts.items() if k not in ('item_id', 'evidence', 'centroid', 'baseline_run', 'compared_with')}
    view['images'] = 'no published image' if 'images' in facts['evidence'] else 'before and after images published'
    return view


def check(text, facts):
    """None when the reason passes, else a reason the model can act on."""
    if not isinstance(text, str) or not text.strip(): return 'Your reason was empty.'
    if len(text.split()) > 60: return 'Your reason was too long. Use at most 45 words.'
    for token in KILN_TOKEN.findall(text):
        if token != facts.get('kiln_id'): return f'You cited {token}, which is not in the facts. Cite only the given kiln_id.'
    scenes = {facts['baseline_scene']['id'], facts['current_scene']['id']}
    for token in SCENE_TOKEN.findall(text):
        if token not in scenes: return f'You cited scene {token}, which is not in the facts. Cite scene IDs exactly.'
    if BANNED.search(text) or FINDING.search(text): return 'You used a banned word. Call it a candidate for review.'
    if STATUS_WORDS.search(text): return 'You used a status word. Only a human reviewer decides status; say candidate for review.'
    if DATE_CLAIMS.search(text): return 'You claimed a construction or demolition date. Use the group_words wording.'
    return None


def template(facts):
    """The deterministic reason when the model fails twice. Passes check() by construction (tested)."""
    subject, group = facts['kiln_id'] or 'This candidate', facts['group']
    before, now = facts['baseline'], facts['current']
    then, today = diff.month(facts['baseline_scene']['date']), diff.month(facts['current_scene']['date'])
    if group == 'new_candidate':
        return (f"{subject} is in the registry as a {now['type']} candidate (detector score {now['score']}) but was not "
                f"detected in the {then} scene. Small kilns and haze can hide a kiln at 10 m pixels. Candidate for review.")
    if group == 'no_longer_detected':
        return (f"A {before['type']} candidate detected in the {then} scene (detector score {before['score']}) is no "
                f"longer detected in the {today} scene. Candidate for review.")
    if group == 'possible_zigzag_conversion':
        return (f"{subject} was detected as {before['type']} in the {then} scene and as Zigzag in the {today} scene, "
                f"a possible zigzag conversion. Candidate for review.")
    return (f"{subject} has a current detector score of {now['score']}, below the {diff.LOW_SCORE} review threshold; "
            f"a detector score is not accuracy. Candidate for review.")


def write_reason(bedrock, model_id, facts, previous=None):
    """One model call. previous: (text or None, failure) from the first attempt. Returns (text, failure, usage)."""
    content = [{'text': json.dumps(model_view(facts))}]
    messages = [{'role': 'user', 'content': content}]
    if previous:
        note = {'text': previous[1] + ' Write the reason again from the facts.'}
        if previous[0]: messages += [{'role': 'assistant', 'content': [{'text': previous[0]}]}, {'role': 'user', 'content': [note]}]
        else: content.append(note)
    try:
        reply = bedrock.converse(modelId=model_id, system=[{'text': SYSTEM}], messages=messages, inferenceConfig=INFERENCE,
                                 **({'additionalModelRequestFields': core.NOVA2_REASONING_OFF} if 'nova-2' in model_id else {}))
    except Exception:
        return None, 'The model call failed.', {}  # never echo provider text
    if reply.get('stopReason') == 'max_tokens':
        return None, 'Your reason was too long. Use at most 45 words.', reply.get('usage', {})
    text = core.plain_text(' '.join(b['text'] for b in reply['output']['message']['content'] if 'text' in b)).strip()
    return text, check(text, facts), reply.get('usage', {})


def queue_for_review(dynamodb, table, facts, reason, source, model_id, now):
    """The only tool and the only write. Idempotent on item_id: an existing item is left untouched.
    Returns True when written, False when it already existed."""
    item = {'item_id': {'S': facts['item_id']}, 'group': {'S': facts['group']}, 'facts': {'S': json.dumps(facts)},
            'reason': {'S': reason}, 'reason_source': {'S': source}, 'state': {'S': 'pending'},
            'created_at': {'S': now.isoformat(timespec='seconds')}, 'model_id': {'S': model_id if source == 'model' else 'none'},
            'baseline_run': {'S': facts['baseline_run']}, 'current': {'S': facts['compared_with']}}
    if facts['kiln_id']: item['kiln_id'] = {'S': facts['kiln_id']}
    try:
        dynamodb.put_item(TableName=table, Item=item, ConditionExpression='attribute_not_exists(item_id)')
    except Exception as exc:
        if getattr(exc, 'response', {}).get('Error', {}).get('Code') == 'ConditionalCheckFailedException': return False
        raise
    return True


def load_geojson(s3, bucket, run_id):
    body = s3.get_object(Bucket=bucket, Key=f'detections/{run_id}/kilns.geojson')['Body'].read(MAX_GEOJSON + 1)
    if len(body) > MAX_GEOJSON: raise ValueError('detections too large')
    return json.loads(body)


def load_registry(api):
    """Every Hapur kiln regardless of status (include=inspected), all pages."""
    kilns, cursor = [], None
    for _ in range(10):
        body = api.get('/public/kilns', {'district': DISTRICT, 'include': 'inspected', 'limit': 200,
                                         **({'cursor': cursor} if cursor else {})}) or {}
        kilns += body.get('kilns', [])
        cursor = body.get('next_cursor')
        if not cursor: return kilns
    raise ValueError('too many registry pages')


def run(event, context, *, dynamodb, s3=None, bedrock=None, api=None, model_id=None, table=None, bucket=None, now=None):
    started = time.monotonic()
    remaining = getattr(context, 'get_remaining_time_in_millis', lambda: 28_000)
    stats = {'items': 0, 'processed': 0, 'written': 0, 'existing': 0, 'model': 0, 'template': 0, 'regenerated': 0,
             'model_calls': 0, 'model_errors': 0, 'input_tokens': 0, 'output_tokens': 0}

    def done(result):
        # Counts and timings only: no kiln IDs, reasons, facts, URLs or names.
        log.info(json.dumps({'event': 'triage', 'ok': result['ok'], **{k: v for k, v in result.items() if k in stats},
                             **({'error': result['error']} if 'error' in result else {}),
                             'total_ms': int((time.monotonic() - started) * 1000)}))
        return {**result, 'total_ms': int((time.monotonic() - started) * 1000)}

    request = parse(event)
    if request is None: return done({'ok': False, 'error': 'invalid_event'})
    model_id = model_id or os.environ['MODEL_ID']
    table = table or os.environ['REVIEW_TABLE']
    try:
        if s3 is None:
            import boto3
            s3 = boto3.client('s3')
        bucket = bucket or os.environ['DETECTIONS_BUCKET']
        baseline = load_geojson(s3, bucket, request['baseline_run'])
        current = load_geojson(s3, bucket, request['current_run'])
        registry = load_registry(api or PublicAPI(os.environ['PUBLIC_API_BASE_URL']))
        items, summary = diff.triage([diff.from_feature(f) for f in baseline['features']],
                                     [diff.from_record(r) for r in registry],
                                     [diff.from_feature(f) for f in current['features']],
                                     diff.scene_of(baseline), diff.scene_of(current), request['baseline_run'])
    except Exception as exc:
        return done({'ok': False, 'error': 'inputs_unavailable', 'kind': type(exc).__name__})
    stats['items'] = len(items)
    result = {'ok': True, 'baseline_run': request['baseline_run'], 'current': 'registry',
              'current_run': request['current_run'], **summary}
    if len(items) > MAX_ITEMS: return done({**result, 'ok': False, 'error': 'too_many_items'})
    todo = [f for f in items if request['start_after'] is None or f['item_id'] > request['start_after']]
    budget = request['max_model_calls']
    if len(todo) > budget: return done({**result, **stats, 'ok': False, 'error': 'model_call_cap'})
    try:
        bedrock = bedrock or core.default_bedrock()
    except core.ModelUnavailable:
        return done({**result, **stats, 'ok': False, 'error': 'model_unavailable'})
    now = now or datetime.now(timezone.utc)
    next_start = None

    def tally(usage):
        stats['model_calls'] += 1
        stats['input_tokens'] += usage.get('inputTokens', 0)
        stats['output_tokens'] += usage.get('outputTokens', 0)

    with concurrent.futures.ThreadPoolExecutor(WORKERS) as pool:
        for start in range(0, len(todo), CHUNK):
            if remaining() < MIN_REMAINING_MS:
                next_start = todo[start - 1]['item_id']
                break
            chunk = todo[start:start + CHUNK]
            first = list(pool.map(lambda f: write_reason(bedrock, model_id, f), chunk))
            for text, failure, usage in first:
                tally(usage)
                stats['model_errors'] += failure == 'The model call failed.'
            # Regenerate once, keeping one call in reserve for every item not yet started.
            spare = budget - stats['model_calls'] - (len(todo) - start - len(chunk))
            retry = [k for k, (_, failure, _) in enumerate(first) if failure][:max(spare, 0)]
            second = dict(zip(retry, pool.map(lambda k: write_reason(bedrock, model_id, chunk[k], first[k][:2]), retry)))
            for k, facts in enumerate(chunk):
                if k in second:
                    tally(second[k][2])
                    stats['regenerated'] += 1
                    stats['model_errors'] += second[k][1] == 'The model call failed.'
                text, failure, _ = second.get(k, first[k])
                source = 'template' if failure else 'model'
                stats[source] += 1
                written = queue_for_review(dynamodb, table, facts, template(facts) if failure else text, source, model_id, now)
                stats['written' if written else 'existing'] += 1
                stats['processed'] += 1
    return done({**result, **stats, 'next_start_after': next_start})

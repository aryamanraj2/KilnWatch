import { describe, expect, it, vi } from 'vitest';
import { makeClient, mergePages, type Config } from '../src/data/client';
import { CHECK_STATUS, EXPOSURE_ATTRIBUTION, flags, liveKilnSchema, toKiln, toPage } from '../src/data/live';
import { describe as explainRecord, makeDraft, missingFacts } from '../src/features/complaint/draft';
// Recorded real-shape Hapur bodies, re-sanitized to a fake evidence host. Distances are
// test values from 28.7306, 77.7759; they are not the server's footprint distances.
import near from './fixtures/hapur-near.json';

const hosts = ['cdn.example.test'];
const live: Config = { mode: 'live', base: 'https://public.example.test', imageHosts: hosts, scenario: '' };
const query = { center: [77.7759, 28.7306] as [number, number], radius_m: 5000 };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
const REF = 'KW-6b3b38da681850e5af46b024f3d3f78e', ZERO = 'KW-64e53b7b965453108b2aeea524685304';
const raw = (id: string) => liveKilnSchema.parse(near.kilns.find(k => k.kiln_id === id));

describe('live adapter (real public read shape)', () => {
  it('maps a flagged record honestly: ID as name, unverified prediction, rule checks, exposure, evidence', () => {
    const k = toKiln(raw(REF), hosts);
    expect(k.name).toEqual({ en: REF, hi: REF }); expect(k.status).toBe('flagged'); expect(k.human_reviewed).toBe(false);
    expect(k.prediction.verified).toBe(false); expect(k.assessments).toEqual([]);
    const hab = k.checks!.find(c => c.rule_id === 'C-HAB-800')!;
    expect(hab).toMatchObject({ status: 'within_threshold', measured_distance_m: 497, threshold_m: 800 });
    expect(flags(k).map(c => c.rule_id)).toEqual(['C-HAB-800']);
    expect(k.exposure).toEqual({ people: 4225, radius_m: 800, source: EXPOSURE_ATTRIBUTION, estimated_at: null });
    expect(k.exposure!.source.en).toContain('HRSL');
    expect(k.evidence.before!.url).toMatch(/^https:\/\/cdn\.example\.test\/evidence\//);
    expect(k.evidence.after!.source.en).toMatch(/^Contains modified Copernicus Sentinel data/);
    expect(k.evidence.after!.outline_px).toHaveLength(4); expect(k.evidence.before!.outline_px).toBeNull();
    expect(k.footprint).toHaveLength(5); expect(k.footprint![0]).toEqual(k.footprint![4]);
  });
  it('keeps a zero-flag record partial, never clear', () => {
    const k = toKiln(raw(ZERO), hosts);
    expect(flags(k)).toEqual([]); expect(k.rules_assessment).toBe('partially_evaluated');
    expect(k.checks!.some(c => c.status === 'inconclusive')).toBe(true);
    for (const lang of ['en', 'hi'] as const) {
      const text = [explainRecord(k, lang, false), ...missingFacts(k, lang)].join(' ');
      expect(text).not.toMatch(/compliant|illegal|violation|\bclear\b/i);
    }
    expect(explainRecord(k, 'en', false)).toContain('does not mean the site passed');
  });
  it('keeps null exposure as not assessed, never zero', () => {
    const k = toKiln({ ...raw(REF), exposure: null }, hosts);
    expect(k.exposure).toBeNull(); expect(missingFacts(k, 'en')).toContain('Exposure estimate not available.');
  });
  it('preserves every rule-check status and threshold verification', () => {
    const base = raw(REF).rule_checks![0];
    const statuses = ['within_threshold', 'beyond_threshold', 'inconclusive', 'not_evaluated', 'not_applicable', 'something_new'];
    const k = toKiln({ ...raw(REF), rule_checks: statuses.map((status, i) => ({ ...base, rule_id: `R-${i}`, status, verification: i % 2 ? 'unverified_compilation' : 'secondary_sources' })) }, hosts);
    expect(k.checks!.map(c => c.status)).toEqual(statuses);
    expect(CHECK_STATUS.inconclusive[0]).toBe('Inconclusive · map data incomplete');
    expect(Object.values(CHECK_STATUS).flat().join(' ')).not.toMatch(/clear|pass|compliant|illegal/i);
    expect(k.checks!.filter(c => c.verification === 'unverified_compilation')).toHaveLength(3);
  });
  it.each([
    ['another host', 'https://other.example.test/evidence/a.png'],
    ['plain HTTP', 'http://cdn.example.test/evidence/a.png'],
    ['credentials', 'https://user:pass@cdn.example.test/evidence/a.png'],
    ['a look-alike host', 'https://cdn.example.test.evil.test/a.png'],
  ])('accepts evidence only from the configured host, not %s', (_, url) => {
    const r = raw(REF);
    const k = toKiln({ ...r, evidence: { ...r.evidence!, before: url, after: url } }, hosts);
    expect(k.evidence).toEqual({ before: null, after: null });
    expect(toKiln(r, []).evidence).toEqual({ before: null, after: null });
  });
  it('states unknown page facts instead of inventing them', () => {
    const page = toPage(near, 5000, hosts);
    expect(page).toMatchObject({ next_cursor: null, complete: true, coverage: 'unknown', updated_at: null, distance_basis: 'footprint', revision: 'unknown' });
    expect(page.items.map(i => i.kiln.id)).toContain(REF);
    expect(page.items.map(i => i.distance_m)).toEqual([...page.items.map(i => i.distance_m)].sort((a, b) => a - b));
  });
});

describe('live paging (single page, next_cursor null)', () => {
  it('sends the real near query, then refuses to page further', async () => {
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(json(near));
    const client = makeClient(live, fetcher);
    const page = await client.nearby(query, null);
    const url = new URL(String(fetcher.mock.calls[0][0]));
    expect(url.pathname).toBe('/public/kilns');
    expect(Object.fromEntries(url.searchParams)).toEqual({ lat: '28.730600', lon: '77.775900', radius_m: '5000' });
    expect(page.items).toHaveLength(4); expect(page.next_cursor).toBeNull();
    await expect(client.nearby(query, 'anything')).rejects.toMatchObject({ code: 'pagination' });
    expect(fetcher).toHaveBeenCalledOnce();
  });
  it('merges pages with no publication time only against the same unknown time', () => {
    const page = toPage(near, 5000, hosts);
    expect(mergePages(page, { ...page, items: [] }, new Set()).items).toHaveLength(4);
    expect(() => mergePages(page, { ...page, updated_at: '2026-10-11T00:00:00Z' }, new Set())).toThrow('pagination');
  });
  it('maps a non-public detail (404) to not found and never loads fixtures', async () => {
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(json({ error: { code: 'not_found', message: 'Not found' } }, 404));
    await expect(makeClient(live, fetcher).detail('KW-00c562060b40502fb4a7ed2016ce7576')).rejects.toMatchObject({ code: 'not_found' });
    expect(fetcher).toHaveBeenCalledOnce();
  });
  it.each([[400, 'malformed'], [503, 'unavailable'], [429, 'throttled']] as const)('maps %s to an error state, never fixtures', async (status, code) => {
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(new Response(JSON.stringify(status === 429 ? { message: 'Too Many Requests' } : { error: { code: 'registry_unavailable' } }), { status, headers: { 'content-type': 'application/json', 'Retry-After': '120' } }));
    await expect(makeClient(live, fetcher).nearby(query, null)).rejects.toMatchObject({ code });
  });
  it('maps a network failure to unavailable without a fixture fallback', async () => {
    const fetcher = vi.fn<typeof fetch>().mockRejectedValue(new TypeError('Failed to fetch'));
    await expect(makeClient(live, fetcher).detail(REF)).rejects.toMatchObject({ code: 'unavailable' });
  });
  it('builds a live draft from rule checks without verdict words', () => {
    const k = toKiln(raw(REF), hosts);
    const draft = makeDraft([k], { name: '', contact: '', observations: '', includeLocation: false }, 'en', null, 'http://localhost:5173', false);
    expect(draft).toContain('Siting flag pending inspection · C-HAB-800 (Distance to habitation): 497 m / threshold 800 m');
    expect(draft).toContain('Flagged by satellite · pending inspection');
    expect(draft).not.toMatch(/illegal|violation|compliant|\bclear\b/i);
  });
});

describe('Ask (POST /ask)', () => {
  const success = { answer: `${REF} has one siting flag: C-HAB-800.`, citations: [REF], steps: [{ tool: 'get_evidence', label: 'Gathering evidence', summary: 'Found', ok: true }], fallback: false, disclaimer: 'Answers cite registry records. Agents never record verdicts.' };
  it('sends one trimmed question with the kiln ID, no auth, and returns the answer', async () => {
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(json(success));
    const answer = await makeClient(live, fetcher).ask('  What should I check at this kiln?  ', REF);
    const [url, init] = fetcher.mock.calls[0];
    expect(String(url)).toBe('https://public.example.test/ask');
    expect(init).toMatchObject({ method: 'POST', credentials: 'omit', redirect: 'error' });
    expect(JSON.parse(String(init!.body))).toEqual({ question: 'What should I check at this kiln?', kiln_id: REF });
    expect(init!.headers).not.toHaveProperty('Authorization');
    expect(answer).toEqual(success);
  });
  it('omits kiln_id without a record and accepts a fallback answer', async () => {
    const fallback = { ...success, answer: 'I couldn’t produce a reliable answer to that.', fallback: true };
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(json(fallback));
    expect((await makeClient(live, fetcher).ask('How many kilns are flagged in Hapur?', null)).fallback).toBe(true);
    expect(JSON.parse(String(fetcher.mock.calls[0][1]!.body))).toEqual({ question: 'How many kilns are flagged in Hapur?' });
  });
  it.each(['', '   ', 'x'.repeat(501)])('rejects an invalid question locally without a request', async q => {
    const fetcher = vi.fn<typeof fetch>();
    await expect(makeClient(live, fetcher).ask(q, null)).rejects.toMatchObject({ kind: 'invalid' });
    expect(fetcher).not.toHaveBeenCalled();
  });
  it.each([
    [400, { error: { code: 'invalid_request', message: 'Bad', retryable: false } }, 'invalid', false],
    [429, { error: { code: 'daily_cap_reached', message: 'Cap', retryable: false } }, 'cap', false],
    [429, { message: 'Too Many Requests' }, 'busy', true],
    [503, { error: { code: 'model_unavailable', message: 'Down', retryable: true } }, 'unavailable', true],
    [503, { error: { code: 'model_unavailable', message: 'Config', retryable: false } }, 'unavailable', false],
  ] as const)('maps %s %j without retrying', async (status, body, kind, retryable) => {
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(json(body, status));
    await expect(makeClient(live, fetcher).ask('How many kilns?', null)).rejects.toMatchObject({ kind, retryable });
    expect(fetcher).toHaveBeenCalledOnce();
  });
  it('refuses Ask in fixture mode without a request', async () => {
    const fetcher = vi.fn<typeof fetch>();
    await expect(makeClient({ ...live, mode: 'fixture' }, fetcher).ask('Hello', null)).rejects.toMatchObject({ kind: 'configuration' });
    expect(fetcher).not.toHaveBeenCalled();
  });
});

import { describe, expect, it, vi } from 'vitest';
import { kilnSchema, pageSchema, safeImage, safeSource, assessed, type Page } from '../src/data/model';
import { CENTER, kilns } from '../src/data/fixtures';
import { destination, distance, parseCoordinate, ring, validateSearch } from '../src/data/geo';
import { makeClient, mergePages, type Config } from '../src/data/client';
import { exportText, makeDraft, missingFacts } from '../src/features/complaint/draft';

const fixture: Config = { mode: 'fixture', base: '', imageHosts: [], scenario: '' };
const live: Config = { mode: 'live', base: 'https://public.example.test', imageHosts: [], scenario: '' };
const query = { center: CENTER, radius_m: 1000 };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

describe('public data boundaries', () => {
  it('preserves unknown types and statuses without replacing missing facts with zero', () => {
    const k = kilnSchema.parse(kilns[3]); expect(k.status).toBe('unclassified'); expect(k.prediction.type).toBe('unclassified'); expect(k.exposure).toBeNull(); expect(k.evidence.before).toBeNull(); expect(k.assessments.every(a => !assessed(a))).toBe(true);
  });
  it.each([[181, 28], [77, 91], [NaN, 28], [77, Infinity]])('rejects invalid centroid %s,%s', (longitude, latitude) => { expect(kilnSchema.safeParse({ ...kilns[0], centroid: [longitude, latitude] }).success).toBe(false); });
  it('rejects malformed timestamps, scores, exposure, and unclosed polygons', () => {
    for (const update of [{ last_seen: '2026-10-01' }, { prediction: { ...kilns[0].prediction, score: 1.1 } }, { exposure: { people: 5 } }, { footprint: [[77, 28], [77.01, 28], [77.01, 28.01], [77, 28.01]] }]) expect(kilnSchema.safeParse({ ...kilns[0], ...update }).success).toBe(false);
  });
  it('does not turn an unknown threshold or an unapproved source into an assessment', () => {
    const a = kilns[0].assessments[0]; expect(assessed(a)).toBe(true); expect(assessed({ ...a, threshold_m: null })).toBe(false); expect(assessed({ ...a, source_url: 'https://untrusted.test/rule' })).toBe(false);
  });
  it('allows only explicit image/source hosts and excludes URL credentials', () => {
    expect(safeImage('/samples/before.svg', true, [])).toBe('/samples/before.svg');
    for (const url of ['//private.test/file', '/samples/../../private.svg', 'javascript:alert(1)', 'http://cdn.test/e.png', 'https://user:pass@cdn.test/e.png']) expect(safeImage(url, false, ['cdn.test'])).toBeUndefined();
    expect(safeImage('https://cdn.test/e.png', false, ['cdn.test'])).toBe('https://cdn.test/e.png');
    expect(safeSource('https://mpcb.gov.in.evil.test')).toBeUndefined();
  });
  it('rejects contradictory pagination metadata', () => { expect(pageSchema.safeParse({ items: [], next_cursor: 'next', complete: true, revision: '1', coverage: 'known', updated_at: kilns[0].last_seen, distance_basis: 'centroid' }).success).toBe(false); });
});

describe('geography and nearby reads', () => {
  it('uses longitude/latitude and a geodesic circle of the requested radius', () => {
    expect(distance([0, 0], [1, 0])).toBeCloseTo(111195.08, 1);
    const points = ring(CENTER, 800); expect(points).toHaveLength(65);
    for (const p of points) expect(distance(CENTER, p)).toBeCloseTo(800, 4);
    expect(destination(CENTER, 1000, 90)[0]).toBeGreaterThan(CENTER[0]);
  });
  it('accepts Devanagari digits but rejects blank or ambiguous coordinates', () => {
    expect(parseCoordinate('२८.७३')).toBe(28.73); expect(parseCoordinate('77.68')).toBe(77.68);
    for (const value of ['', ' ', '28,73', '1e5', '0x20']) expect(Number.isNaN(parseCoordinate(value))).toBe(true);
    expect(validateSearch({ center: CENTER, radius_m: 999999 })).toBe(false);
  });
  it('filters the whole fixture collection before paging and labels distance basis', async () => {
    const c = makeClient(fixture); const first = await c.nearby(query, null); const second = await c.nearby(query, first.next_cursor);
    expect(first.items).toHaveLength(3); expect(first.complete).toBe(false); expect(second.complete).toBe(true);
    const combined = mergePages(first, second, new Set([first.next_cursor!])); expect(combined.items).toHaveLength(6); expect(combined.distance_basis).toBe('centroid');
    expect(combined.items.every(i => i.distance_m <= 1000)).toBe(true);
    expect(combined.items[0].distance_m).not.toBe(combined.items[0].kiln.assessments[0].measured_distance_m);
  });
  it('distinguishes known empty coverage from unknown coverage', async () => {
    expect((await makeClient({ ...fixture, scenario: 'empty' }).nearby(query, null)).coverage).toBe('known');
    const unknown = await makeClient(fixture).nearby({ center: [0, 0], radius_m: 1000 }, null); expect(unknown.coverage).toBe('unknown'); expect(unknown.items).toEqual([]);
  });
  it('deduplicates pages and refuses repeated cursors or revision changes', async () => {
    const first = await makeClient(fixture).nearby(query, null);
    const next: Page = { ...first, next_cursor: null, complete: true }; expect(mergePages(first, next, new Set(['3'])).items).toHaveLength(3);
    expect(() => mergePages(first, first, new Set(['3']))).toThrow('pagination'); expect(() => mergePages(first, { ...next, revision: 'new' }, new Set())).toThrow('pagination');
  });
  it('cancels a superseded fixture read', async () => {
    const abort = new AbortController(); const result = makeClient(fixture).nearby(query, null, abort.signal); abort.abort(); await expect(result).rejects.toMatchObject({ name: 'AbortError' });
  });
});

describe('live client refuses sample recovery', () => {
  it('retains a 503 after one bounded retry, sends no credentials, and never returns fixtures', async () => {
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(json({ error: { code: 'publication_unavailable' } }, 503));
    await expect(makeClient(live, fetcher).nearby(query, null)).rejects.toMatchObject({ code: 'unavailable' });
    expect(fetcher).toHaveBeenCalledTimes(2); expect(fetcher.mock.calls[0][1]).toMatchObject({ credentials: 'omit', cache: 'no-store' });
    expect(fetcher.mock.calls[0][1]?.headers).toEqual({ Accept: 'application/json' });
  });
  it.each([null, { items: 'bad' }, { kiln: kilns[0] }])('rejects malformed live payload %j without retries', async body => {
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(json(body)); await expect(makeClient(live, fetcher).nearby(query, null)).rejects.toMatchObject({ code: 'malformed' }); expect(fetcher).toHaveBeenCalledTimes(1);
  });
  it('does not accept the wrong detail ID or retry a non-disclosing 404', async () => {
    await expect(makeClient(live, vi.fn<typeof fetch>().mockResolvedValue(json(kilns[1]))).detail(kilns[0].id)).rejects.toMatchObject({ code: 'malformed' });
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(json({}, 404)); await expect(makeClient(live, fetcher).detail('SAMPLE-MISSING')).rejects.toMatchObject({ code: 'not_found' }); expect(fetcher).toHaveBeenCalledTimes(1);
  });
  it('fails unconfigured live mode without making any request', async () => {
    const fetcher = vi.fn<typeof fetch>(); await expect(makeClient({ ...live, base: '' }, fetcher).nearby(query, null)).rejects.toMatchObject({ code: 'configuration' }); expect(fetcher).not.toHaveBeenCalled();
  });
  it('respects long Retry-After instead of aggressively retrying', async () => {
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(new Response('', { status: 429, headers: { 'Retry-After': '120' } })); await expect(makeClient(live, fetcher).nearby(query, null)).rejects.toMatchObject({ code: 'throttled' }); expect(fetcher).toHaveBeenCalledTimes(1);
  });
});

describe('inspection drafting', () => {
  const fields = { name: '', contact: '', observations: 'Test observation only', includeLocation: false };
  it.each(['en', 'hi'] as const)('creates an honest %s draft with no resident location by default', lang => {
    const draft = makeDraft([kilns[0], kilns[3]], fields, lang, [72.12345, 20.98765], 'http://localhost:5173', true);
    expect(draft).toContain(kilns[0].id); expect(draft).toContain(kilns[3].id); expect(draft).not.toContain('20.98765'); expect(draft).not.toContain('72.12345'); expect(draft).toContain('Test observation only'); expect(draft).not.toMatch(/illegal|Complaint filed/);
    expect(exportText(draft, lang, true)).toContain(lang === 'hi' ? 'नमूना डेटा' : 'SAMPLE DATA');
  });
  it('includes exact location only after opt-in and keeps edited text in exports', () => {
    expect(makeDraft([kilns[0]], { ...fields, includeLocation: true }, 'en', [72.12345, 20.98765], 'http://localhost', true)).toContain('20.98765, 72.12345');
    expect(exportText('My edited request', 'en', true)).toContain('My edited request');
  });
  it('does not generate a rule conclusion from missing measurements', () => {
    const draft = makeDraft([kilns[3]], fields, 'en', null, 'http://localhost', true); expect(draft).not.toContain('threshold 800'); expect(missingFacts(kilns[3], 'en')).toContain('Exposure estimate not available.');
  });
});

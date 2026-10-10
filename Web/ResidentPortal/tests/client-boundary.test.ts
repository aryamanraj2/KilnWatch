import { afterEach, describe, expect, it, vi } from 'vitest';
import { makeClient, mergePages, type Config } from '../src/data/client';
import { CENTER, kilns, UPDATED } from '../src/data/fixtures';
import type { Page } from '../src/data/model';

const live: Config = { mode: 'live', base: 'https://public.example.test', imageHosts: [], scenario: '' };
const query = { center: CENTER, radius_m: 1000 };
const headers = { 'content-type': 'application/json' };
const json = (data: unknown) => new Response(JSON.stringify(data), { headers });
const first: Page = { items: [{ kiln: kilns[0], distance_m: 300 }], next_cursor: 'next', complete: false,
  revision: 'test-dataset-1', coverage: 'known', updated_at: UPDATED, distance_basis: 'centroid' };
const next: Page = { ...first, items: [{ kiln: kilns[1], distance_m: 400 }], next_cursor: null, complete: true };
afterEach(() => vi.useRealTimers());

describe('bounded public response reading', () => {
  it('cancels oversized declared responses before reading their body', async () => {
    const cancel = vi.fn();
    const response = new Response(new ReadableStream({ cancel }), { headers: { ...headers, 'content-length': '1000001' } });
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(response);
    await expect(makeClient(live, fetcher).detail(kilns[0].id)).rejects.toMatchObject({ code: 'malformed' });
    expect(cancel).toHaveBeenCalledOnce(); expect(response.bodyUsed).toBe(true); expect(fetcher).toHaveBeenCalledOnce();
  });
  it.each([undefined, '1'])('stops an oversized stream even when Content-Length is %s', async length => {
    const cancel = vi.fn(); const pull = vi.fn((controller: ReadableStreamDefaultController<Uint8Array>) => controller.enqueue(new Uint8Array(600_000).fill(32)));
    const response = new Response(new ReadableStream({ pull, cancel }), { headers: { ...headers, ...(length ? { 'content-length': length } : {}) } });
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(response);
    await expect(makeClient(live, fetcher).detail(kilns[0].id)).rejects.toMatchObject({ code: 'malformed' });
    expect(cancel).toHaveBeenCalledOnce(); expect(pull.mock.calls.length).toBeLessThanOrEqual(3); expect(fetcher).toHaveBeenCalledOnce();
  });
  it('counts UTF-8 bytes rather than JavaScript string characters', async () => {
    const body = JSON.stringify({ ...kilns[0], name: { en: 'Test', hi: 'आ'.repeat(350_000) } });
    expect(body.length).toBeLessThan(1_000_000); expect(new TextEncoder().encode(body).length).toBeGreaterThan(1_000_000);
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(new Response(body, { headers }));
    await expect(makeClient(live, fetcher).detail(kilns[0].id)).rejects.toMatchObject({ code: 'malformed' });
    expect(fetcher).toHaveBeenCalledOnce();
  });
  it('decodes Hindi correctly when a character spans response chunks', async () => {
    const record = { ...kilns[0], name: { en: 'Test record', hi: 'निरीक्षण' } };
    const bytes = new TextEncoder().encode(JSON.stringify(record));
    const split = bytes.indexOf(0xe0) + 1;
    const response = new Response(new ReadableStream({ start(controller) {
      controller.enqueue(bytes.slice(0, split)); controller.enqueue(bytes.slice(split, split + 1));
      controller.enqueue(bytes.slice(split + 1)); controller.close();
    } }), { headers });
    expect((await makeClient(live, vi.fn<typeof fetch>().mockResolvedValue(response)).detail(record.id)).name.hi).toBe(record.name.hi);
  });
  it('rejects invalid UTF-8 instead of replacing corrupt characters', async () => {
    const bytes = new Uint8Array([0x7b, 0x22, 0xff, 0x22, 0x3a, 0x31, 0x7d]);
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(new Response(bytes, { headers }));
    await expect(makeClient(live, fetcher).detail(kilns[0].id)).rejects.toMatchObject({ code: 'malformed' });
    expect(fetcher).toHaveBeenCalledOnce();
  });
  it('passes redirect refusal to Fetch so search requests cannot follow another destination', async () => {
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(json(first));
    await makeClient(live, fetcher).nearby(query, null);
    expect(fetcher.mock.calls[0][1]).toMatchObject({ redirect: 'error', credentials: 'omit', referrerPolicy: 'no-referrer' });
  });
  it.each(['cancel', 'timeout'] as const)('retains %s behavior during body streaming', async action => {
    vi.useFakeTimers(); const abort = new AbortController();
    const fetcher = vi.fn<typeof fetch>().mockImplementation(async (_url, options) => new Response(new ReadableStream({ start(controller) {
      options?.signal?.addEventListener('abort', () => controller.error(new DOMException('Aborted', 'AbortError')), { once: true });
    } }), { headers }));
    const pending = makeClient(live, fetcher).detail(kilns[0].id, abort.signal);
    const assertion = expect(pending).rejects.toMatchObject(action === 'cancel' ? { name: 'AbortError' } : { code: 'timeout' });
    await vi.advanceTimersByTimeAsync(1);
    if (action === 'cancel') abort.abort(); else await vi.advanceTimersByTimeAsync(10_000);
    await assertion; expect(fetcher).toHaveBeenCalledOnce();
  });
});

describe('consistent nearby result sets', () => {
  it('deduplicates the first page and rejects conflicting copies within that page', async () => {
    const fetcher = vi.fn<typeof fetch>().mockResolvedValueOnce(json({ ...first, items: [first.items[0], first.items[0]] }))
      .mockResolvedValueOnce(json({ ...first, items: [first.items[0], { ...first.items[0], kiln: { ...kilns[0], revision: 'conflicting' } }] }));
    expect((await makeClient(live, fetcher).nearby(query, null)).items).toHaveLength(1);
    await expect(makeClient(live, fetcher).nearby(query, null)).rejects.toMatchObject({ code: 'malformed' });
  });
  it.each(['order', 'id-tie', 'radius'] as const)('rejects a first page with invalid %s', async variant => {
    const items = variant === 'order' ? [next.items[0], first.items[0]] : variant === 'id-tie'
      ? [{ ...next.items[0], distance_m: 300 }, first.items[0]] : [{ ...first.items[0], distance_m: 1001 }];
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(json({ ...first, items }));
    await expect(makeClient(live, fetcher).nearby(query, null)).rejects.toMatchObject({ code: 'malformed' });
    expect(fetcher).toHaveBeenCalledOnce();
  });
  it('rejects changed snapshot time and an earlier unseen record on a later page', () => {
    expect(() => mergePages(first, { ...next, updated_at: '2026-10-02T06:00:00Z' }, new Set())).toThrow('pagination');
    expect(() => mergePages(first, { ...next, items: [{ ...next.items[0], distance_m: 200 }] }, new Set())).toThrow('pagination');
    expect(first.items[0].distance_m).toBe(300);
  });
  it.each(['distance', 'revision'] as const)('rejects overlapping records with changed %s', variant => {
    const duplicate = { ...first.items[0], distance_m: variant === 'distance' ? 310 : 300,
      kiln: { ...first.items[0].kiln, revision: variant === 'revision' ? 'changed-record' : first.items[0].kiln.revision } };
    expect(() => mergePages(first, { ...next, items: [duplicate] }, new Set())).toThrow('pagination');
  });
  it('keeps loaded records on overlap and accepts equivalent timestamp offsets', () => {
    const duplicate = { ...first.items[0], kiln: { ...first.items[0].kiln, name: { en: 'Changed label', hi: 'बदला नाम' } } };
    const result = mergePages(first, { ...next, items: [duplicate, ...next.items], updated_at: '2026-10-01T11:30:00+05:30' }, new Set());
    expect(result.items).toHaveLength(2); expect(result.items[0]).toBe(first.items[0]); expect(result.items[1]).toBe(next.items[0]);
  });
});

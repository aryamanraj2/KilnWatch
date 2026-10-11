import { describe, expect, it, vi } from 'vitest';
import recorded from './fixtures/requests-recorded.json';
import near from './fixtures/hapur-near.json';
import { makeClient, type Config } from '../src/data/client';
import { liveKilnSchema, toKiln } from '../src/data/live';
import { browserCode, rememberRequest, requestResponseSchema, residentRequestsSchema, sentOn, zeroRequests, type RequestBody } from '../src/data/requests';

const cfg: Config = { mode: 'live', base: 'https://public.example.test', imageHosts: [], scenario: '' };
const body: RequestBody = { kiln_id: recorded.kiln_id, client_id: 'a80d2cb8-9e91-4dfd-96fd-a3d6d4c24aa1', concerns: ['smoke_or_ash', 'near_homes'], distance_band: 'under_1km', lang: 'en' };
describe('inspection request contract', () => {
  it('maps the shared recorded aggregate through a public kiln and retains older records', () => {
    const raw = { ...near.kilns[0], resident_requests: recorded.resident_requests };
    expect(toKiln(liveKilnSchema.parse(raw), []).resident_requests).toEqual(recorded.resident_requests);
    expect(toKiln(liveKilnSchema.parse(near.kilns[0]), []).resident_requests).toBeUndefined();
    expect(residentRequestsSchema.parse(zeroRequests()).count).toBe(0);
    expect(requestResponseSchema.parse(recorded)).toEqual(recorded);
  });
  it('sends only the frozen body without auth, cookies, redirects or retries', async () => {
    const fetcher = vi.fn().mockResolvedValue(new Response(JSON.stringify(recorded), { status: 201, headers: { 'content-type': 'application/json' } }));
    expect(await makeClient(cfg, fetcher).request(body)).toEqual(recorded);
    expect(fetcher).toHaveBeenCalledTimes(1);
    expect(fetcher.mock.calls[0][1]).toMatchObject({ method: 'POST', credentials: 'omit', cache: 'no-store', redirect: 'error', referrerPolicy: 'no-referrer' });
    expect(JSON.parse(fetcher.mock.calls[0][1].body)).toEqual(body);
    expect(fetcher.mock.calls[0][1].headers.Authorization).toBeUndefined();
  });
  it('accepts a duplicate acknowledgement with a fresh aggregate', async () => {
    const duplicate = { ...recorded, created: false };
    const fetcher = vi.fn().mockResolvedValue(new Response(JSON.stringify(duplicate), { status: 200, headers: { 'content-type': 'application/json' } }));
    expect(await makeClient(cfg, fetcher).request(body)).toEqual(duplicate);
  });
  it.each([[429, 'daily_cap_reached', 'cap'], [429, 'throttle', 'busy'], [503, 'registry_unavailable', 'unavailable'], [404, 'not_found', 'not_found'], [400, 'invalid_request', 'invalid']] as const)('preserves %s error semantics with no retry', async (status, code, kind) => {
    const fetcher = vi.fn().mockResolvedValue(new Response(JSON.stringify({ error: { code, retryable: true } }), { status, headers: { 'content-type': 'application/json' } }));
    await expect(makeClient(cfg, fetcher).request(body)).rejects.toMatchObject({ kind }); expect(fetcher).toHaveBeenCalledTimes(1);
  });
  it('handles network failure without automatically repeating a write', async () => {
    const fetcher = vi.fn().mockRejectedValue(new TypeError('Network unavailable'));
    await expect(makeClient(cfg, fetcher).request(body)).rejects.toMatchObject({ kind: 'unavailable' }); expect(fetcher).toHaveBeenCalledTimes(1);
  });
  it('rejects a wrong kiln acknowledgement and invalid aggregates', async () => {
    const fetcher = vi.fn().mockResolvedValue(new Response(JSON.stringify({ ...recorded, kiln_id: 'KW-ffffffffffffffffffffffffffffffff' }), { status: 201, headers: { 'content-type': 'application/json' } }));
    await expect(makeClient(cfg, fetcher).request(body)).rejects.toMatchObject({ kind: 'unavailable' });
    expect(residentRequestsSchema.safeParse({ ...recorded.resident_requests, within_1km: 13 }).success).toBe(false);
  });
  it('keeps one browser code and records sent dates when storage is denied', () => {
    const read = vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => { throw new Error('Denied'); });
    const write = vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => { throw new Error('Denied'); });
    const code = browserCode('denied-test'); expect(browserCode('denied-test')).toBe(code);
    rememberRequest('denied-test', body.kiln_id, recorded.resident_requests);
    expect(sentOn('denied-test', body.kiln_id)).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    read.mockRestore(); write.mockRestore();
  });
  it('simulates sample requests without calling a network transport', async () => {
    const fetcher = vi.fn(); const sample = makeClient({ ...cfg, mode: 'fixture' }, fetcher);
    const request = { ...body, kiln_id: 'SAMPLE-KW-001' };
    const first = await sample.request(request); expect(first.created).toBe(true); expect(first.resident_requests.count).toBe(13);
    const repeat = await sample.request(request); expect(repeat.created).toBe(false); expect(repeat.resident_requests.count).toBe(13);
    const another = await sample.request({ ...request, client_id: 'b80d2cb8-9e91-4dfd-96fd-a3d6d4c24aa1' }); expect(another.resident_requests.count).toBe(14);
    const freshReplay = await sample.request(request); expect(freshReplay.created).toBe(false); expect(freshReplay.resident_requests.count).toBe(14);
    expect(fetcher).not.toHaveBeenCalled();
  });
});

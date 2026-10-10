import { DataError, kilnSchema, pageSchema, ruleSchema, type Kiln, type Page, type Rule, type Search } from './model';
import { distance, validateSearch } from './geo';

export type Config = { mode: 'fixture' | 'live' | 'invalid'; base: string; imageHosts: string[]; scenario: string };
export const config: Config = {
  mode: !import.meta.env.VITE_DATA_MODE || import.meta.env.VITE_DATA_MODE === 'fixture' ? 'fixture' : import.meta.env.VITE_DATA_MODE === 'live' ? 'live' : 'invalid',
  base: import.meta.env.VITE_PUBLIC_API_BASE_URL ?? '',
  imageHosts: (import.meta.env.VITE_PUBLIC_IMAGE_HOSTS ?? '').split(',').map((s: string) => s.trim()).filter(Boolean),
  scenario: import.meta.env.DEV ? import.meta.env.VITE_FIXTURE_SCENARIO || new URLSearchParams(window.location.search).get('demo') || '' : '',
};
export function abortableDelay(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) { reject(new DOMException('Aborted', 'AbortError')); return; }
    const abort = () => { clearTimeout(timer); reject(new DOMException('Aborted', 'AbortError')); };
    const timer = setTimeout(() => { signal?.removeEventListener('abort', abort); resolve(); }, ms);
    signal?.addEventListener('abort', abort, { once: true });
  });
}
export function makeClient(cfg: Config, fetcher: typeof fetch = fetch) {
  async function read(path: string, signal?: AbortSignal): Promise<unknown> {
    let base: URL;
    try { base = new URL(cfg.base); } catch { throw new DataError('configuration'); }
    if (cfg.mode !== 'live' || base.protocol !== 'https:' || base.username || base.password || base.search || base.hash) throw new DataError('configuration');
    for (let attempt = 0; attempt < 2; attempt++) {
      const controller = new AbortController();
      const abort = () => controller.abort();
      signal?.addEventListener('abort', abort, { once: true });
      if (signal?.aborted) controller.abort();
      let timedOut = false;
      const timer = setTimeout(() => { timedOut = true; controller.abort(); }, 10000);
      try {
        const res = await fetcher(`${base.href.replace(/\/$/, '')}${path}`, { signal: controller.signal, credentials: 'omit', cache: 'no-store', referrerPolicy: 'no-referrer', headers: { Accept: 'application/json' } });
        if (res.status === 404) throw new DataError('not_found');
        if (!res.ok) {
          if (attempt === 0 && [408, 429, 502, 503, 504].includes(res.status)) {
            const retry = res.headers.get('Retry-After');
            const seconds = retry && /^\d+$/.test(retry) ? Number(retry) : retry ? (Date.parse(retry) - Date.now()) / 1000 : 0.3;
            if (!Number.isFinite(seconds) || seconds > 2) throw new DataError(res.status === 429 ? 'throttled' : 'unavailable');
            await abortableDelay(Math.max(300, seconds * 1000), signal); continue;
          }
          throw new DataError(res.status === 429 ? 'throttled' : 'unavailable');
        }
        if (!res.headers.get('content-type')?.includes('application/json')) throw new DataError('malformed');
        const body = await res.text();
        if (body.length > 1_000_000) throw new DataError('malformed');
        try { return JSON.parse(body); } catch { throw new DataError('malformed'); }
      } catch (e) {
        if (signal?.aborted) throw new DOMException('Aborted', 'AbortError');
        if (timedOut) throw new DataError('timeout');
        if (e instanceof DataError) throw e;
        throw new DataError('unavailable');
      } finally { clearTimeout(timer); signal?.removeEventListener('abort', abort); }
    }
    throw new DataError('unavailable');
  }
  async function fixtures(signal?: AbortSignal) {
    if (cfg.mode !== 'fixture') throw new DataError('configuration');
    await abortableDelay(180, signal);
    if (cfg.scenario === 'unavailable') throw new DataError('unavailable');
    if (cfg.scenario === 'malformed') throw new DataError('malformed');
    return import('./fixtures');
  }
  return {
    async nearby(query: Search, cursor: string | null, signal?: AbortSignal): Promise<Page> {
      if (!validateSearch(query)) throw new DataError('malformed');
      if (cfg.mode === 'fixture') {
        const f = await fixtures(signal);
        if (cursor && cfg.scenario === 'partial') throw new DataError('unavailable');
        const offset = Number(cursor ?? 0);
        if (!Number.isInteger(offset) || offset < 0 || offset > 100) throw new DataError('pagination');
        const known = distance(f.CENTER, query.center) + query.radius_m <= 5500 && cfg.scenario !== 'unknown';
        const hits = cfg.scenario === 'empty' || cfg.scenario === 'unknown' ? [] : f.kilns.map(kiln => ({ kiln, distance_m: distance(query.center, kiln.centroid) })).filter(x => x.distance_m <= query.radius_m).sort((a, b) => a.distance_m - b.distance_m || a.kiln.id.localeCompare(b.kiln.id));
        const next = offset + 3 < hits.length ? String(offset + 3) : null;
        return { items: hits.slice(offset, offset + 3), next_cursor: next, complete: !next, revision: 'sample-1', coverage: known ? 'known' : 'unknown', updated_at: cfg.scenario === 'stale' ? '2025-01-01T00:00:00Z' : f.UPDATED, distance_basis: 'centroid' };
      }
      const params = new URLSearchParams({ longitude: String(query.center[0]), latitude: String(query.center[1]), radius_m: String(query.radius_m), limit: '3', ...(cursor ? { cursor } : {}) });
      const result = pageSchema.safeParse(await read(`/public/kilns?${params}`, signal));
      if (!result.success) throw new DataError('malformed');
      return result.data;
    },
    async detail(id: string, signal?: AbortSignal): Promise<Kiln> {
      if (!/^[A-Za-z0-9-]{1,100}$/.test(id)) throw new DataError('not_found');
      if (cfg.mode === 'fixture') { const f = await fixtures(signal); const k = f.kilns.find(k => k.id === id); if (!k) throw new DataError('not_found'); return k; }
      const result = kilnSchema.safeParse(await read(`/public/kilns/${encodeURIComponent(id)}`, signal));
      if (!result.success || result.data.id !== id) throw new DataError('malformed');
      return result.data;
    },
    async rule(id: string, signal?: AbortSignal): Promise<Rule> {
      if (!/^[A-Za-z0-9-]{1,100}$/.test(id)) throw new DataError('not_found');
      if (cfg.mode === 'fixture') { const f = await fixtures(signal); const r = f.rules.find(r => r.id === id); if (!r) throw new DataError('not_found'); return r; }
      const result = ruleSchema.safeParse(await read(`/public/rules/${encodeURIComponent(id)}`, signal));
      if (!result.success || result.data.id !== id) throw new DataError('malformed');
      return result.data;
    },
  };
}
export const client = makeClient(config);
export function mergePages(previous: Page, next: Page, seenCursors: Set<string>): Page {
  if (previous.revision !== next.revision || previous.coverage !== next.coverage || (next.next_cursor && seenCursors.has(next.next_cursor)) || (!next.items.length && next.next_cursor)) throw new DataError('pagination');
  const items = [...new Map([...previous.items, ...next.items].map(i => [i.kiln.id, i])).values()];
  if (items.length > 100) throw new DataError('pagination');
  return { ...next, items };
}

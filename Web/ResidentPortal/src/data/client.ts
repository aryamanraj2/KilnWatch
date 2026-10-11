import { DataError, type Kiln, type Page, type Rule, type Search } from './model';
import { distance, validateSearch } from './geo';
import { askError, AskError, askSchema, liveKilnSchema, toKiln, toPage, type AskAnswer } from './live';

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
async function readJSON(response: Response): Promise<unknown> {
  const limit = 1_000_000; // Decoded response bytes, including UTF-8 Hindi text.
  const declaredSize = Number(response.headers.get('content-length'));
  if (declaredSize > limit || !response.body) {
    await response.body?.cancel().catch(() => {});
    throw new DataError('malformed');
  }
  const reader = response.body.getReader();
  const decoder = new TextDecoder('utf-8', { fatal: true });
  const parts: string[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) throw new DataError('malformed');
      try { parts.push(decoder.decode(value, { stream: true })); }
      catch { throw new DataError('malformed'); }
    }
    try { return JSON.parse(parts.join('') + decoder.decode()); }
    catch { throw new DataError('malformed'); }
  } catch (error) {
    await reader.cancel().catch(() => {});
    throw error;
  } finally { reader.releaseLock(); }
}
function compareResults(a: Page['items'][number], b: Page['items'][number]): number {
  return a.distance_m - b.distance_m || (a.kiln.id < b.kiln.id ? -1 : a.kiln.id > b.kiln.id ? 1 : 0);
}
function ordered(items: Page['items']): boolean {
  return items.every((item, index) => index === 0 || compareResults(items[index - 1], item) <= 0);
}
function appendItems(previous: Page['items'], next: Page['items']): Page['items'] {
  const byId = new Map<string, Page['items'][number]>();
  for (const item of [...previous, ...next]) {
    const existing = byId.get(item.kiln.id);
    if (existing) {
      if (existing.distance_m !== item.distance_m || existing.kiln.revision !== item.kiln.revision) throw new DataError('pagination');
      continue; // Keep the already displayed record when pages overlap.
    }
    byId.set(item.kiln.id, item);
  }
  const items = [...byId.values()];
  if (items.length > 100 || !ordered(items)) throw new DataError('pagination');
  return items;
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
        const res = await fetcher(`${base.href.replace(/\/$/, '')}${path}`, { signal: controller.signal, credentials: 'omit', cache: 'no-store', redirect: 'error', referrerPolicy: 'no-referrer', headers: { Accept: 'application/json' } });
        if (res.status === 404) throw new DataError('not_found');
        if (res.status === 400) throw new DataError('malformed');
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
        return await readJSON(res);
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
        const hits = cfg.scenario === 'empty' || cfg.scenario === 'unknown' ? [] : f.kilns.map(kiln => ({ kiln, distance_m: distance(query.center, kiln.centroid) })).filter(x => x.distance_m <= query.radius_m).sort(compareResults);
        const next = offset + 3 < hits.length ? String(offset + 3) : null;
        return { items: hits.slice(offset, offset + 3), next_cursor: next, complete: !next, revision: 'sample-1', coverage: known ? 'known' : 'unknown', updated_at: cfg.scenario === 'stale' ? '2025-01-01T00:00:00Z' : f.UPDATED, distance_basis: 'centroid' };
      }
      // The real near query is one page (next_cursor null); there is nothing to continue.
      if (cursor) throw new DataError('pagination');
      const params = new URLSearchParams({ lat: query.center[1].toFixed(6), lon: query.center[0].toFixed(6), radius_m: String(query.radius_m) });
      const body = await read(`/public/kilns?${params}`, signal);
      try { const page = toPage(body, query.radius_m, cfg.imageHosts); return { ...page, items: appendItems([], page.items) }; }
      catch { throw new DataError('malformed'); }
    },
    async detail(id: string, signal?: AbortSignal): Promise<Kiln> {
      if (!/^[A-Za-z0-9-]{1,100}$/.test(id)) throw new DataError('not_found');
      if (cfg.mode === 'fixture') { const f = await fixtures(signal); const k = f.kilns.find(k => k.id === id); if (!k) throw new DataError('not_found'); if (cfg.scenario === 'image-error') return { ...k, evidence: { before: null, after: k.evidence.after && { ...k.evidence.after, url: '/samples/unavailable.svg' } } }; return k; }
      const result = liveKilnSchema.safeParse(await read(`/public/kilns/${encodeURIComponent(id)}`, signal));
      if (!result.success || result.data.kiln_id !== id) throw new DataError('malformed');
      try { return toKiln(result.data, cfg.imageHosts); } catch { throw new DataError('malformed'); }
    },
    async rule(id: string, signal?: AbortSignal): Promise<Rule> {
      if (!/^[A-Za-z0-9-]{1,100}$/.test(id)) throw new DataError('not_found');
      if (cfg.mode === 'fixture') { const f = await fixtures(signal); const r = f.rules.find(r => r.id === id); if (!r) throw new DataError('not_found'); return r; }
      // The real API has no rule route; live rule pages are built from a kiln's rule_checks.
      throw new DataError('configuration');
    },
    // POST /ask: one request, never retried automatically. Rejects with AskError.
    async ask(question: string, kilnId: string | null, signal?: AbortSignal): Promise<AskAnswer> {
      let base: URL;
      try { base = new URL(cfg.base); } catch { throw new AskError('configuration', false); }
      if (cfg.mode !== 'live' || base.protocol !== 'https:' || base.username || base.password || base.search || base.hash) throw new AskError('configuration', false);
      const trimmed = question.trim();
      if (!trimmed || trimmed.length > 500) throw new AskError('invalid', false);
      const controller = new AbortController();
      const abort = () => controller.abort();
      signal?.addEventListener('abort', abort, { once: true });
      const timer = setTimeout(abort, 35000); // The server budget is 28 s.
      try {
        const res = await fetcher(`${base.href.replace(/\/$/, '')}/ask`, { method: 'POST', signal: controller.signal, credentials: 'omit', cache: 'no-store', redirect: 'error', referrerPolicy: 'no-referrer',
          headers: { Accept: 'application/json', 'Content-Type': 'application/json' }, body: JSON.stringify({ question: trimmed, ...(kilnId ? { kiln_id: kilnId } : {}) }) });
        let body: unknown = null;
        try { body = await readJSON(res); } catch { /* Error bodies may be empty or non-JSON. */ }
        if (!res.ok) throw askError(res.status, body);
        const answer = askSchema.safeParse(body);
        if (!answer.success) throw new AskError('malformed', true);
        return answer.data;
      } catch (e) {
        if (signal?.aborted) throw new DOMException('Aborted', 'AbortError');
        if (e instanceof AskError) throw e;
        throw new AskError('network', true);
      } finally { clearTimeout(timer); signal?.removeEventListener('abort', abort); }
    },
  };
}
export const client = makeClient(config);
export function mergePages(previous: Page, next: Page, seenCursors: Set<string>): Page {
  const sameTime = previous.updated_at === null || next.updated_at === null ? previous.updated_at === next.updated_at : Date.parse(previous.updated_at) === Date.parse(next.updated_at);
  if (previous.revision !== next.revision || previous.coverage !== next.coverage || previous.distance_basis !== next.distance_basis || !sameTime || (next.next_cursor && seenCursors.has(next.next_cursor)) || (!next.items.length && next.next_cursor) || !ordered(previous.items) || !ordered(next.items)) throw new DataError('pagination');
  const items = appendItems(previous.items, next.items);
  return { ...next, items };
}

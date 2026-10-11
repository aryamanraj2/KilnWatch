import { z } from 'zod';

export const concernValues = ['smoke_or_ash', 'near_homes', 'near_school_or_hospital', 'other'] as const;
export const distanceValues = ['under_1km', '1_to_5km', 'over_5km', 'not_said'] as const;
export const residentRequestsSchema = z.object({
  count: z.number().int().nonnegative(), within_1km: z.number().int().nonnegative(),
  concerns: z.object({ smoke_or_ash: z.number().int().nonnegative(), near_homes: z.number().int().nonnegative(), near_school_or_hospital: z.number().int().nonnegative(), other: z.number().int().nonnegative() }),
  last_request_on: z.iso.date().nullable(),
}).refine(r => r.within_1km <= r.count && Object.values(r.concerns).every(n => n <= r.count) && (r.count === 0 ? r.last_request_on === null : r.last_request_on !== null));
export type ResidentRequests = z.infer<typeof residentRequestsSchema>;
export const requestBodySchema = z.object({ kiln_id: z.string().regex(/^KW-[0-9a-f]{32}$/), client_id: z.uuidv4(), concerns: z.array(z.enum(concernValues)).min(1).max(4).refine(v => new Set(v).size === v.length), distance_band: z.enum(distanceValues), lang: z.enum(['en', 'hi']) }).strict();
export type RequestBody = z.infer<typeof requestBodySchema>;
export const requestResponseSchema = z.object({ kiln_id: z.string().regex(/^KW-[0-9a-f]{32}$/), created: z.boolean(), resident_requests: residentRequestsSchema });
export type RequestResponse = z.infer<typeof requestResponseSchema>;
export class RequestError extends Error {
  constructor(public kind: 'cap' | 'busy' | 'not_found' | 'unavailable' | 'invalid') { super(kind); }
}
export const zeroRequests = (): ResidentRequests => ({ count: 0, within_1km: 0, concerns: { smoke_or_ash: 0, near_homes: 0, near_school_or_hospital: 0, other: 0 }, last_request_on: null });

// Sample storage is isolated from real browser requests. Storage denial falls back to this document.
const browserCodes = new Map<string, string>();
const sent = new Map<string, string>();
const fresh = new Map<string, { value: ResidentRequests; until: number }>();
const listeners = new Set<() => void>();
export function subscribeRequests(listener: () => void) { listeners.add(listener); return () => { listeners.delete(listener); }; }
export function freshRequests(mode: string, id: string) {
  const entry = fresh.get(`${mode}:${id}`);
  return entry && entry.until >= Date.now() ? entry.value : undefined;
}
export function browserCode(mode: string): string {
  const key = `kw-requests-${mode}-client`;
  if (browserCodes.has(key)) return browserCodes.get(key)!;
  let code: string | null = null;
  try { code = localStorage.getItem(key); } catch { /* Memory fallback. */ }
  if (!z.uuidv4().safeParse(code).success) code = crypto.randomUUID();
  browserCodes.set(key, code!);
  try { localStorage.setItem(key, code!); } catch { /* Memory fallback. */ }
  return code!;
}
export function sentOn(mode: string, id: string): string | null {
  const key = `kw-requests-${mode}-sent-${id}`;
  if (sent.has(key)) return sent.get(key)!;
  try { const value = localStorage.getItem(key); if (z.iso.date().safeParse(value).success) { sent.set(key, value!); return value; } } catch { /* Memory fallback. */ }
  return null;
}
export function rememberRequest(mode: string, id: string, result: ResidentRequests) {
  const key = `kw-requests-${mode}-sent-${id}`;
  const day = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
  sent.set(key, day); fresh.set(`${mode}:${id}`, { value: result, until: Date.now() + 120000 });
  try { localStorage.setItem(key, day); } catch { /* Memory fallback. */ }
  listeners.forEach(listener => listener());
}

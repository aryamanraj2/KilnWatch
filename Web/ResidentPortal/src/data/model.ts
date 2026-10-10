import { z } from 'zod';

export type Language = 'en' | 'hi';
export const localized = z.object({ en: z.string(), hi: z.string() });
export type Localized = z.infer<typeof localized>;
export const text = (en: string, hi: string): Localized => ({ en, hi });
export const point = z.tuple([z.number().finite().min(-180).max(180), z.number().finite().min(-90).max(90)]);
export type Point = z.infer<typeof point>;
const timestamp = z.string().datetime({ offset: true });
const positive = z.number().finite().positive();
function validRing(p: Point[] | null): boolean {
  if (!p) return true;
  if (p[0][0] !== p.at(-1)?.[0] || p[0][1] !== p.at(-1)?.[1]) return false;
  const vertices = p.slice(0, -1);
  if (new Set(vertices.map(v => v.join(','))).size !== vertices.length) return false;
  const cross = (a: Point, b: Point, c: Point) => (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
  const area = vertices.reduce((sum, a, i) => { const b = p[i + 1]; return sum + a[0] * b[1] - b[0] * a[1]; }, 0);
  if (Math.abs(area) < 1e-12) return false;
  for (let i = 0; i < vertices.length; i++) for (let j = i + 2; j < vertices.length; j++) {
    if (i === 0 && j === vertices.length - 1) continue;
    if (cross(p[i], p[i + 1], p[j]) * cross(p[i], p[i + 1], p[j + 1]) <= 0 && cross(p[j], p[j + 1], p[i]) * cross(p[j], p[j + 1], p[i + 1]) <= 0) return false;
  }
  return true;
}
const imageSchema = z.object({
  url: z.string(), acquired_at: timestamp.nullable(), source: localized,
  resolution_m: positive.nullable(), width: z.literal(256), height: z.literal(256),
  outline_px: z.array(z.tuple([z.number().min(0).max(256), z.number().min(0).max(256)])).length(4).nullable(),
});
export type EvidenceImage = z.infer<typeof imageSchema>;
export const ruleSchema = z.object({
  id: z.string().regex(/^[A-Za-z0-9-]+$/), name: localized, jurisdiction: localized,
  explanation: localized, limitation: localized, threshold_m: positive.nullable(),
  source_url: z.string().url().nullable(), source_title: z.string(), effective_date: z.string().nullable(),
  applicability: z.enum(['reference_only', 'sample_assessment']),
});
export type Rule = z.infer<typeof ruleSchema>;
export const kilnSchema = z.object({
  id: z.string().regex(/^[A-Za-z0-9-]{1,100}$/), name: localized,
  status: z.string().min(1).max(80), human_reviewed: z.boolean(), centroid: point,
  footprint: z.array(point).min(4).max(12).nullable().refine(validRing, 'Invalid polygon'),
  last_seen: timestamp, revision: z.string().min(1),
  prediction: z.object({ type: z.string().min(1).max(80), score: z.number().min(0).max(1).nullable(), verified: z.boolean() }),
  evidence: z.object({ before: imageSchema.nullable(), after: imageSchema.nullable() }),
  assessments: z.array(z.object({ rule_id: z.string(), state: z.enum(['assessed', 'not_evaluated']), measured_distance_m: z.number().finite().nonnegative().nullable(), threshold_m: positive.nullable(), source_url: z.string().url().nullable() })),
  exposure: z.object({ people: z.number().int().nonnegative(), radius_m: positive, source: localized, estimated_at: timestamp }).nullable(),
});
export type Kiln = z.infer<typeof kilnSchema>;
export const pageSchema = z.object({
  items: z.array(z.object({ kiln: kilnSchema, distance_m: z.number().finite().nonnegative() })).max(100),
  next_cursor: z.string().min(1).nullable(), complete: z.boolean(), revision: z.string().min(1),
  coverage: z.enum(['known', 'unknown']), updated_at: timestamp, distance_basis: z.literal('centroid'),
}).refine(p => !(p.complete && p.next_cursor) && !(p.items.length === 0 && p.next_cursor), 'Invalid page completeness');
export type Page = z.infer<typeof pageSchema>;
export type Search = { center: Point; radius_m: number };
export type DataErrorCode = 'configuration' | 'unavailable' | 'malformed' | 'not_found' | 'throttled' | 'timeout' | 'pagination';
export class DataError extends Error {
  constructor(public code: DataErrorCode) { super(code); }
}

export const SOURCE_HOSTS = ['mpcb.gov.in', 'www.mpcb.gov.in'];
export function safeSource(url: string | null): string | undefined {
  try { const u = new URL(url ?? ''); return u.protocol === 'https:' && SOURCE_HOSTS.includes(u.hostname) && !u.username && !u.password ? u.href : undefined; } catch { return undefined; }
}
export function safeImage(url: string, sample: boolean, hosts: string[]): string | undefined {
  if (sample && /^\/samples\/[a-z0-9-]+\.svg$/.test(url)) return url;
  if (sample) return undefined;
  try { const u = new URL(url); return u.protocol === 'https:' && hosts.includes(u.hostname) && !u.username && !u.password ? u.href : undefined; } catch { return undefined; }
}
export function assessed(a: Kiln['assessments'][number]): boolean {
  return a.state === 'assessed' && a.measured_distance_m !== null && a.threshold_m !== null && !!safeSource(a.source_url);
}

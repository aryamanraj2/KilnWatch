import { z } from 'zod';
import { residentRequestsSchema } from './requests';
import { checkSchema, kilnSchema, safeImage, text, type EvidenceImage, type Kiln, type Page } from './model';

// Real public read API (App/docs/api-contract.md, "Integration 2C" and "R1").
// Only fields the API publishes are mapped; anything it lacks stays unknown.
const timestamp = z.string().datetime({ offset: true });
const latLon = z.object({ latitude: z.number().finite().min(-90).max(90), longitude: z.number().finite().min(-180).max(180) });
const pixel = z.tuple([z.number().min(0).max(256), z.number().min(0).max(256)]);
const metadata = z.object({
  acquired_at: timestamp.nullable().optional(), attribution: z.string().max(200).nullable().optional(),
  gsd_m: z.number().finite().positive().nullable().optional(), patch_px: z.number().nullable().optional(),
  footprint_px: z.array(pixel).length(4).nullable().optional(),
}).nullable().optional();
export const liveKilnSchema = z.object({
  kiln_id: z.string().regex(/^[A-Za-z0-9-]{1,100}$/),
  footprint: z.object({ centroid: latLon, polygon: z.array(latLon).min(3).max(11) }),
  type: z.string().min(1).max(80).nullable(), type_verification: z.string().max(40).nullable().optional(),
  detection_confidence: z.number().min(0).max(1).nullable().optional(),
  status: z.string().min(1).max(80), rules_assessment: z.string().max(40).nullable().optional(),
  rule_checks: z.array(checkSchema).nullable().optional(),
  exposure: z.object({ people: z.number().int().nonnegative() }).nullable().optional(),
  evidence: z.object({
    before: z.string().nullable().optional(), after: z.string().nullable().optional(),
    before_metadata: metadata, after_metadata: metadata,
  }).nullable().optional(),
  first_seen: timestamp.nullable().optional(), last_seen: timestamp,
  distance_m: z.number().finite().nonnegative().optional(),
  resident_requests: residentRequestsSchema.optional(),
});
export type LiveKiln = z.infer<typeof liveKilnSchema>;
export const liveListSchema = z.object({ kilns: z.array(liveKilnSchema).max(200), next_cursor: z.string().nullable() });

export const EXPOSURE_ATTRIBUTION = text(
  'Modelled estimate of residents within 800 m of the kiln edge. Population: Meta and CIESIN High Resolution Settlement Layer (HRSL) v1.5.2, CC BY 4.0. Age groups are modelled shares of the same estimate.',
  // Needs native review.
  'भट्ठे के किनारे से 800 मीटर के भीतर रहने वाले निवासियों का मॉडल आधारित अनुमान। जनसंख्या: Meta और CIESIN High Resolution Settlement Layer (HRSL) v1.5.2, CC BY 4.0। आयु समूह इसी अनुमान के मॉडल आधारित हिस्से हैं।',
);

function image(url: string | null | undefined, meta: z.infer<typeof metadata>, hosts: string[]): EvidenceImage | null {
  // Evidence is accepted only from the configured evidence CDN host.
  const safe = url ? safeImage(url, false, hosts) : undefined;
  if (!safe) return null;
  const attribution = meta?.attribution ?? 'Attribution not published';
  return {
    url: safe, acquired_at: meta?.acquired_at ?? null, source: text(attribution, attribution),
    resolution_m: meta?.gsd_m ?? null, width: 256, height: 256, outline_px: meta?.footprint_px ?? null,
  };
}

export function toKiln(raw: LiveKiln, hosts: string[]): Kiln {
  const ring = raw.footprint.polygon.map(p => [p.longitude, p.latitude] as [number, number]);
  return kilnSchema.parse({
    id: raw.kiln_id, name: text(raw.kiln_id, raw.kiln_id), status: raw.status, human_reviewed: false,
    centroid: [raw.footprint.centroid.longitude, raw.footprint.centroid.latitude],
    footprint: [...ring, ring[0]], last_seen: raw.last_seen, revision: 'unknown',
    prediction: { type: raw.type ?? 'unknown', score: raw.detection_confidence ?? null, verified: false },
    evidence: { before: image(raw.evidence?.before, raw.evidence?.before_metadata, hosts), after: image(raw.evidence?.after, raw.evidence?.after_metadata, hosts) },
    assessments: [],
    exposure: raw.exposure ? { people: raw.exposure.people, radius_m: 800, source: EXPOSURE_ATTRIBUTION, estimated_at: null } : null,
    checks: raw.rule_checks ?? [], rules_assessment: raw.rules_assessment ?? 'unknown',
    resident_requests: raw.resident_requests,
  });
}

export function toPage(body: unknown, radius: number, hosts: string[]): Page {
  const list = liveListSchema.parse(body);
  // The near query is a single page (at most 50, next_cursor null).
  if (list.next_cursor !== null) throw new Error('unexpected cursor');
  const items = list.kilns.map(raw => {
    if (raw.distance_m === undefined || raw.distance_m > radius) throw new Error('distance outside query');
    return { kiln: toKiln(raw, hosts), distance_m: raw.distance_m };
  }).sort((a, b) => a.distance_m - b.distance_m || (a.kiln.id < b.kiln.id ? -1 : a.kiln.id > b.kiln.id ? 1 : 0));
  return { items, next_cursor: null, complete: true, revision: 'unknown', coverage: 'unknown', updated_at: null, distance_basis: 'footprint' };
}

// Ask (Phase 4A): one stateless question, one JSON answer.
export const KILN_ID = /^KW-(?:[0-9a-f]{32}|\d{4,})$/;
export const askSchema = z.object({
  answer: z.string().max(20000), citations: z.array(z.string()).max(100),
  steps: z.array(z.object({ tool: z.string(), label: z.string(), summary: z.string().nullable().optional(), ok: z.boolean() })).max(50),
  fallback: z.boolean(), disclaimer: z.string().max(2000),
});
export type AskAnswer = z.infer<typeof askSchema>;
export type AskErrorKind = 'invalid' | 'cap' | 'busy' | 'unavailable' | 'model' | 'registry' | 'timeout' | 'network' | 'malformed' | 'configuration';
export class AskError extends Error {
  constructor(public kind: AskErrorKind, public retryable: boolean) { super(kind); }
}
export function askError(status: number, body: unknown): AskError {
  const error = (body as { error?: { code?: unknown; retryable?: unknown } } | null)?.error;
  const code = typeof error?.code === 'string' ? error.code : null;
  if (status === 400) return new AskError('invalid', false);
  if (status === 429) return code === 'daily_cap_reached' ? new AskError('cap', false) : new AskError('busy', true);
  if (status === 503) return new AskError(code === 'model_unavailable' ? 'model' : code === 'upstream_unavailable' ? 'registry' : 'unavailable', error?.retryable === true);
  return new AskError('unavailable', status >= 500);
}

// Display words match the iOS app (KilnWatchCore RuleCheck). Hindi needs native review.
export const CHECK_STATUS: Record<string, [string, string]> = {
  within_threshold: ['Siting flag · needs inspection', 'स्थान संबंधी संकेत · निरीक्षण आवश्यक'],
  beyond_threshold: ['Beyond threshold', 'सीमा से अधिक दूरी पर'],
  inconclusive: ['Inconclusive · map data incomplete', 'अनिर्णीत · मानचित्र डेटा अधूरा'],
  not_evaluated: ['Not evaluated · no usable data', 'मूल्यांकन नहीं हुआ · उपयोगी डेटा नहीं'],
  not_applicable: ['Not applicable', 'लागू नहीं'],
};
export const UNKNOWN_CHECK: [string, string] = ['Check state unavailable · unsupported result', 'जाँच की स्थिति उपलब्ध नहीं'];
export const VERIFICATION: Record<string, [string, string]> = {
  secondary_sources: ['Secondary sources · gazette text not checked', 'द्वितीयक स्रोत · राजपत्र का पाठ नहीं जाँचा गया'],
  unverified_compilation: ['Unverified threshold · from an academic compilation', 'अपुष्ट सीमा · एक शैक्षणिक संकलन से'],
};
export const UNKNOWN_VERIFICATION: [string, string] = ['Threshold verification unavailable', 'सीमा की पुष्टि की जानकारी उपलब्ध नहीं'];
export const flags = (kiln: Kiln) => (kiln.checks ?? []).filter(c => c.status === 'within_threshold');

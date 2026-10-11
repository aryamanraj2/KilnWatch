import { test, expect, type Page as BrowserPage } from '@playwright/test';
import { deflateSync } from 'node:zlib';
import { mockMapTiles } from './map-tiles';
import { readFileSync } from 'node:fs';
test.beforeEach(async ({ page }) => { await mockMapTiles(page); });

// Recorded real-shape public responses (sanitized hosts). These tests never contact AWS.
const api = 'https://public.example.test';
const near = JSON.parse(readFileSync(new URL('../fixtures/hapur-near.json', import.meta.url), 'utf8').replaceAll('cdn.example.test', 'evidence.example.test'));
const REF = 'KW-6b3b38da681850e5af46b024f3d3f78e', ZERO = 'KW-64e53b7b965453108b2aeea524685304', HIDDEN = 'KW-00c562060b40502fb4a7ed2016ce7576';
const answer = { answer: `${REF} has one siting flag: C-HAB-800 at 497 m against 800 m.`, citations: [REF], fallback: false,
  steps: [{ tool: 'get_evidence', label: `Gathering evidence for ${REF}`, summary: 'Found', ok: true }],
  disclaimer: 'Answers cite registry records. Agents never record verdicts. Kilns are flagged by satellite and pending inspection.' };

// Generate two distinct 256 px PNG test images without a dependency or real evidence.
function png(shade: number, size = 256): Buffer {
  const crc = (bytes: Buffer) => {
    let value = 0xffffffff;
    for (const byte of bytes) {
      value ^= byte;
      for (let i = 0; i < 8; i++) value = (value >>> 1) ^ ((value & 1) ? 0xedb88320 : 0);
    }
    return (value ^ 0xffffffff) >>> 0;
  };
  const chunk = (type: string, data: Buffer) => {
    const body = Buffer.concat([Buffer.from(type), data]);
    const length = Buffer.alloc(4); length.writeUInt32BE(data.length);
    const checksum = Buffer.alloc(4); checksum.writeUInt32BE(crc(body));
    return Buffer.concat([length, body, checksum]);
  };
  const header = Buffer.alloc(13); header.writeUInt32BE(size); header.writeUInt32BE(size, 4); header[8] = 8; header[9] = 2;
  const pixels = Buffer.alloc(size * (1 + size * 3), shade);
  for (let row = 0; row < size; row++) pixels[row * (1 + size * 3)] = 0;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', header), chunk('IDAT', deflateSync(pixels)), chunk('IEND', Buffer.alloc(0))]);
}

async function mockPublicService(page: BrowserPage, ask: { status: number; body: unknown } = { status: 200, body: answer }) {
  const asked: unknown[] = [];
  await page.route(`${api}/**`, route => {
    const url = new URL(route.request().url());
    if (url.pathname === '/ask') { asked.push(route.request().postDataJSON()); return route.fulfill({ status: ask.status, json: ask.body }); }
    if (url.pathname === '/public/kilns') return route.fulfill({ json: near });
    const record = near.kilns.find((k: { kiln_id: string }) => `/public/kilns/${k.kiln_id}` === url.pathname);
    if (record) { const { distance_m: _, ...detail } = record; return route.fulfill({ json: detail }); }
    return route.fulfill({ status: 404, json: { error: { code: 'not_found', message: 'Not found' } } });
  });
  await page.route('https://evidence.example.test/**', route => route.fulfill({ contentType: 'image/png', body: png(route.request().url().length % 2 ? 100 : 160) }));
  return asked;
}
async function search(page: BrowserPage) {
  await page.getByLabel('Latitude', { exact: true }).fill('28.73060');
  await page.getByLabel('Longitude', { exact: true }).fill('77.77590');
  await page.getByLabel('5 km').check();
  await page.getByRole('button', { name: 'Confirm area & search' }).click();
}

test('real near query, record rule checks, exposure and evidence', async ({ page }) => {
  await mockPublicService(page);
  const requests: string[] = [];
  page.on('request', r => { if (r.url().startsWith(api)) { requests.push(r.url()); expect(r.headers().authorization).toBeUndefined(); } });
  await page.goto('/'); await search(page);
  await expect(page.getByText('4 results loaded')).toBeVisible();
  expect(Object.fromEntries(new URL(requests[0]).searchParams)).toEqual({ lat: '28.730600', lon: '77.775900', radius_m: '5000' });
  await expect(page.getByText('Distance from search centre to the kiln footprint', { exact: false }).first()).toBeVisible();
  await expect(page.getByRole('button', { name: 'Load more records' })).toHaveCount(0);
  await page.getByRole('link', { name: REF, exact: true }).click();
  await expect(page.getByRole('heading', { name: REF, exact: true })).toBeVisible();
  await expect(page.locator('.record-heading')).toContainText('Flagged by satellite · pending inspection');
  const hab = page.locator('.rule-card', { hasText: 'C-HAB-800' });
  await expect(hab).toContainText('Siting flag · needs inspection'); await expect(hab).toContainText('497'); await expect(hab).toContainText('800');
  await expect(page.locator('.detail-aside').getByText('4,225', { exact: false })).toBeVisible();
  await expect(page.getByText('High Resolution Settlement Layer (HRSL) v1.5.2', { exact: false })).toBeVisible();
  await expect(page.getByRole('slider')).toBeEnabled();
  await expect(page.getByText('Contains modified Copernicus Sentinel data 2023', { exact: false })).toBeVisible();
  await expect(page.locator('main')).not.toContainText(/illegal|violation|compliant|\bclear\b/i);
  await hab.getByRole('link', { name: 'C-HAB-800' }).click();
  await expect(page.getByRole('heading', { name: 'Distance to habitation' })).toBeVisible();
  await expect(page.locator('main')).toContainText('Secondary sources · gazette text not checked');
  await page.goto('/rules/C-HAB-800'); await expect(page.getByRole('heading', { name: 'Rule details come from a kiln record' })).toBeVisible();
});

test('zero-flag record is never clear; non-public record shows not found', async ({ page }) => {
  await mockPublicService(page);
  await page.goto(`/kilns/${ZERO}`);
  await expect(page.getByText('This does not mean the site passed', { exact: false })).toBeVisible();
  await expect(page.locator('main')).toContainText('Inconclusive · map data incomplete');
  await page.goto(`/kilns/${HIDDEN}`);
  await expect(page.getByRole('alert')).toContainText('This public record is not available');
  await expect(page.locator('main')).not.toContainText('SAMPLE-KW');
});

test('Ask from a record: body, steps, citations and disclaimer; Hindi note', async ({ page }) => {
  const asked = await mockPublicService(page);
  await page.goto(`/kilns/${REF}`); await page.getByRole('link', { name: 'Ask about this kiln' }).click();
  await page.getByLabel('Your question').fill('  What should I check at this kiln?  ');
  await page.getByRole('button', { name: 'Ask', exact: true }).click();
  await expect(page.locator('.ask-text')).toHaveText(answer.answer);
  expect(asked).toEqual([{ question: 'What should I check at this kiln?', kiln_id: REF }]);
  await expect(page.locator('.ask-steps')).toContainText(`Gathering evidence for ${REF}`);
  await expect(page.locator('.ask-disclaimer')).toHaveText(answer.disclaimer);
  await expect(page.getByText('Answers cite public registry records. The assistant never records verdicts.')).toBeVisible();
  await page.locator('.ask-citations').getByRole('link', { name: REF }).click();
  await expect(page.getByRole('heading', { name: REF, exact: true })).toBeVisible();
  await page.goto('/ask'); await page.getByRole('button', { name: 'हिन्दी', exact: true }).click();
  await expect(page.getByText('उत्तर केवल अंग्रेज़ी में मिलते हैं', { exact: false })).toBeVisible();
});

for (const [status, body, message, retry] of [
  [429, { error: { code: 'daily_cap_reached', message: 'Cap', retryable: false } }, 'Ask has reached today’s limit', false],
  [429, { message: 'Too Many Requests' }, 'Too many questions, wait a moment', true],
  [400, { error: { code: 'invalid_request', message: 'Bad', retryable: false } }, 'Your draft is still here', false],
] as const) {
  test(`Ask ${status} ${message} keeps the draft and is never retried automatically`, async ({ page }) => {
    const asked = await mockPublicService(page, { status, body });
    await page.goto('/ask'); await page.getByLabel('Your question').fill('How many kilns are flagged in Hapur?');
    await page.getByRole('button', { name: 'Ask', exact: true }).click();
    await expect(page.getByRole('alert')).toContainText(message);
    await expect(page.getByLabel('Your question')).toHaveValue('How many kilns are flagged in Hapur?');
    await expect(page.getByRole('button', { name: 'Try again' })).toHaveCount(retry ? 1 : 0);
    expect(asked).toHaveLength(1);
  });
}

test('search failure shows an error state and never loads fixtures', async ({ page }) => {
  await mockPublicService(page);
  await page.route(`${api}/public/kilns?**`, route => route.fulfill({ status: 503, headers: { 'Retry-After': '120' }, json: { error: { code: 'registry_unavailable', message: 'Down' } } }));
  await page.goto('/'); await search(page);
  await expect(page.getByRole('alert')).toContainText('The service is unavailable');
  await expect(page.locator('.result-list li')).toHaveCount(0); await expect(page.locator('main')).not.toContainText('SAMPLE-KW');
});

test('phone rule list: flags first, other checks grouped; only flags use the status colour', async ({ page }) => {
  await mockPublicService(page); await page.setViewportSize({ width: 393, height: 852 });
  await page.goto(`/kilns/${REF}`);
  const flagged = page.locator('.record-section > .rule-card'); await expect(flagged).toHaveCount(1); await expect(flagged).toContainText('C-HAB-800');
  const others = page.locator('.other-checks'); await expect(others.locator('summary')).toHaveText(/Other rule checks · 7/);
  await others.locator('summary').click(); await expect(others.locator('.rule-card')).toHaveCount(7);
  await expect(others).toContainText('Inconclusive · map data incomplete');
  await expect(others.locator('.rule-card', { hasText: 'C-KILN-1K' }).locator('.distance-bar')).toHaveClass(/neutral/);
  await expect(flagged.locator('.distance-bar')).not.toHaveClass(/neutral/);
  await expect(page.locator('.glance')).toContainText('C-HAB-800'); await expect(page.locator('.glance')).toContainText('4,225');
  await expect(page.locator('.action-bar').getByRole('link', { name: 'Ask about this kiln' })).toHaveAttribute('href', `/ask?kiln=${REF}`);
});

import { test, expect, type Page as BrowserPage } from '@playwright/test';
import { deflateSync } from 'node:zlib';
import { mockMapTiles } from './map-tiles';
import { mkdirSync, readFileSync } from 'node:fs';
test.beforeEach(async ({ page }) => { await mockMapTiles(page); });

// Recorded real-shape public responses (sanitized hosts). These tests never contact AWS.
const api = 'https://public.example.test';
const requestRecorded = JSON.parse(readFileSync(new URL('../fixtures/requests-recorded.json', import.meta.url), 'utf8'));
const near = JSON.parse(readFileSync(new URL('../fixtures/hapur-near.json', import.meta.url), 'utf8').replaceAll('cdn.example.test', 'evidence.example.test'));
const REF = 'KW-6b3b38da681850e5af46b024f3d3f78e', ZERO = 'KW-64e53b7b965453108b2aeea524685304';
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


const stage = process.env.KW_POLISH_STAGE ?? 'after';
const captureDir = new URL('../../docs/screens/polish-45/', import.meta.url).pathname;
async function shot(page: BrowserPage, name: string) {
  mkdirSync(captureDir, { recursive: true });
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({ path: `${captureDir}/${name}-${stage}.png` });
}
test('matched portal openings and local request/disclosure journey', async ({ page }) => {
  test.setTimeout(60000);
  await page.setViewportSize({ width: 393, height: 852 });
  await mockPublicService(page);
  await page.route(`${api}/public/kilns/${REF}`, route => {
    const { distance_m: _, ...detail } = near.kilns.find((k: { kiln_id: string }) => k.kiln_id === REF);
    return route.fulfill({ json: { ...detail, resident_requests: requestRecorded.resident_requests } });
  });
  let writes = 0;
  await page.route(`${api}/requests`, route => { writes++; return route.fulfill({ status: 201, json: { ...requestRecorded, kiln_id: REF, created: true } }); });
  await page.goto('/');
  await page.locator('.area-settings > summary').click(); await search(page);
  await expect(page.getByText('4 results loaded')).toBeVisible();
  await expect(page.locator('.basemap .leaflet-tile-loaded').first()).toBeVisible();
  await shot(page, 'phone-area');
  await page.goto(`/kilns/${REF}`);
  await expect(page.getByRole('heading', { name: REF, exact: true })).toBeVisible();
  await expect(page.getByRole('slider')).toBeEnabled();
  await shot(page, 'phone-record');
  await page.setViewportSize({ width: 1440, height: 1000 });
  await shot(page, 'desktop-record');
  if (stage === 'before') return;
  await page.goto('/'); await search(page);
  await shot(page, 'desktop-area');
  await page.setViewportSize({ width: 393, height: 852 });
  await page.getByRole('button', { name: new RegExp(' · ' + REF + '$') }).click();
  await expect(page.locator('.map-selection')).toContainText(REF);
  await page.getByRole('link', { name: 'Open selected record' }).click();
  await page.locator('.action-bar').getByRole('link', { name: 'Request an inspection' }).click();
  await expect(page.getByLabel('Smoke or ash')).toBeFocused();
  await expect(page.locator('.action-bar')).toBeHidden();
  await page.getByLabel('Smoke or ash').check();
  await page.getByLabel('Under 1 km', { exact: true }).check();
  await page.locator('#resident-requests').scrollIntoViewIfNeeded();
  await page.screenshot({ path: `${captureDir}/phone-request-form-after.png` });
  const send = page.getByRole('button', { name: 'Send request' });
  await send.scrollIntoViewIfNeeded();
  const box = await send.boundingBox(); const tab = await page.locator('.tab-bar').boundingBox();
  expect(box!.y + box!.height).toBeLessThanOrEqual(tab!.y);
  await send.click(); await expect(page.getByRole('status').filter({ hasText: 'Your request was added' })).toBeVisible();
  expect(writes).toBe(1);
  await page.screenshot({ path: `${captureDir}/phone-request-confirmation-after.png` });
  await page.reload(); await page.locator('.action-bar').getByRole('link', { name: 'View your request' }).click();
  await expect(page.locator('#resident-requests')).toContainText('You asked for an inspection on');
  expect(writes).toBe(1);
  await page.locator('.prefs-menu > summary').click(); await page.getByRole('button', { name: 'हिन्दी', exact: true }).click();
  await page.goto(`/kilns/${ZERO}`);
  await page.locator('.action-bar').getByRole('link', { name: 'निरीक्षण का अनुरोध करें' }).click();
  await expect(page.getByLabel('धुआँ या राख')).toBeFocused();
  await page.getByLabel('धुआँ या राख').check();
  await page.getByRole('button', { name: 'अनुरोध भेजें' }).scrollIntoViewIfNeeded();
  await page.screenshot({ path: `${captureDir}/phone-request-hindi-after.png` });
});

test('motion: retained map selection, disclosure and reduced-motion fallback', async ({ page }) => {
  test.skip(stage === 'before');
  await page.setViewportSize({ width: 393, height: 852 });
  await mockPublicService(page);
  await page.goto('/'); await page.locator('.area-settings > summary').click(); await search(page);
  const pins = page.locator('.basemap .map-pin');
  await expect(pins.first()).toBeVisible();
  const mapHandle = await page.locator('.basemap').elementHandle();
  for (const index of [1, 0]) {
    await pins.nth(index).click();
    await expect(page.locator('.map-selection')).toBeVisible();
  }
  expect(await mapHandle!.evaluate(el => el.isConnected)).toBe(true);
  await page.getByRole('link', { name: 'Open selected record' }).click();
  await page.locator('.other-checks > summary').click();
  await expect(page.locator('.other-checks')).toHaveAttribute('open', '');
  await page.screenshot({ path: `${captureDir}/phone-checks-expanded-after.png` });
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.locator('.other-checks > summary').click();
  await page.locator('.other-checks > summary').click();
  expect(await page.locator('.other-checks').evaluate(el => getComputedStyle(el).transitionDuration)).toBe('0s');
});

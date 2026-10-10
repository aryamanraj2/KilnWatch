import { test, expect, type Page as BrowserPage } from '@playwright/test';
import { mockMapTiles } from './map-tiles';
test.beforeEach(async ({ page }) => { await mockMapTiles(page); });
import { readFile } from 'node:fs/promises';
import { deflateSync } from 'node:zlib';
import { kilns, rules, UPDATED } from '../../src/data/fixtures';
import type { Kiln, Page } from '../../src/data/model';

// Fictional contract responses only. These tests do not contact AWS or publish records.
const api = 'https://public.example.test';
const evidence = 'https://evidence.example.test';
const records: Kiln[] = kilns.slice(0, 2).map((k, i) => ({
  ...k, id: `PUBLIC-TEST-${i + 1}`, name: { en: `Published test record ${i + 1}`, hi: `प्रकाशित परीक्षण रिकॉर्ड ${i + 1}` },
  evidence: {
    before: k.evidence.before && { ...k.evidence.before, url: `${evidence}/before.png` },
    after: k.evidence.after && { ...k.evidence.after, url: `${evidence}/after.png`, resolution_m: null },
  },
}));
const responsePage = (cursor: boolean): Page => ({
  items: [{ kiln: records[cursor ? 1 : 0], distance_m: cursor ? 420 : 290 }],
  next_cursor: cursor ? null : 'page-two', complete: cursor, revision: 'public-test-1',
  coverage: 'known', updated_at: UPDATED, distance_basis: 'centroid',
});

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

async function mockPublicService(page: BrowserPage) {
  await page.route(`${api}/**`, route => {
    const url = new URL(route.request().url());
    if (url.pathname === '/public/kilns') return route.fulfill({ json: responsePage(url.searchParams.has('cursor')) });
    const record = records.find(k => `/public/kilns/${k.id}` === url.pathname);
    if (record) return route.fulfill({ json: record });
    const rule = rules.find(r => `/public/rules/${r.id}` === url.pathname);
    if (rule) return route.fulfill({ json: { ...rule, applicability: 'reference_only',
      jurisdiction: { en: 'Test jurisdiction', hi: 'परीक्षण क्षेत्राधिकार' },
      explanation: { en: 'Public rule reference for testing.', hi: 'परीक्षण के लिए सार्वजनिक नियम संदर्भ।' },
      limitation: { en: 'Applicability requires confirmation by the authority.', hi: 'लागू नियम की प्राधिकरण से पुष्टि आवश्यक है।' },
    } });
    return route.fulfill({ status: 404, json: { error: { code: 'not_found' } } });
  });
  await page.route(`${evidence}/**`, route => route.fulfill({ contentType: 'image/png', body: png(route.request().url().endsWith('before.png') ? 100 : 160) }));
}
async function search(page: BrowserPage) {
  await page.getByLabel('Latitude', { exact: true }).fill('28.73000');
  await page.getByLabel('Longitude', { exact: true }).fill('77.68000');
  await page.getByRole('button', { name: 'Confirm area & search' }).click();
}

test('live-mode query, paging, diagram selection, detail, and session Back', async ({ page }) => {
  await mockPublicService(page);
  const requests: string[] = [];
  page.on('request', r => { if (r.url().startsWith(api)) { requests.push(r.url()); expect(r.headers().authorization).toBeUndefined(); expect(r.headers().cookie).toBeUndefined(); } });
  await page.goto('/');
  await expect(page.getByLabel('Place or address', { exact: true })).toBeDisabled();
  await expect(page.getByText('Confirming sends your search coordinates', { exact: false })).toBeVisible();
  await search(page); await expect(page.getByText('1 results loaded')).toBeVisible();
  await expect(page.getByText('Public records', { exact: true })).toBeVisible();
  await expect(page.getByText('Distance from search centre to record centroid', { exact: false })).toBeVisible();
  const query = new URL(requests[0]).searchParams;
  expect(Object.fromEntries(query)).toEqual({ longitude: '77.68', latitude: '28.73', radius_m: '1000', limit: '3' });
  await page.getByRole('button', { name: 'Load more records' }).click(); await expect(page.getByText('2 results loaded')).toBeVisible();
  expect(new URL(requests[1]).searchParams.get('cursor')).toBe('page-two');
  await page.getByRole('button', { name: '2 · PUBLIC-TEST-2' }).click();
  await expect(page.getByRole('button', { name: 'Select PUBLIC-TEST-2', exact: true })).toHaveAttribute('aria-pressed', 'true');
  await page.getByRole('link', { name: 'PUBLIC-TEST-1', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Published test record 1', exact: true })).toBeVisible();
  await page.goBack(); await expect(page.getByText('2 results loaded')).toBeVisible();
  expect(page.url()).not.toContain('28.73');
  expect(await page.evaluate(() => Object.keys(localStorage).sort())).toEqual(['kw-language', 'kw-theme']);
});

for (const language of ['en', 'hi'] as const) {
  test(`${language} published evidence, explanations, rules, and edited draft export`, async ({ page }) => {
    await mockPublicService(page); await page.goto('/kilns/PUBLIC-TEST-1');
    if (language === 'hi') await page.getByRole('button', { name: 'हिन्दी', exact: true }).click();
    const hi = language === 'hi';
    const slider = page.getByRole('slider'); await expect(slider).toBeEnabled();
    await slider.focus(); await page.keyboard.press('ArrowRight'); await expect(slider).toHaveValue('55');
    const image = page.getByRole('img', { name: hi ? 'इस रिकॉर्ड का बाद का प्रकाशित चित्र' : 'Later published image for this record' });
    await expect(image).toBeVisible(); await expect(image).toHaveAttribute('referrerpolicy', 'no-referrer');
    expect(await image.evaluate((img: HTMLImageElement) => [img.naturalWidth, img.naturalHeight])).toEqual([256, 256]);
    await expect(page.getByText(hi ? 'रिज़ॉल्यूशन अज्ञात' : 'Resolution unknown', { exact: false }).last()).toBeVisible();
    await expect(page.getByText(hi ? 'मापी गई दूरी · दी गई सीमा' : 'measured distance · supplied threshold', { exact: false })).toBeVisible();
    await page.getByRole('button', { name: hi ? 'इस रिकॉर्ड को समझाएँ' : 'Explain this record', exact: true }).click();
    await expect(page.locator('.explanation-answer')).not.toContainText(hi ? 'नमूना' : 'sample');
    await page.getByRole('link', { name: records[0].assessments[0].rule_id, exact: true }).click();
    await expect(page.locator('main')).not.toContainText(hi ? 'नमूना' : 'sample');
    await page.goBack(); await page.getByRole('button', { name: hi ? 'निरीक्षण का अनुरोध तैयार करें' : 'Prepare an inspection request', exact: true }).click();
    await page.getByRole('button', { name: hi ? 'संपादन योग्य मसौदा बनाएँ' : 'Create editable draft', exact: true }).click();
    const editor = page.getByLabel(hi ? 'अपना निरीक्षण अनुरोध संपादित करें' : 'Edit your inspection request', { exact: true });
    const body = await editor.inputValue(); expect(body).not.toMatch(/sample|नमूना/i); expect(body).toContain(`${evidence}/after.png`);
    await editor.fill(body + '\nRetained test edit.');
    const pending = page.waitForEvent('download'); await page.getByRole('button', { name: hi ? 'पाठ डाउनलोड करें' : 'Download text', exact: true }).click();
    const downloaded = await pending; const content = await readFile((await downloaded.path())!, 'utf8');
    expect(downloaded.suggestedFilename()).toBe(`kilnwatch-draft-${language}.txt`);
    expect(content).toContain('Retained test edit.'); expect(content).not.toMatch(/sample|नमूना/i);
    expect(content).toContain(hi ? 'किसी प्राधिकरण को भेजा नहीं गया' : 'Not submitted to any authority');
  });
}

test('live-mode failure, malformed data, throttling, and non-disclosing not found never load fixtures', async ({ page }) => {
  await mockPublicService(page);
  for (const status of [503, 200, 429]) {
    await page.route(`${api}/public/kilns?**`, route => route.fulfill({ status, headers: { 'Retry-After': '120' }, json: status === 200 ? { items: 'invalid' } : { error: { code: 'unavailable' } } }));
    await page.goto('/'); await search(page); await expect(page.getByRole('alert')).toBeVisible();
    await expect(page.getByLabel('Latitude', { exact: true })).toHaveValue('28.73000');
    await expect(page.locator('.result-list li')).toHaveCount(0); await expect(page.locator('main')).not.toContainText('SAMPLE-KW');
    await page.unroute(`${api}/public/kilns?**`);
  }
  let refused = '';
  for (const id of ['UNPUBLISHED-TEST', 'MISSING-TEST']) {
    await page.goto(`/kilns/${id}`); const error = page.getByRole('alert'); await expect(error).toContainText('This public record is not available');
    const current = await error.innerText(); if (refused) expect(current).toBe(refused); refused = current;
  }
});

test('later-page failure retains loaded results; bitmap failure can retry; unapproved evidence is never fetched', async ({ page }) => {
  await mockPublicService(page); await page.goto('/'); await search(page);
  await expect(page.getByText('1 results loaded')).toBeVisible();
  await page.route(`${api}/public/kilns?**`, route => route.fulfill({ status: 503, headers: { 'Retry-After': '120' }, json: {} }));
  await page.getByRole('button', { name: 'Load more records' }).click(); await expect(page.getByRole('alert')).toBeVisible();
  await expect(page.getByRole('link', { name: 'PUBLIC-TEST-1', exact: true })).toBeVisible(); await expect(page.getByText('All returned records loaded')).toHaveCount(0);
  await page.route(`${evidence}/after.png`, route => route.fulfill({ status: 503, body: '' }));
  await page.goto('/kilns/PUBLIC-TEST-1'); await expect(page.getByText('This image could not be loaded.', { exact: true })).toBeVisible();
  await page.unroute(`${evidence}/after.png`); await page.getByRole('button', { name: 'Retry images' }).click(); await expect(page.getByRole('slider')).toBeEnabled();
  await page.route(`${evidence}/after.png`, route => route.fulfill({ contentType: 'image/png', body: png(160, 128) }));
  await page.reload(); await expect(page.getByText('This image could not be loaded.', { exact: true })).toBeVisible();
  await expect(page.getByRole('slider')).toHaveCount(0);
  const blocked: string[] = []; page.on('request', r => { if (r.url().includes('private.example.test')) blocked.push(r.url()); });
  await page.route(`${api}/public/kilns/PUBLIC-TEST-1`, route => route.fulfill({ json: { ...records[0], evidence: { before: null, after: { ...records[0].evidence.after, url: 'https://private.example.test/secret.png' } } } }));
  await page.reload(); await expect(page.getByText('This image could not be loaded.', { exact: true })).toBeVisible(); expect(blocked).toEqual([]);
});

test('overlapping pages deduplicate, reject changed snapshots, and recover without losing selection', async ({ page }) => {
  await mockPublicService(page);
  for (const variant of ['snapshot', 'order', 'distance', 'revision']) {
    let valid = false;
    const firstPage = responsePage(false);
    const nextPage = responsePage(true);
    await page.route(`${api}/public/kilns?**`, route => {
      if (!new URL(route.request().url()).searchParams.has('cursor')) return route.fulfill({ json: { ...firstPage, items: [firstPage.items[0], firstPage.items[0]] } });
      if (valid) return route.fulfill({ json: { ...nextPage, items: [...firstPage.items, ...nextPage.items] } });
      const invalid = variant === 'snapshot' ? { ...nextPage, updated_at: '2026-10-02T06:00:00Z' }
        : variant === 'order' ? { ...nextPage, items: [{ ...nextPage.items[0], distance_m: 200 }] }
        : { ...nextPage, items: [{ ...firstPage.items[0], distance_m: variant === 'distance' ? 310 : firstPage.items[0].distance_m,
          kiln: { ...records[0], revision: variant === 'revision' ? 'changed-record' : records[0].revision } }] };
      return route.fulfill({ json: invalid });
    });
    await page.goto('/'); await search(page); await expect(page.getByText('1 results loaded')).toBeVisible();
    await expect(page.locator('.result-list li')).toHaveCount(1);
    await page.getByRole('button', { name: 'Load more records' }).click();
    await expect(page.getByRole('alert')).toContainText('Results changed while loading');
    await expect(page.getByText('1 results loaded')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Select PUBLIC-TEST-1', exact: true })).toHaveAttribute('aria-pressed', 'true');
    valid = true; await page.getByRole('button', { name: 'Load more records' }).click();
    await expect(page.getByText('2 results loaded')).toBeVisible(); await expect(page.getByRole('alert')).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Select PUBLIC-TEST-1', exact: true })).toHaveAttribute('aria-pressed', 'true');
    await page.unroute(`${api}/public/kilns?**`);
  }
});

test('oversized responses preserve input; Chromium also refuses redirected reads', async ({ page }, info) => {
  await mockPublicService(page);
  // Playwright WebKit cannot fulfill intercepted requests with a redirect status.
  // Exercise redirect refusal in Chromium and request-policy unit tests instead.
  if (info.project.name === 'chromium') {
    const redirected: string[] = [];
    await page.route('https://private.example.test/**', route => { redirected.push(route.request().url()); return route.fulfill({ json: responsePage(false) }); });
    await page.route(`${api}/public/kilns?**`, route => route.fulfill({ status: 302, headers: { location: 'https://private.example.test/redirect' } }));
    await page.goto('/'); await search(page); await expect(page.getByRole('alert')).toContainText('The service is unavailable');
    expect(redirected).toEqual([]); await expect(page.getByLabel('Latitude', { exact: true })).toHaveValue('28.73000');
    await expect(page.locator('.result-list li')).toHaveCount(0);
    await page.unroute(`${api}/public/kilns?**`);
  } else { await page.goto('/'); }
  const large = { ...responsePage(false), padding: 'आ'.repeat(350_000) };
  await page.route(`${api}/public/kilns?**`, route => route.fulfill({ json: large }));
  if (info.project.name === 'chromium') await page.getByRole('button', { name: 'Try again', exact: true }).click();
  else await search(page);
  await expect(page.getByRole('alert')).toContainText('This response could not be read safely');
  await expect(page.getByLabel('Longitude', { exact: true })).toHaveValue('77.68000');
  await expect(page.locator('.result-list li')).toHaveCount(0); await expect(page.locator('main')).not.toContainText('SAMPLE-KW');
});

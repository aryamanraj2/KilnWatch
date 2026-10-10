import { test, expect, type Page } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { mkdir, readFile } from 'node:fs/promises';
const artifacts = 'docs/screens';
async function sampleSearch(page: Page) {
  await page.getByRole('button', { name: 'Pilkhuwa · sample area' }).click();
  await page.getByRole('button', { name: 'Confirm area & search' }).click();
  await expect(page.getByText('3 results loaded')).toBeVisible();
}
async function openFirst(page: Page) { await page.getByRole('link', { name: 'SAMPLE-KW-001' }).click(); await expect(page.getByRole('heading', { name: 'Orchard edge', exact: true })).toBeVisible(); }

test('search, pagination, map/list selection, Back, and direct links', async ({ page }, info) => {
  await page.goto('/'); await sampleSearch(page);
  await page.getByRole('button', { name: 'Load more records' }).click(); await expect(page.getByText('6 results loaded')).toBeVisible();
  await page.getByRole('button', { name: 'Select SAMPLE-KW-002', exact: true }).click();
  await expect(page.getByRole('button', { name: '2 · SAMPLE-KW-002', exact: true })).toHaveAttribute('aria-pressed', 'true');
  await page.getByRole('button', { name: '1 · SAMPLE-KW-001', exact: true }).focus(); await page.keyboard.press('Enter');
  await expect(page.getByRole('button', { name: 'Select SAMPLE-KW-001', exact: true })).toHaveAttribute('aria-pressed', 'true');
  if (info.project.name === 'chromium') { await mkdir(artifacts, { recursive: true }); await page.screenshot({ path: `${artifacts}/desktop-area-en.png`, fullPage: true }); }
  await openFirst(page); await page.goBack(); await expect(page.getByText('6 results loaded')).toBeVisible();
  await page.goto('/kilns/SAMPLE-KW-001'); await expect(page.getByRole('heading', { name: 'Orchard edge', exact: true })).toBeVisible(); await page.reload(); await expect(page.getByText('Flagged by satellite · pending inspection', { exact: true })).toBeVisible();
  await page.goto('/kilns/DOES-NOT-EXIST'); await expect(page.getByRole('alert')).toContainText('This public record is not available');
});

test('two, single, absent, and failed evidence; rule limits and keyboard comparison', async ({ page }, info) => {
  await page.goto('/kilns/SAMPLE-KW-001'); const slider = page.getByRole('slider', { name: 'Compare images' }); await expect(slider).toBeEnabled();
  await slider.focus(); await page.keyboard.press('ArrowRight'); await expect(slider).toHaveValue('55');
  await page.getByRole('button', { name: 'Show before', exact: true }).click(); await expect(slider).toHaveValue('0');
  await page.getByRole('button', { name: 'Show after', exact: true }).click(); await expect(slider).toHaveValue('100');
  if (info.project.name === 'chromium') await page.screenshot({ path: `${artifacts}/evidence-en.png`, fullPage: true });
  await page.getByRole('button', { name: 'What is missing?', exact: true }).click(); await expect(page.getByRole('status')).toContainText('Some rules have not been assessed');
  await page.getByRole('link', { name: 'C-HAB-800' }).click(); await expect(page.getByRole('heading', { name: 'Distance from homes', exact: true })).toBeVisible(); await expect(page.getByText('Not established', { exact: true })).toBeVisible();
  await page.goto('/kilns/SAMPLE-KW-002'); await expect(page.getByRole('img', { name: 'Later synthetic scene for this sample record' })).toBeVisible(); await expect(page.getByRole('slider')).toHaveCount(0);
  await page.goto('/kilns/SAMPLE-KW-003'); await expect(page.getByText('This image could not be loaded.', { exact: true })).toBeVisible(); await page.getByRole('button', { name: 'Retry images' }).click(); await expect(page.getByText('This image could not be loaded.', { exact: true })).toBeVisible();
  await page.goto('/kilns/SAMPLE-KW-004'); await expect(page.getByRole('heading', { name: 'Imagery is not available' })).toBeVisible(); await expect(page.getByText('Status not available', { exact: true })).toBeVisible();
});

test('English multi-record draft, personal-data boundaries, edits, download, and print', async ({ page, context }, info) => {
  const unexpected: string[] = [];
  page.on('request', r => { if (!r.url().startsWith('http://127.0.0.1:5173') && !r.url().startsWith('data:')) unexpected.push(r.url()); });
  await page.goto('/'); await sampleSearch(page); await openFirst(page); await page.getByRole('button', { name: 'Add to inspection draft', exact: true }).click();
  await page.getByRole('link', { name: 'Back to area' }).click(); await page.getByRole('link', { name: 'SAMPLE-KW-002' }).click(); await page.getByRole('button', { name: 'Add to inspection draft', exact: true }).click();
  await page.getByRole('button', { name: 'Prepare an inspection request', exact: true }).click(); await expect(page.getByRole('heading', { name: '2 selected' })).toBeVisible();
  await page.getByLabel('Name (optional)', { exact: true }).fill('Sample Resident'); await page.getByLabel('Your own observations', { exact: true }).fill('Fictional resident observation for export testing.');
  await page.getByRole('button', { name: 'Create editable draft', exact: true }).click();
  const editor = page.getByLabel('Edit your inspection request', { exact: true }); const content = await editor.inputValue();
  expect(content).toContain('SAMPLE-KW-001'); expect(content).toContain('SAMPLE-KW-002'); expect(content).toContain('Sample Resident'); expect(content).not.toContain('28.73000'); expect(content).not.toContain('77.68000'); expect(content).toContain('links only; no images attached');
  await editor.fill(content + '\n\nMy retained edit.');
  page.once('dialog', dialog => dialog.dismiss()); await page.getByRole('button', { name: 'Regenerate draft', exact: true }).click(); await expect(editor).toHaveValue(/My retained edit/);
  const downloadPromise = page.waitForEvent('download'); await page.getByRole('button', { name: 'Download text', exact: true }).click(); const download = await downloadPromise; const file = await download.path(); const exported = await readFile(file!, 'utf8');
  expect(exported).toContain('SAMPLE DATA'); expect(exported).toContain('My retained edit.'); expect(exported).toContain('Draft only. Not submitted'); expect(exported).not.toContain('28.73000');
  if (info.project.name === 'chromium') {
    await download.saveAs(`${artifacts}/sample-draft-en.txt`);
    await context.grantPermissions(['clipboard-read', 'clipboard-write']); await page.getByRole('button', { name: 'Copy draft', exact: true }).click(); expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(exported);
    await page.screenshot({ path: `${artifacts}/draft-en.png`, fullPage: true }); await page.pdf({ path: `${artifacts}/sample-draft-en.pdf`, printBackground: true, preferCSSPageSize: true });
  }
  await page.evaluate(() => { window.print = () => { document.body.dataset.printRequested = 'yes'; }; }); await page.getByRole('button', { name: 'Print / Save PDF' }).click(); await expect(page.locator('body')).toHaveAttribute('data-print-requested', 'yes');
  expect(await page.evaluate(() => Object.keys(localStorage).sort())).toEqual(['kw-language', 'kw-theme']);
  expect(await page.evaluate(() => sessionStorage.length)).toBe(0); expect(page.url()).not.toContain('28.73'); expect(await page.evaluate(() => JSON.stringify(history.state))).not.toContain('28.73'); expect(unexpected).toEqual([]);
});

test('Hindi mobile journey, Devanagari coordinates, preserved language, and printable export', async ({ page }, info) => {
  await page.setViewportSize({ width: 375, height: 812 }); await page.emulateMedia({ colorScheme: 'dark', reducedMotion: 'reduce' });
  await page.goto('/'); await page.getByRole('button', { name: 'हिन्दी', exact: true }).click(); await page.reload(); await expect(page.locator('html')).toHaveAttribute('lang', 'hi');
  await page.getByLabel('अक्षांश', { exact: true }).fill('२८.७३०००'); await page.getByLabel('देशांतर', { exact: true }).fill('७७.६८०००'); await page.getByRole('button', { name: 'क्षेत्र की पुष्टि करके खोजें' }).click(); await expect(page.getByText('3 परिणाम लोड हुए')).toBeVisible();
  await page.getByRole('button', { name: 'मानचित्र', exact: true }).click(); await expect(page.getByText('सांकेतिक मानचित्र', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'सूची', exact: true }).click();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  if (info.project.name === 'chromium') await page.screenshot({ path: `${artifacts}/mobile-area-hi-dark.png`, fullPage: true });
  await page.getByRole('link', { name: 'SAMPLE-KW-001' }).click(); await expect(page.getByRole('slider')).toBeEnabled(); await page.getByRole('button', { name: 'निरीक्षण का अनुरोध तैयार करें' }).click();
  await page.getByRole('button', { name: 'संपादन योग्य मसौदा बनाएँ' }).click(); const editor = page.getByLabel('अपना निरीक्षण अनुरोध संपादित करें'); await expect(editor).toHaveValue(/निरीक्षण का अनुरोध/);
  await editor.fill((await editor.inputValue()) + '\n\nकृपया जाँच करें।');
  const downloadPromise = page.waitForEvent('download'); await page.getByRole('button', { name: 'पाठ डाउनलोड करें' }).click(); const download = await downloadPromise;
  const body = await readFile((await download.path())!, 'utf8'); expect(body).toContain('नमूना डेटा'); expect(body).toContain('कृपया जाँच करें।');
  if (info.project.name === 'chromium') { await download.saveAs(`${artifacts}/sample-draft-hi.txt`); await page.pdf({ path: `${artifacts}/sample-draft-hi.pdf`, printBackground: true, preferCSSPageSize: true }); }
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
});

test('denied location and invalid coordinates retain a working manual path', async ({ page }) => {
  await page.addInitScript(() => Object.defineProperty(navigator, 'geolocation', { value: { getCurrentPosition: (_success: unknown, error: (e: { code: number }) => void) => error({ code: 1 }) } }));
  await page.goto('/'); await page.getByRole('button', { name: 'Use my location' }).click(); await expect(page.getByRole('status')).toContainText('Location could not be used');
  await page.getByLabel('Latitude', { exact: true }).fill('999'); await page.getByLabel('Longitude', { exact: true }).fill('77.68'); await page.getByRole('button', { name: 'Confirm area & search' }).click(); await expect(page.getByRole('alert')).toContainText('Enter latitude');
  await sampleSearch(page); await expect(page.getByText('3 results loaded')).toBeVisible();
});

test('coverage, service failures, partial pages, map failure, and input preservation', async ({ page }, info) => {
  await page.goto('/?demo=unknown'); await sampleSearchEmpty(); await expect(page.getByText('Coverage for this area is unknown.', { exact: false })).toBeVisible();
  await page.goto('/?demo=unavailable'); await page.getByRole('button', { name: 'Pilkhuwa · sample area' }).click(); await page.getByRole('button', { name: 'Confirm area & search' }).click(); await expect(page.getByRole('alert')).toContainText('The service is unavailable'); await expect(page.getByLabel('Latitude', { exact: true })).toHaveValue('28.73000');
  if (info.project.name === 'chromium') await page.screenshot({ path: `${artifacts}/service-error-en.png`, fullPage: true });
  await page.goto('/?demo=partial'); await sampleSearch(page); await page.getByRole('button', { name: 'Load more records' }).click(); await expect(page.getByRole('alert')).toBeVisible(); await expect(page.getByText('3 results loaded')).toBeVisible(); await expect(page.getByText('All returned records loaded')).toHaveCount(0);
  await page.goto('/?demo=map-error'); await sampleSearch(page); await expect(page.getByRole('heading', { name: 'Map unavailable' })).toBeVisible(); await openFirst(page);
  async function sampleSearchEmpty() { await page.getByRole('button', { name: 'Pilkhuwa · sample area' }).click(); await page.getByRole('button', { name: 'Confirm area & search' }).click(); await expect(page.getByRole('heading', { name: 'No published candidates returned' })).toBeVisible(); }
});

test('keyboard, semantic accessibility, both themes, and narrow reflow', async ({ page }, info) => {
  await page.goto('/'); await sampleSearch(page);
  await page.getByRole('button', { name: 'Select SAMPLE-KW-002', exact: true }).focus(); await page.keyboard.press('Enter'); await expect(page.getByRole('button', { name: 'Select SAMPLE-KW-002', exact: true })).toHaveAttribute('aria-pressed', 'true');
  for (const theme of ['light', 'dark']) {
    await page.getByLabel('Appearance', { exact: true }).selectOption(theme);
    const results = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa']).analyze();
    expect(results.violations.map(v => ({ id: v.id, targets: v.nodes.map(n => n.target) }))).toEqual([]);
  }
  await page.goto('/kilns/SAMPLE-KW-001'); await expect(page.getByRole('heading', { name: 'Orchard edge', exact: true })).toBeVisible();
  const results = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa']).analyze(); expect(results.violations.map(v => ({ id: v.id, targets: v.nodes.map(n => n.target) }))).toEqual([]);
  await page.setViewportSize({ width: 320, height: 800 }); expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  if (info.project.name === 'chromium') { const snapshot = await page.locator('main').ariaSnapshot(); expect(snapshot).toContain('heading "Orchard edge"'); }
});

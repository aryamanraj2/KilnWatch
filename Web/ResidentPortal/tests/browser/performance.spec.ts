import { test, expect } from '@playwright/test';
import { mkdir, writeFile } from 'node:fs/promises';
declare global { interface Window { kwMetrics: { lcp: number; cls: number; maxEvent: number } } }

test('production mobile performance sample and 200% reflow', async ({ page, context }, info) => {
  test.skip(info.project.name !== 'chromium', 'CDP measurement is Chromium-specific');
  await page.setViewportSize({ width: 390, height: 844 });
  const cdp = await context.newCDPSession(page);
  await cdp.send('Network.enable'); await cdp.send('Network.setCacheDisabled', { cacheDisabled: true });
  await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: 150, downloadThroughput: 1500 * 1024 / 8, uploadThroughput: 750 * 1024 / 8 });
  await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 });
  await page.addInitScript(() => {
    window.kwMetrics = { lcp: 0, cls: 0, maxEvent: 0 };
    new PerformanceObserver(list => { for (const entry of list.getEntries()) window.kwMetrics.lcp = entry.startTime; }).observe({ type: 'largest-contentful-paint', buffered: true });
    new PerformanceObserver(list => { for (const entry of list.getEntries()) if ('hadRecentInput' in entry && !entry.hadRecentInput && 'value' in entry && typeof entry.value === 'number') window.kwMetrics.cls += entry.value; }).observe({ type: 'layout-shift', buffered: true });
    const eventOptions = { type: 'event', buffered: true, durationThreshold: 16 };
    new PerformanceObserver(list => { for (const entry of list.getEntries()) window.kwMetrics.maxEvent = Math.max(window.kwMetrics.maxEvent, entry.duration); }).observe(eventOptions);
  });
  await page.goto('/'); await expect(page.getByRole('button', { name: 'Pilkhuwa · sample area' })).toBeVisible();
  await page.getByRole('button', { name: 'Pilkhuwa · sample area' }).click(); const started = Date.now();
  await page.getByRole('button', { name: 'Confirm area & search' }).click(); await expect(page.getByText('3 results loaded')).toBeVisible(); const searchMs = Date.now() - started;
  await page.getByRole('button', { name: 'Map', exact: true }).click(); await expect(page.getByText('Illustrative map', { exact: true })).toBeVisible();
  const metrics = await page.evaluate(() => ({ ...window.kwMetrics, navigation: performance.getEntriesByType('navigation')[0]?.toJSON(), resources: performance.getEntriesByType('resource').map(e => e.toJSON()) }));
  await mkdir('docs/screens', { recursive: true }); await writeFile('docs/screens/performance.json', JSON.stringify({ measured_at: new Date().toISOString(), browser: await page.context().browser()?.version(), conditions: { viewport: '390x844', cpuSlowdown: 4, latencyMs: 150, downloadKbps: 1500, uploadKbps: 750, cache: 'disabled', server: 'local production preview', sampleRuns: 1 }, searchToResultsMs: searchMs, metrics, limitation: 'A single local laboratory sample, not an INP field measurement or a performance score.' }, null, 2));
  // Browser page zoom at 200% is approximated by layout zoom with a halved CSS viewport.
  // The explicit 320px layout proof remains the more stringent narrow-screen test.
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.evaluate(() => { document.documentElement.style.zoom = '2'; });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  await expect(page.getByRole('button', { name: 'Confirm area & search' })).toBeVisible();
});

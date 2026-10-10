import type { Page } from '@playwright/test';
// Geographic provider availability is checked separately during visual review.
// Functional tests exercise Leaflet against a deterministic local tile response.
export async function mockMapTiles(page: Page) {
  await page.route('https://tile.openstreetmap.org/**', route => route.fulfill({
    contentType: 'image/svg+xml',
    body: '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256"><rect width="256" height="256" fill="#e3e6da"/><path d="M0 64H256M64 0V256M192 0V256M0 192H256" stroke="#ccd1c0" fill="none"/><path d="M0 128H256" stroke="#fafafa" stroke-width="8"/></svg>',
  }));
}

import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: './tests/browser', fullyParallel: false, workers: 1, retries: 0,
  testMatch: process.env.KW_PERFORMANCE ? '**/performance.spec.ts' : '**/portal.spec.ts',
  timeout: 30000, expect: { timeout: 8000 }, reporter: [['list'], ['json', { outputFile: 'test-results/browser-results.json' }]],
  use: { baseURL: process.env.KW_PERFORMANCE ? 'http://127.0.0.1:4173' : 'http://127.0.0.1:5173', viewport: { width: 1440, height: 1000 }, screenshot: 'only-on-failure', trace: 'retain-on-failure' },
  projects: [{ name: 'chromium', use: { browserName: 'chromium' } }, { name: 'webkit', use: { browserName: 'webkit' } }],
  webServer: { command: process.env.KW_PERFORMANCE ? 'npm run preview -- --port 4173 --strictPort' : 'npm run dev', url: process.env.KW_PERFORMANCE ? 'http://127.0.0.1:4173' : 'http://127.0.0.1:5173', reuseExistingServer: !process.env.CI, timeout: 30000 },
});

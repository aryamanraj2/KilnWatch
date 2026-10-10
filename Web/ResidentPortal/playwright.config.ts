import { defineConfig } from '@playwright/test';
const liveCheck = process.env.KW_LIVE_CHECK === '1';
const baseURL = liveCheck ? 'http://127.0.0.1:5174' : process.env.KW_PERFORMANCE ? 'http://127.0.0.1:4173' : 'http://127.0.0.1:5173';
export default defineConfig({
  testDir: './tests/browser', fullyParallel: false, workers: 1, retries: 0,
  testMatch: liveCheck ? '**/live.spec.ts' : process.env.KW_PERFORMANCE ? '**/performance.spec.ts' : '**/portal.spec.ts',
  timeout: 30000, expect: { timeout: 8000 }, reporter: [['list'], ['json', { outputFile: 'test-results/browser-results.json' }]],
  use: { baseURL, viewport: { width: 1440, height: 1000 }, screenshot: 'only-on-failure', trace: 'retain-on-failure' },
  projects: [{ name: 'chromium', use: { browserName: 'chromium' } }, { name: 'webkit', use: { browserName: 'webkit' } }],
  webServer: {
    command: liveCheck ? 'npm run dev -- --port 5174 --strictPort' : process.env.KW_PERFORMANCE ? 'npm run preview -- --port 4173 --strictPort' : 'npm run dev',
    url: baseURL, reuseExistingServer: !liveCheck && !process.env.CI, timeout: 30000,
    ...(liveCheck ? { env: { VITE_DATA_MODE: 'live', VITE_PUBLIC_API_BASE_URL: 'https://public.example.test', VITE_PUBLIC_IMAGE_HOSTS: 'evidence.example.test' } } : {}),
  },
});

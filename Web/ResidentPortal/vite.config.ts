import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: { host: '127.0.0.1', port: 5173, strictPort: true },
  build: { sourcemap: false },
  test: { environment: 'jsdom', include: ['tests/**/*.test.{ts,tsx}'], setupFiles: ['tests/setup.ts'], fileParallelism: false },
});

import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: '.',
  timeout: 30_000,
  retries: 0,
  reporter: 'list',
  use: {
    baseURL: 'http://localhost:1337',
    headless: true,
    viewport: { width: 1200, height: 864 },
  },
  // Serve the production web build on 1337 for the duration of the run.
  // `npm test` builds first (flutter build web), then runs Playwright, which
  // starts this server. reuseExistingServer lets you point at an already-running
  // dev server (e.g. `flutter run -d web-server --web-port 1337`) instead.
  webServer: {
    command: 'python3 -m http.server 1337 --directory ../build/web',
    url: 'http://localhost:1337/index.html',
    reuseExistingServer: true,
    timeout: 60_000,
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],
});

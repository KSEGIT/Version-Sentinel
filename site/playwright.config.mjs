import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: './tests',
  testMatch: '**/*.spec.mjs',
  outputDir: './reports/test-results',
  fullyParallel: true,
  workers: 3,
  reporter: [['list'], ['html', { outputFolder: 'reports/playwright', open: 'never' }], ['json', { outputFile: 'reports/results.json' }]],
  use: { baseURL: 'http://127.0.0.1:4173/Version-Sentinel/', browserName: 'chromium', screenshot: 'only-on-failure' },
  projects: [375, 768, 1440].flatMap(width => ['light', 'dark'].map(colorScheme => ({ name: `${width}-${colorScheme}`, use: { viewport: { width, height: 900 }, colorScheme } }))),
  webServer: { command: 'npm run serve', url: 'http://127.0.0.1:4173/Version-Sentinel/assets/OFL.txt', reuseExistingServer: !process.env.CI }
});

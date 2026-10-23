const { chromium } = require('@playwright/test');

module.exports = {
  ci: {
    collect: {
      url: ['http://127.0.0.1:4174/Version-Sentinel/'],
      // The project base path requires the same prefix-aware server as tests.
      startServerCommand: 'PORT=4174 npm run serve',
      startServerReadyPattern: 'Serving',
      chromePath: chromium.executablePath(),
      numberOfRuns: 3,
      settings: { formFactor: 'mobile', chromeFlags: '--headless --no-sandbox' },
    },
    assert: {
      assertions: {
        'categories:performance': ['error', { minScore: 0.95, aggregationMethod: 'pessimistic' }],
        'categories:accessibility': ['error', { minScore: 0.95, aggregationMethod: 'pessimistic' }],
        'categories:best-practices': ['error', { minScore: 0.95, aggregationMethod: 'pessimistic' }],
        'categories:seo': ['error', { minScore: 0.95, aggregationMethod: 'pessimistic' }],
        'cumulative-layout-shift': ['error', { maxNumericValue: 0, aggregationMethod: 'pessimistic' }],
      },
    },
    upload: { target: 'filesystem', outputDir: 'reports/lighthouse' },
  },
};

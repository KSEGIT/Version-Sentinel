import { test, expect } from '@playwright/test';

async function frozenDemo(page) {
  await page.clock.install({ time: 0 });
  await page.clock.pauseAt(1000);
  await page.goto('./');
}
const step = (page, name) => page.locator(`[data-demo-step="${name}"] .demo-visual`);

// Missing controller, changed order, or unpinned retry must fail this test.
test('automatic transcript types, blocks with exit 2, looks up, records, and retries the exact version', async ({ page }) => {
  await frozenDemo(page);
  await expect(page.locator('#terminal-demo')).toHaveAttribute('data-state', 'playing');
  await expect(step(page, 'block')).toBeHidden();
  const initial = await step(page, 'edit').textContent();
  await page.clock.runFor(300);
  expect((await step(page, 'edit').textContent()).length).toBeGreaterThan(initial.length);
  await expect(step(page, 'block')).toBeHidden();
  await page.clock.runFor(1500);
  const expected = [
    ['block', 'exit 2'], ['lookup', 'https://www.npmjs.com/package/lodash'],
    ['record', '/vs-record npm lodash 4.17.21'], ['retry', '> npm install lodash@4.17.21'], ['result', 'ALLOWED']
  ];
  for (let index = 0; index < expected.length; index++) {
    const [name, text] = expected[index];
    await expect(step(page, name)).toBeVisible();
    await expect(step(page, name)).toContainText(text);
    if (expected[index + 1]) await expect(step(page, expected[index + 1][0])).toBeHidden();
    await page.clock.runFor(800);
  }
  await expect(page.locator('#terminal-demo')).toHaveAttribute('data-state', 'complete');
  await expect(page.locator('#demo-pause')).toBeDisabled();
  await expect(page.locator('.demo-static')).toHaveCount(6);
  await expect(page.locator('.demo-visual[aria-hidden="true"]')).toHaveCount(6);
  await expect(page.locator('#terminal-demo [aria-live]')).toHaveCount(0);
});

// Cosmetic pause labels and leftover replay timers change the visible text here.
test('pause stops typing, resume continues, and rapid replay has no overlap or layout shifts', async ({ page }) => {
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.addInitScript(() => {
    window.shifts = [];
    new PerformanceObserver(list => window.shifts.push(...list.getEntries().map(entry => entry.value))).observe({ type: 'layout-shift', buffered: true });
  });
  await frozenDemo(page);
  const bounds = () => page.locator('#terminal-demo').evaluate(node => { const box = node.getBoundingClientRect(); return { x: box.x + scrollX, y: box.y + scrollY, width: box.width, height: box.height }; });
  const before = await bounds();
  await page.clock.runFor(300);
  await page.locator('#demo-pause').click();
  await expect(page.locator('#terminal-demo')).toHaveAttribute('data-state', 'paused');
  const paused = await step(page, 'edit').textContent();
  await page.clock.runFor(3000);
  await expect(step(page, 'edit')).toHaveText(paused);
  await expect(step(page, 'block')).toBeHidden();
  await page.getByRole('button', { name: 'Resume demo' }).click();
  await page.clock.runFor(300);
  expect((await step(page, 'edit').textContent()).length).toBeGreaterThan(paused.length);
  await page.clock.runFor(7000);
  await expect(page.locator('#terminal-demo')).toHaveAttribute('data-state', 'complete');
  for (let index = 0; index < 5; index++) {
    await page.locator('#demo-replay').click();
    await page.clock.runFor(120);
  }
  await expect(step(page, 'block')).toBeHidden();
  await page.clock.runFor(7000);
  await expect(page.locator('#terminal-demo')).toHaveAttribute('data-state', 'complete');
  expect(await bounds()).toEqual(before);
  expect(await page.evaluate(() => window.shifts.reduce((sum, value) => sum + value, 0))).toBe(0);
  expect(errors).toEqual([]);
});

// A missed preference event leaves timers and hidden rows active.
test('reduced motion before and during playback immediately shows the complete transcript', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto('./');
  await expect(page.locator('#terminal-demo')).toHaveAttribute('data-state', 'complete');
  await expect(page.locator('#demo-result')).toBeVisible();
  await expect(step(page, 'result')).toBeVisible();
  await page.locator('#demo-replay').click();
  await expect(step(page, 'result')).toBeVisible();
  await page.emulateMedia({ reducedMotion: 'no-preference' });
  await page.locator('#demo-replay').click();
  await expect(page.locator('#terminal-demo')).toHaveAttribute('data-state', 'playing');
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await expect(page.locator('#terminal-demo')).toHaveAttribute('data-state', 'complete');
  await expect(step(page, 'result')).toBeVisible();
  expect(await page.evaluate(() => document.getAnimations().length)).toBe(0);
});

// Native transition observation catches removal of the existing skip handler.
test('enabling reduced motion cancels an active native theme transition', async ({ page }) => {
  await page.addInitScript(() => {
    const start = document.startViewTransition.bind(document);
    document.startViewTransition = callback => {
      const transition = start(callback);
      window.themeTransition = transition;
      window.transitionSkips = 0;
      const skip = transition.skipTransition.bind(transition);
      transition.skipTransition = () => { window.transitionSkips++; skip(); };
      return transition;
    };
  });
  await page.goto('./');
  await page.addStyleTag({ content: '::view-transition-old(root),::view-transition-new(root){animation-duration:10s}' });
  const oldTheme = await page.locator('html').getAttribute('data-theme');
  await page.locator('#theme-toggle').click();
  await page.evaluate(() => window.themeTransition.ready);
  expect(await page.evaluate(() => document.getAnimations().length)).toBeGreaterThan(0);
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await expect.poll(() => page.evaluate(() => window.transitionSkips)).toBe(1);
  await page.evaluate(() => window.themeTransition.finished);
  await expect(page.locator('html')).toHaveAttribute('data-theme', oldTheme === 'light' ? 'dark' : 'light');
  expect(await page.evaluate(() => document.getAnimations().length)).toBe(0);
});

// Omitting any agent/ecosystem disclosure or hiding it from either input breaks this.
test('all registry details support hover and keyboard focus and reduced motion restores grid states', async ({ page }) => {
  await page.goto('./');
  await expect(page.locator('.ecosystem-list .registry-info')).toHaveCount(4);
  await expect(page.locator('.agent-list .registry-info')).toHaveCount(6);
  for (const card of await page.locator('.ecosystem-list > div, .agent-list > li').all()) {
    const detail = card.locator('.registry-detail');
    const before = await card.evaluate(node => node.offsetHeight);
    await card.hover();
    await expect(detail).toBeVisible();
    await page.mouse.move(0, 0);
    await expect(detail).toBeHidden();
    await card.locator('.registry-toggle').focus();
    await expect(detail).toBeVisible();
    await page.keyboard.press('Enter');
    await expect(card.locator('.registry-info')).toHaveAttribute('open', '');
    await expect(detail).toBeVisible();
    expect(await card.evaluate(node => node.offsetHeight)).toBe(before);
  }
  for (const detail of await page.locator('.agent-list .registry-detail').all()) {
    await expect(detail).toContainText('same npm, PyPI, crates.io, and NuGet registries');
  }
  await expect(page.locator('.agent-list a[href^="#install-"]')).toHaveCount(6);
  await expect(page.locator('.agent-list > li').last()).toContainText('No automatic hook blocking.');
  await page.emulateMedia({ reducedMotion: 'reduce' });
  for (const item of await page.locator('.ecosystem-list > div, .agent-list > li').all()) {
    expect(await item.evaluate(node => getComputedStyle(node).opacity)).toBe('1');
  }
});

test('all registry details are discoverable on a touch mobile viewport', async ({ browser }) => {
  const context = await browser.newContext({ viewport: { width: 375, height: 900 }, isMobile: true, hasTouch: true });
  const page = await context.newPage();
  await page.goto('http://127.0.0.1:4173/Version-Sentinel/');
  await expect(page.locator('.registry-toggle')).toHaveCount(10);
  for (const card of await page.locator('.ecosystem-list > div, .agent-list > li').all()) {
    const before = await card.evaluate(node => node.offsetHeight);
    await card.locator('.registry-toggle').tap();
    await expect(card.locator('.registry-detail')).toBeVisible();
    await expect(card.locator('.registry-info')).toHaveAttribute('open', '');
    expect(await card.evaluate(node => node.offsetHeight)).toBe(before);
  }
  await context.close();
});

test('all registry disclosures work without JavaScript', async ({ browser }) => {
  const context = await browser.newContext({ javaScriptEnabled: false, viewport: { width: 375, height: 900 } });
  const page = await context.newPage();
  await page.goto('http://127.0.0.1:4173/Version-Sentinel/');
  await expect(page.locator('.registry-toggle')).toHaveCount(10);
  for (const card of await page.locator('.ecosystem-list > div, .agent-list > li').all()) {
    await card.locator('.registry-toggle').click();
    await expect(card.locator('.registry-info')).toHaveAttribute('open', '');
    await expect(card.locator('.registry-detail')).toBeVisible();
  }
  await expect(page.locator('#demo-result')).toBeVisible();
  await context.close();
});

// Simulate an engine with no scroll-animation support at the CSS boundary.
test('unsupported scroll CSS keeps every diagram and grid readable', async ({ page }) => {
  await page.route('**/styles.css', async route => {
    const response = await route.fetch();
    await route.fulfill({ response, body: (await response.text()).replaceAll('@supports ', '@supports (unsupported-feature: true) and ') });
  });
  await page.goto('./');
  for (const item of await page.locator('.ecosystem-list > div, .agent-list > li, .flow-connector').all()) {
    expect(await item.evaluate(node => getComputedStyle(node).opacity)).toBe('1');
    expect(await item.evaluate(node => getComputedStyle(node).transform)).toBe('none');
  }
  await expect(page.locator('.scroll-progress')).toBeHidden();
});

import { test, expect } from '@playwright/test';

const agents = ['claude', 'kimi', 'gemini', 'codex', 'copilot', 'zed'];
const claudeCommand = '/plugin marketplace add https://github.com/KSEGIT/Version-Sentinel.git\n/plugin install version-sentinel@version-sentinel-marketplace';

// Catch hero feedback sent only to the distant shared live region, layout
// changes on feedback, lost focus, and a failed attempt that cannot be retried.
test('hero copy feedback stays beside the control on success, denial, and retry', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.addInitScript(() => {
    const write = navigator.clipboard.writeText.bind(navigator.clipboard);
    let attempts = 0;
    navigator.clipboard.writeText = text => ++attempts === 2
      ? Promise.reject(new DOMException('Denied', 'NotAllowedError')) : write(text);
  });
  await page.goto('./');
  await page.evaluate(() => document.fonts.ready);
  const button = page.getByRole('button', { name: 'Copy commands', exact: true });
  const feedback = page.locator('.install-command .copy-feedback');
  await button.scrollIntoViewIfNeeded();
  const geometry = () => page.locator('#top, .install-command, .command-heading, #hero-install-command, .text-link').evaluateAll(nodes => nodes.map(node => {
    const { x, y, width, height } = node.getBoundingClientRect();
    return { x, y, width, height };
  }));
  const before = await geometry();
  for (const denied of [false, true, false]) {
    await button.focus();
    await page.keyboard.press('Enter');
    await expect(feedback).toContainText(denied ? /clipboard unavailable.*select.*commands.*copy.*manually/i : /copied/i);
    await expect(feedback).toBeVisible();
    await expect(feedback).toBeInViewport({ ratio: 1 });
    await expect(button).toBeFocused();
    expect(await feedback.evaluate((node, target) => {
      const box = node.getBoundingClientRect();
      const control = document.querySelector(target).getBoundingClientRect();
      return box.top >= control.bottom && box.top - control.bottom <= 32;
    }, '[data-copy-target="hero-install-command"]')).toBe(true);
    expect(await geometry()).toEqual(before);
    expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(claudeCommand);
  }
  await expect(page.getByRole('status')).toHaveCount(1);
  await expect(page.getByRole('status')).toHaveAttribute('aria-live', 'polite');
});

// Catch broken system updates and an explicit choice that gets overwritten.
test('theme follows live system changes until the user chooses, then persists on reload', async ({ page }, testInfo) => {
  await page.goto('./');
  await expect(page.locator('html')).toHaveAttribute('data-theme', testInfo.project.use.colorScheme);
  await page.emulateMedia({ colorScheme: 'dark' });
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  await expect(page.getByRole('button', { name: /switch to light theme/i })).toBeVisible();
  await page.emulateMedia({ colorScheme: 'light' });
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
  await page.getByRole('button', { name: /switch to dark theme/i }).click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  await page.emulateMedia({ colorScheme: 'dark' });
  await page.emulateMedia({ colorScheme: 'light' });
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  await page.reload();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
});

// Catch a stored choice applied only after the main module executes.
test('stored explicit theme applies before the main module loads', async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('version-sentinel-theme', 'dark'));
  await page.route('**/main.js', route => route.abort());
  await page.emulateMedia({ colorScheme: 'light' });
  await page.goto('./');
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  await expect(page.locator('#theme-toggle')).toBeHidden();
});

// Catch storage exceptions escaping initialization or preventing user changes.
test('denied storage leaves the theme and other controls usable', async ({ page }) => {
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.addInitScript(() => {
    for (const method of ['getItem', 'setItem']) Storage.prototype[method] = () => { throw new DOMException('Denied', 'SecurityError'); };
  });
  await page.emulateMedia({ colorScheme: 'light' });
  await page.goto('./');
  await page.getByRole('button', { name: /switch to dark theme/i }).click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  await page.emulateMedia({ colorScheme: 'dark' });
  await page.emulateMedia({ colorScheme: 'light' });
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  await expect(page.getByRole('tab')).toHaveCount(6);
  expect(errors).toEqual([]);
});

// Catch changed command bytes, missing feedback, or the wrong target.
test('clipboard receives the exact hero and selected install commands', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.goto('./');
  await page.getByRole('button', { name: 'Copy commands', exact: true }).click();
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(claudeCommand);
  await expect(page.getByRole('status')).toContainText(/copied/i);
  await page.getByRole('tab', { name: 'Gemini CLI', exact: true }).click();
  await page.getByRole('button', { name: 'Copy Gemini CLI commands' }).click();
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe('gemini extensions install https://github.com/KSEGIT/Version-Sentinel\nbash ~/.gemini/extensions/version-sentinel/platforms/gemini/setup.sh');
});

// Catch failed clipboard access hiding commands or promising success.
for (const unavailable of [false, true]) test(`clipboard ${unavailable ? 'unavailable' : 'denied'} keeps manual copying possible`, async ({ page }) => {
  await page.addInitScript(unavailable => {
    if (unavailable) Object.defineProperty(navigator, 'clipboard', { value: undefined });
    else Object.defineProperty(navigator.clipboard, 'writeText', { value: async () => { throw new DOMException('Denied', 'NotAllowedError'); } });
  }, unavailable);
  await page.goto('./');
  await page.getByRole('button', { name: 'Copy commands', exact: true }).click();
  await expect(page.getByRole('status')).toContainText(/select.*command.*copy.*manually/i);
  await expect(page.locator('#hero-install-command')).toBeVisible();
  await expect(page.locator('#hero-install-command')).toHaveText(claudeCommand);
});

// Catch broken associations, roving tabindex, keyboard wrap, or panel selection.
test('installation tabs support click, arrows, Home, End, and standard associations', async ({ page }) => {
  await page.goto('./');
  const tabs = page.getByRole('tab');
  await expect(page.getByRole('tablist', { name: 'Installation options' })).toBeVisible();
  await expect(tabs).toHaveCount(6);
  for (let index = 0; index < agents.length; index++) {
    await expect(tabs.nth(index)).toHaveAttribute('aria-controls', `install-${agents[index]}`);
    await expect(page.locator(`#install-${agents[index]}`)).toHaveAttribute('aria-labelledby', await tabs.nth(index).getAttribute('id'));
  }
  await tabs.first().focus();
  for (const [key, index] of [['End', 5], ['ArrowRight', 0], ['ArrowLeft', 5], ['Home', 0], ['ArrowRight', 1]]) {
    await page.keyboard.press(key);
    await expect(tabs.nth(index)).toBeFocused();
    await expect(tabs.nth(index)).toHaveAttribute('aria-selected', 'true');
    await expect(tabs.nth(index)).toHaveAttribute('tabindex', '0');
    await expect(page.getByRole('tabpanel')).toHaveCount(1);
    await expect(page.locator(`#install-${agents[index]}`)).toBeVisible();
    await expect(page.locator('[role="tab"][tabindex="-1"]')).toHaveCount(5);
  }
  await tabs.nth(3).click();
  await expect(page.locator('#install-codex')).toBeVisible();
  await page.keyboard.press('Tab');
  await expect(page.locator('#install-codex')).toBeFocused();
});

// Catch enhanced tabs hiding initial, agent-entry, or history-linked instructions.
test('agent links, initial fragments, and history select their install panel', async ({ page }) => {
  await page.goto('./#install-zed');
  await expect(page.locator('#install-zed')).toBeVisible();
  await expect(page.getByRole('tab', { name: 'Zed', exact: true })).toHaveAttribute('aria-selected', 'true');
  for (const agent of agents) {
    await page.locator(`.agent-list a[href="#install-${agent}"]`).click();
    await expect(page.locator(`#install-${agent}`)).toBeVisible();
  }
  await page.goBack();
  await expect(page.locator('#install-copilot')).toBeVisible();
  await page.goForward();
  await expect(page.locator('#install-zed')).toBeVisible();
});

// Catch controls changing header/hero geometry when the script arrives late.
test('enhancing controls reserves their geometry before script arrival', async ({ page }) => {
  let release;
  const ready = new Promise(resolve => { release = resolve; });
  await page.route('**/main.js', async route => { await ready; await route.continue(); });
  await page.goto('./', { waitUntil: 'commit' });
  await page.locator('#hero-install-command').waitFor();
  await page.evaluate(() => document.fonts.ready);
  const before = await page.locator('#top').boundingBox();
  const commandBefore = await page.locator('.install-command').boundingBox();
  release();
  await expect(page.locator('#theme-toggle')).toBeVisible();
  expect(await page.locator('#top').boundingBox()).toEqual(before);
  expect(await page.locator('.install-command').boundingBox()).toEqual(commandBefore);
});

// Catch missing browser APIs and animation that ignores reduced motion.
test('theme works without View Transitions and skips animation with reduced motion', async ({ page }) => {
  // A present API must not be called while reduced motion is active.
  await page.addInitScript(() => { document.startViewTransition = () => { throw new Error('Reduced motion must bypass View Transitions'); }; });
  await page.emulateMedia({ colorScheme: 'light', reducedMotion: 'reduce' });
  await page.goto('./');
  await page.getByRole('button', { name: /switch to dark theme/i }).click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  expect(await page.evaluate(() => document.getAnimations().length)).toBe(0);
  // Separately exercise the fallback in a browser without that API.
  await page.evaluate(() => { document.startViewTransition = undefined; });
  await page.emulateMedia({ reducedMotion: 'no-preference' });
  await page.getByRole('button', { name: /switch to light theme/i }).click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
});

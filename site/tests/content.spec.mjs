import { test, expect } from '@playwright/test';

// Removing the heading, final transcript, install panels, or metadata must fail these tests.
const sections = ['problem', 'how-it-works', 'before-after', 'ecosystems', 'agents', 'comparison', 'install'];
const agents = ['claude', 'kimi', 'gemini', 'codex', 'copilot', 'zed'];

test('page has the complete content and no document overflow', async ({ page }, testInfo) => {
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
  const failures = [];
  page.on('response', response => { if (response.url().startsWith('http://127.0.0.1:4173/') && !response.ok()) failures.push(`${response.status()} ${response.url()}`); });
  await page.goto('/Version-Sentinel/');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Check dependency versions before your agent writes them.');
  for (const id of sections) await expect(page.locator(`#${id}`)).toHaveCount(1);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  expect(await page.locator('[id]').evaluateAll(nodes => { const ids = nodes.map(n => n.id); return ids.filter((id, i) => ids.indexOf(id) !== i); })).toEqual([]);
  for (const href of await page.locator('a[href^="#"]').evaluateAll(nodes => nodes.map(n => n.getAttribute('href')))) await expect(page.locator(href)).toHaveCount(1);
  for (const target of ['LICENSE', 'CHANGELOG.md', 'PRIVACY.md', 'TERMS.md']) await expect(page.locator(`footer a[href="https://github.com/KSEGIT/Version-Sentinel/blob/main/${target}"]`)).toHaveCount(1);
  await expect(page.locator('footer a[href="https://github.com/KSEGIT/Version-Sentinel"]')).toHaveCount(1);
  await expect(page.locator('link[rel="canonical"]')).toHaveAttribute('href', 'https://ksegit.github.io/Version-Sentinel/');
  for (const name of ['description', 'twitter:card']) await expect(page.locator(`meta[name="${name}"]`)).toHaveAttribute('content', /.+/);
  for (const property of ['og:title', 'og:description', 'og:url', 'og:image']) await expect(page.locator(`meta[property="${property}"]`)).toHaveAttribute('content', /.+/);
  await expect(page.locator('meta[property="og:image:width"]')).toHaveAttribute('content', '1200');
  await expect(page.locator('meta[property="og:image:height"]')).toHaveAttribute('content', '630');
  const resources = await page.locator('[src],link[href]').evaluateAll(nodes => nodes.map(n => n.getAttribute('src') || n.getAttribute('href')).filter(url => !url.startsWith('https:')));
  for (const resource of resources) expect((await page.request.get(new URL(resource, page.url()).href)).ok(), resource).toBe(true);
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: `reports/task-1/${testInfo.project.name}.png`, fullPage: true });
  expect(errors).toEqual([]);
  expect(failures).toEqual([]);
});

test('all installation instructions and final allowed result remain readable without JavaScript', async ({ browser }, testInfo) => {
  const context = await browser.newContext({ javaScriptEnabled: false, viewport: testInfo.project.use.viewport, colorScheme: testInfo.project.use.colorScheme });
  const page = await context.newPage();
  await page.goto('http://127.0.0.1:4173/Version-Sentinel/');
  for (const agent of agents) await expect(page.locator(`#install-${agent}`)).toBeVisible();
  await expect(page.locator('#demo-result')).toBeVisible();
  await expect(page.locator('#demo-result')).toContainText('ALLOWED');
  await expect(page.locator('#terminal-demo')).toContainText('npm install lodash@4.17.21');
  for (const command of ['/plugin marketplace add https://github.com/KSEGIT/Version-Sentinel.git', '/plugin install version-sentinel@version-sentinel-marketplace', '/plugins install https://github.com/KSEGIT/Version-Sentinel', 'gemini extensions install https://github.com/KSEGIT/Version-Sentinel', 'bash ~/.gemini/extensions/version-sentinel/platforms/gemini/setup.sh', 'codex plugin marketplace add KSEGIT/Version-Sentinel', 'codex plugin add version-sentinel']) await expect(page.locator('#install')).toContainText(command);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await context.close();
});

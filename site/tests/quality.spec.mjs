import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { mkdir, writeFile } from 'node:fs/promises';

test('320px reflow and 200 percent text preserve every control', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 900 });
  await page.emulateMedia({ reducedMotion: 'reduce' });
  for (const fontSize of [16, 32]) {
    await page.goto('./');
    await page.addStyleTag({ content: `html { font-size: ${fontSize}px !important }` });
    await page.evaluate(() => document.fonts.ready);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(320);
    for (const control of await page.locator('.terminal-controls button, .command-heading button').all()) {
      expect(await control.evaluate(node => {
        const rect = node.getBoundingClientRect();
        const parent = node.closest('.terminal, .install-command').getBoundingClientRect();
        return rect.left >= parent.left && rect.right <= parent.right;
      })).toBe(true);
    }
  }
});

test('tablet hero leaves enough width to read the terminal', async ({ page }) => {
  await page.goto('./');
  await page.evaluate(() => document.fonts.ready);
  const width = await page.locator('.terminal-figure').evaluate(node => node.getBoundingClientRect().width);
  expect(width).toBeGreaterThanOrEqual(300);
});

test('normal-motion initial content preserves accessible text contrast', async ({ page }, testInfo) => {
  await page.goto('./');
  await page.evaluate(() => document.fonts.ready);
  for (const item of await page.locator('.ecosystem-list > div, .agent-list > li').all()) {
    expect(await item.evaluate(node => getComputedStyle(node).opacity)).toBe('1');
  }
  const results = await new AxeBuilder({ page }).analyze();
  await mkdir('reports/axe', { recursive: true });
  const file = `reports/axe/normal-motion-${testInfo.project.name}.json`;
  await writeFile(file, JSON.stringify(results, null, 2));
  await testInfo.attach('axe-normal-motion', { path: file, contentType: 'application/json' });
  expect(results.violations).toEqual([]);
  expect(results.incomplete.filter(result => result.id === 'aria-prohibited-attr')).toEqual([]);
});

test('axe scans all install tabs with closed and open registry disclosures', async ({ page }, testInfo) => {
  test.setTimeout(180000);
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto('./');
  await page.evaluate(() => document.fonts.ready);
  const reports = [];
  for (const agent of ['claude', 'kimi', 'gemini', 'codex', 'copilot', 'zed']) {
    await page.locator(`[role="tab"][aria-controls="install-${agent}"]`).click();
    for (const open of [false, true]) {
      await page.evaluate(open => {
        for (const detail of document.querySelectorAll('.registry-info')) detail.open = open;
        document.activeElement?.blur();
      }, open);
      await page.mouse.move(0, 0);
      const results = await new AxeBuilder({ page }).analyze();
      reports.push({ agent, disclosures: open ? 'open' : 'closed', ...results });
    }
  }
  await mkdir('reports/axe', { recursive: true });
  const file = `reports/axe/${testInfo.project.name}.json`;
  await writeFile(file, JSON.stringify(reports, null, 2));
  await testInfo.attach('axe-all-states', { path: file, contentType: 'application/json' });
  // All impacts fail, including actionable lower-impact findings; no exclusions.
  expect(reports.flatMap(report => report.violations.map(violation => ({ agent: report.agent, disclosures: report.disclosures, violation })))).toEqual([]);
  expect(reports.flatMap(report => report.incomplete.filter(result => result.id === 'aria-prohibited-attr'))).toEqual([]);
});

test('final full-page screenshot after fonts and normal scroll reveal', async ({ page }, testInfo) => {
  await page.goto('./');
  await page.evaluate(() => document.fonts.ready);
  await expect(page.locator('#terminal-demo')).toHaveAttribute('data-state', 'complete', { timeout: 15000 });
  const end = await page.evaluate(() => document.documentElement.scrollHeight - innerHeight);
  for (let y = 0; y <= end + 200; y += 200) {
    await page.evaluate(y => scrollTo(0, y), y);
    await page.waitForTimeout(25);
  }
  await expect(page.locator('.agent-list > li').last()).toBeVisible();
  // Scroll timelines depend on the capture scroll position. Reduced motion
  // supplies their documented final state for a complete full-page image.
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.evaluate(() => scrollTo(0, 0));
  await mkdir('reports/screenshots', { recursive: true });
  const file = `reports/screenshots/final-${testInfo.project.name}.png`;
  await page.screenshot({ path: file, fullPage: true });
  await testInfo.attach(`final-${testInfo.project.name}`, { path: file, contentType: 'image/png' });
});

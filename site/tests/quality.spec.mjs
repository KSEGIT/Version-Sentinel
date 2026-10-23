import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { mkdir, writeFile } from 'node:fs/promises';

// Catch light-theme focus tokens leaking onto the permanently dark terminal.
test('keyboard focus has a visible, unobscured 3 to 1 terminal outline', async ({ page }) => {
  await page.goto('./');
  await page.locator('#demo-pause').focus();
  await page.keyboard.press('Enter'); // Keep both controls enabled while checking.
  for (const [key, id] of [['Tab', 'demo-replay'], ['Shift+Tab', 'demo-pause']]) {
    await page.keyboard.press(key);
    const control = page.locator(`#${id}`);
    await expect(control).toBeFocused();
    await expect(control).toBeInViewport({ ratio: 1 });
    const focus = await control.evaluate(node => {
      const style = getComputedStyle(node);
      const terminal = node.closest('.terminal');
      const luminance = color => {
        const rgb = color.match(/[\d.]+/g).slice(0, 3).map(Number).map(value => {
          const channel = value / 255;
          return channel <= .04045 ? channel / 12.92 : ((channel + .055) / 1.055) ** 2.4;
        });
        return rgb[0] * .2126 + rgb[1] * .7152 + rgb[2] * .0722;
      };
      const outline = luminance(style.outlineColor);
      const background = luminance(getComputedStyle(terminal).backgroundColor);
      const box = node.getBoundingClientRect();
      const parent = terminal.getBoundingClientRect();
      const extent = parseFloat(style.outlineWidth) + parseFloat(style.outlineOffset);
      return {
        ratio: (Math.max(outline, background) + .05) / (Math.min(outline, background) + .05),
        width: parseFloat(style.outlineWidth), style: style.outlineStyle,
        visible: node.matches(':focus-visible'),
        contained: box.left - extent >= parent.left && box.right + extent <= parent.right && box.top - extent >= parent.top && box.bottom + extent <= parent.bottom,
        unobscured: node.contains(document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2))
      };
    });
    expect(focus.ratio).toBeGreaterThanOrEqual(3);
    expect(focus.width).toBeGreaterThanOrEqual(2);
    expect(focus.style).toBe('solid');
    expect(focus.visible && focus.contained && focus.unobscured).toBe(true);
  }
});

// Catch feedback that clips commands/controls or shifts following content at
// narrow widths and enlarged text, for every copy control and both outcomes.
test('all copy feedback reserves geometry at 320px and 200 percent text', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.setViewportSize({ width: 320, height: 900 });
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.addInitScript(() => {
    const write = navigator.clipboard.writeText.bind(navigator.clipboard);
    let attempts = 0;
    navigator.clipboard.writeText = text => ++attempts % 2
      ? Promise.reject(new DOMException('Denied', 'NotAllowedError')) : write(text);
  });
  for (const fontSize of [16, 32]) {
    await page.goto('./');
    await page.addStyleTag({ content: `html { font-size: ${fontSize}px !important }` });
    await page.evaluate(() => document.fonts.ready);
    for (const target of ['hero-install-command', 'install-claude-command', 'install-kimi-command', 'install-gemini-command', 'install-codex-command']) {
      if (target !== 'hero-install-command') await page.locator(`[aria-controls="${target.replace('-command', '')}"]`).click();
      const button = page.locator(`[data-copy-target="${target}"]`);
      const block = button.locator('xpath=ancestor::*[contains(@class,"install-command") or contains(@class,"code-block")][1]');
      const feedback = block.locator('.copy-feedback');
      const geometry = () => page.evaluate(() => ({ height: document.documentElement.scrollHeight, boxes: [...document.querySelectorAll('.install-command, .code-block, #problem, footer')].map(node => {
        const { x, y, width, height } = node.getBoundingClientRect();
        return { x, y: y + scrollY, width, height };
      }) }));
      await button.scrollIntoViewIfNeeded();
      const before = await geometry();
      for (const denied of [true, false]) {
        await button.click();
        await expect(feedback).toContainText(denied ? /clipboard unavailable.*copy.*manually/i : /copied/i);
        expect(await geometry()).toEqual(before);
        expect(await feedback.evaluate(node => {
          const box = node.getBoundingClientRect();
          return box.left >= 0 && box.right <= innerWidth && node.scrollHeight <= node.clientHeight && getComputedStyle(node).visibility === 'visible';
        })).toBe(true);
        expect(await button.evaluate(node => {
          const box = node.getBoundingClientRect();
          return box.left >= 0 && box.right <= innerWidth;
        })).toBe(true);
      }
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(320);
    }
  }
});

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

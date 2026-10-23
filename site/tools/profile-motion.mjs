import { chromium } from '@playwright/test';
import { mkdir, writeFile } from 'node:fs/promises';
import { once } from 'node:events';

const output = new URL('../reports/final-fix/', import.meta.url);
await mkdir(output, { recursive: true });
const browser = await chromium.launch();
try {
  const context = await browser.newContext({ viewport: { width: 375, height: 900 }, deviceScaleFactor: 1, isMobile: true, hasTouch: true, colorScheme: 'light', reducedMotion: 'no-preference' });
  const page = await context.newPage();
  const cdp = await context.newCDPSession(page);
  await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 });
  await page.addInitScript(() => {
    window.motionProfile = { frames: [], longTasks: [], shifts: [], phase: 'load' };
    for (const type of ['longtask', 'layout-shift']) {
      new PerformanceObserver(list => {
        for (const entry of list.getEntries()) {
          if (type === 'longtask') window.motionProfile.longTasks.push({ start: entry.startTime, duration: entry.duration, phase: window.motionProfile.phase });
          else window.motionProfile.shifts.push({ start: entry.startTime, value: entry.value, recentInput: entry.hadRecentInput, phase: window.motionProfile.phase });
        }
      }).observe({ type, buffered: true });
    }
    let previous;
    const frame = time => {
      if (previous !== undefined) window.motionProfile.frames.push({ start: time, duration: time - previous, phase: window.motionProfile.phase });
      previous = time;
      requestAnimationFrame(frame);
    };
    requestAnimationFrame(frame);
  });
  await cdp.send('Tracing.start', { categories: 'devtools.timeline,blink.user_timing,cc,benchmark', transferMode: 'ReturnAsStream' });
  await page.goto(process.env.SITE_URL || 'http://127.0.0.1:4173/Version-Sentinel/');
  await page.evaluate(() => document.fonts.ready);
  await page.locator('#terminal-demo').scrollIntoViewIfNeeded();
  await page.waitForFunction(() => document.getElementById('terminal-demo').dataset.state === 'complete');
  await page.evaluate(() => { window.motionProfile.phase = 'replay'; });
  await page.locator('#demo-replay').click();
  await page.waitForFunction(() => document.getElementById('terminal-demo').dataset.state === 'complete');
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.locator('[data-copy-target="hero-install-command"]').scrollIntoViewIfNeeded();
  await page.evaluate(() => { window.motionProfile.phase = 'copy-success'; });
  await page.locator('[data-copy-target="hero-install-command"]').tap();
  await page.waitForFunction(() => document.getElementById('hero-install-command-feedback').textContent.includes('copied'));
  await page.waitForTimeout(600);
  await page.evaluate(() => {
    window.motionProfile.phase = 'copy-denied';
    navigator.clipboard.writeText = async () => { throw new DOMException('Denied', 'NotAllowedError'); };
  });
  await page.locator('[data-copy-target="hero-install-command"]').tap();
  await page.waitForFunction(() => document.getElementById('hero-install-command-feedback').textContent.includes('manually'));
  await page.waitForTimeout(600);
  await page.evaluate(() => { window.motionProfile.phase = 'scroll'; });
  // The harness scrolls in short increments; the production page has no scroll loop.
  await page.evaluate(() => scrollTo(0, 0));
  const height = await page.evaluate(() => document.documentElement.scrollHeight - innerHeight);
  for (let y = 0; y <= height; y += 160) {
    await page.evaluate(y => scrollTo(0, y), y);
    await page.waitForTimeout(45);
  }
  for (const toggle of await page.locator('.registry-toggle').all()) {
    await toggle.tap();
    await page.waitForTimeout(50);
  }
  await page.waitForTimeout(250);
  const measurements = await page.evaluate(() => window.motionProfile);
  const completed = once(cdp, 'Tracing.tracingComplete');
  await cdp.send('Tracing.end');
  const [{ stream }] = await completed;
  let trace = '';
  while (true) {
    const chunk = await cdp.send('IO.read', { handle: stream });
    trace += chunk.base64Encoded ? Buffer.from(chunk.data, 'base64').toString() : chunk.data;
    if (chunk.eof) break;
  }
  await cdp.send('IO.close', { handle: stream });
  await writeFile(new URL('motion-trace.json', output), trace);
  const phases = Object.fromEntries(['load', 'replay', 'copy-success', 'copy-denied', 'scroll'].map(phase => {
    const frames = measurements.frames.filter(frame => frame.phase === phase).map(frame => frame.duration).sort((a, b) => a - b);
    const longTasks = measurements.longTasks.filter(task => task.phase === phase);
    let run = 0, longestRun = 0;
    for (const frame of measurements.frames.filter(frame => frame.phase === phase)) {
      run = frame.duration > 25 ? run + 1 : 0;
      longestRun = Math.max(longestRun, run);
    }
    return [phase, { frames: frames.length, p95FrameMs: frames[Math.floor(frames.length * .95)] || 0, maxFrameMs: frames.at(-1) || 0, framesOver25ms: frames.filter(value => value > 25).length, longestConsecutiveOver25ms: longestRun, longTasks: longTasks.length, maxLongTaskMs: Math.max(0, ...longTasks.map(task => task.duration)) }];
  }));
  const summary = {
    browser: browser.version(), viewport: '375x900', cpuSlowdown: 4, mobile: true, touch: true,
    cls: measurements.shifts.filter(shift => !shift.recentInput).reduce((sum, shift) => sum + shift.value, 0),
    allLayoutShiftValues: measurements.shifts.reduce((sum, shift) => sum + shift.value, 0),
    phases, longTasks: measurements.longTasks, layoutShifts: measurements.shifts,
    limits: 'Headless Chromium on the host CPU with CDP 4x slowdown and a mobile viewport/touch emulation. rAF intervals measure callback cadence, not physical screen presentation. No device GPU, mobile network, heat, battery, or physical-phone measurement is claimed.'
  };
  await writeFile(new URL('motion-measurements.json', output), JSON.stringify(measurements, null, 2));
  await writeFile(new URL('motion-summary.json', output), JSON.stringify(summary, null, 2));
  console.log(JSON.stringify(summary, null, 2));
  if (summary.cls !== 0 || summary.allLayoutShiftValues !== 0) throw new Error('Motion caused layout shifts');
  if (Object.values(phases).some(phase => phase.longestConsecutiveOver25ms >= 5)) throw new Error('Sustained missed-frame cadence: inspect the trace');
} finally {
  await browser.close();
}

// Local code-native image sources; no image generation service or remote requests.
import { chromium } from '@playwright/test';
import { readFile } from 'node:fs/promises';
const publicRoot = new URL('../public/', import.meta.url);
const font = (await readFile(new URL('assets/IBMPlexSans-SemiBold-Latin1.woff2', publicRoot))).toString('base64');
const logo = (await readFile(new URL('assets/favicon.svg', publicRoot))).toString('base64');
const browser = await chromium.launch();
try {
  const page = await browser.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 1 });
  await page.setContent(`<style>@font-face{font-family:Plex;src:url(data:font/woff2;base64,${font})}*{box-sizing:border-box}body{margin:0;background:#142E32;color:#EAF2F1;font-family:Plex,Arial,sans-serif;padding:62px 72px}header{display:flex;align-items:center;gap:18px;font-size:28px}header img{width:62px;height:62px;background:#F4F7F7;border-radius:8px;padding:7px}h1{font-size:66px;line-height:1.08;letter-spacing:-2px;margin:43px 0 38px;max-width:950px}footer{border-top:1px solid #7E999B;padding-top:28px;display:flex;align-items:center;gap:25px;font-size:26px}.arrow{color:#7CDAD4}.allow{color:#7CDAD4;margin-left:auto}</style><header><img src="data:image/svg+xml;base64,${logo}" alt="">Version Sentinel</header><h1>Check dependency versions<br>before your agent writes them.</h1><footer><span>Registry check</span><span class="arrow">→</span><span>Local record</span><span class="arrow">→</span><span class="allow">✓ Allow the edit</span></footer>`);
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: new URL('assets/social.png', publicRoot).pathname });
  await page.setViewportSize({ width: 32, height: 32 });
  await page.setContent(`<style>body{margin:0;background:#F4F7F7}img{width:32px;height:32px}</style><img src="data:image/svg+xml;base64,${logo}" alt="">`);
  await page.screenshot({ path: new URL('assets/favicon-32.png', publicRoot).pathname });
} finally { await browser.close(); }

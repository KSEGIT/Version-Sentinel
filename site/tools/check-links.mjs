import { readFile, readdir, stat } from 'node:fs/promises';
import path from 'node:path';

const root = path.resolve(process.argv[2] || 'public');
const origin = 'https://ksegit.github.io';
const base = '/Version-Sentinel/';
const files = [];
async function walk(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) await walk(file);
    else files.push(file);
  }
}
await walk(root);
const references = [];
const documents = files.filter(file => /\.html$/.test(file));
const ids = new Map();
const decode = value => value.replaceAll('&amp;', '&').replaceAll('&quot;', '"').replaceAll('&#39;', "'");
for (const file of files) {
  if (!/\.(html|css|js|xml|txt)$/.test(file)) continue;
  const source = await readFile(file, 'utf8');
  const relative = path.relative(root, file).split(path.sep).join('/');
  const from = new URL(base + relative, origin);
  const add = value => references.push({ value: decode(value.trim()), from, relative });
  if (file.endsWith('.html')) {
    ids.set(file, new Set([...source.matchAll(/\bid\s*=\s*["']([^"']+)["']/g)].map(match => decode(match[1]))));
    for (const match of source.matchAll(/\b(?:href|src)\s*=\s*["']([^"']+)["']/g)) add(match[1]);
    for (const match of source.matchAll(/<meta\b[^>]*property=["']og:(?:url|image)["'][^>]*content=["']([^"']+)["']/g)) add(match[1]);
  }
  if (file.endsWith('.css')) for (const match of source.matchAll(/url\(\s*["']?([^\s"')]+)["']?\s*\)/g)) add(match[1]);
  if (file.endsWith('.js')) for (const match of source.matchAll(/\bimport\s+(?:[^;]*?\s+from\s+)?["']([^"']+)["']/g)) add(match[1]);
  if (file.endsWith('.xml')) for (const match of source.matchAll(/<loc>([^<]+)<\/loc>/g)) add(match[1]);
  if (path.basename(file) === 'robots.txt') for (const match of source.matchAll(/^Sitemap:\s*(\S+)/gm)) add(match[1]);
}
const failures = [];
const external = new Map();
for (const reference of references) {
  const { value, from, relative } = reference;
  try {
    const url = new URL(value, from);
    if (!['https:', 'http:'].includes(url.protocol)) throw new Error(`unsupported protocol ${url.protocol}`);
    if (url.origin !== origin) {
      url.hash = '';
      const previous = external.get(url.href) || [];
      external.set(url.href, [...previous, relative]);
      continue;
    }
    if (!url.pathname.startsWith(base)) throw new Error(`path must start with ${base}`);
    const file = path.resolve(root, decodeURIComponent(url.pathname.slice(base.length)) || 'index.html');
    if (!file.startsWith(root + path.sep)) throw new Error('path escapes public directory');
    if (!(await stat(file)).isFile()) throw new Error('target is not a file');
    if (url.hash && !ids.get(file)?.has(decodeURIComponent(url.hash.slice(1)))) throw new Error(`missing document ID ${url.hash}`);
  } catch (error) { failures.push(`${relative}: ${value}: ${error.message}`); }
}
const queue = [...external];
await Promise.all(Array.from({ length: 4 }, async () => {
  while (queue.length) {
    const [url, sources] = queue.shift();
    let lastError;
    for (let attempt = 1; attempt <= 2; attempt++) {
      try {
        const response = await fetch(url, { method: 'GET', signal: AbortSignal.timeout(12000), headers: { 'User-Agent': 'Version-Sentinel-link-check/1.0' } });
        await response.body?.cancel();
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        lastError = undefined;
        break;
      } catch (error) { lastError = error; }
    }
    if (lastError) failures.push(`${sources.join(', ')}: ${url}: ${lastError.message} (2 attempts, 12s timeout each)`);
  }
}));
for (const failure of failures) console.error(`FAIL ${failure}`);
console.log(`Validated ${documents.length} documents, ${references.length} links; ${failures.length} failures (${external.size} external URLs; production base mapped to public/)`);
if (failures.length) process.exitCode = 1;

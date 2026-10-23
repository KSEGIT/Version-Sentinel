import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, mkdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import http from 'node:http';

// Broken anchors, missing CSS assets, escaped paths, or ignored HTTP errors must fail.
test('link CLI validates the production mirror and reports every broken reference', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'sentinel-links-'));
  const server = http.createServer((req, res) => res.writeHead(req.url === '/ok' ? 200 : 503).end());
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const external = `http://127.0.0.1:${server.address().port}`;
  const run = () => new Promise(resolve => {
    const child = spawn(process.execPath, ['tools/check-links.mjs', root]);
    let output = '';
    for (const stream of [child.stdout, child.stderr]) stream.on('data', data => { output += data; });
    child.on('close', code => resolve({ code, output }));
  });
  try {
    await mkdir(path.join(root, 'assets'));
    await writeFile(path.join(root, 'index.html'), `<h1 id="ok">OK</h1><a href="#ok">Anchor</a><link href="styles.css"><a href="https://ksegit.github.io/Version-Sentinel/#ok">Canonical</a><a href="${external}/ok">External</a>`);
    await writeFile(path.join(root, 'styles.css'), 'body{background:url("assets/font.woff2")}');
    await writeFile(path.join(root, 'assets/font.woff2'), 'fixture');
    const good = await run();
    assert.equal(good.code, 0, good.output);
    assert.match(good.output, /Validated 1 documents, 5 links; 0 failures/);
    await writeFile(path.join(root, 'index.html'), `<a href="#missing">Bad anchor</a><link href="styles.css"><a href="/elsewhere/">Bad base</a><a href="${external}/bad">External error</a>`);
    await rm(path.join(root, 'assets/font.woff2'));
    const bad = await run();
    assert.equal(bad.code, 1);
    for (const issue of ['#missing', 'assets/font.woff2', '/elsewhere/', '503']) assert.ok(bad.output.includes(issue), bad.output);
    assert.match(bad.output, /4 failures/);
  } finally {
    server.close();
    await rm(root, { recursive: true, force: true });
  }
});

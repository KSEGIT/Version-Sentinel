import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';

test('dedicated audit port serves the exact project path and rejects the root', async () => {
  const child = spawn(process.execPath, ['tools/serve.mjs'], { env: { ...process.env, PORT: '4174' } });
  let output = '';
  child.stderr.on('data', data => { output += data; });
  try {
    const ready = await Promise.race([
      once(child.stdout, 'data').then(([data]) => String(data)),
      once(child, 'exit').then(() => output),
    ]);
    assert.match(ready, /Serving http:\/\/127\.0\.0\.1:4174\/Version-Sentinel\//);
    assert.equal((await fetch('http://127.0.0.1:4174/Version-Sentinel/')).status, 200);
    assert.equal((await fetch('http://127.0.0.1:4174/')).status, 404);
  } finally { child.kill(); }
});

import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { resolve, extname, sep } from 'node:path';
import { chromium } from 'playwright';

const [mode, directory, compiler] = process.argv.slice(2);
assert.ok(['frb', 'defines'].includes(mode));
const root = resolve(directory);
const types = { '.js': 'text/javascript', '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.html': 'text/html', '.json': 'application/json' };
const server = createServer(async (req, res) => {
  // Deliberately no COOP or COEP headers.
  let path = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  if (path.endsWith('/')) path += 'index.html';
  if (mode === 'frb' && path === '/index.html') {
    res.setHeader('Content-Type', 'text/html');
    return res.end('<!doctype html><title>Standalone FRB worker proof</title>');
  }
  const file = resolve(root, `.${path}`);
  if (!file.startsWith(root + sep)) { res.writeHead(403); return res.end(); }
  try {
    const body = await readFile(file);
    res.setHeader('Content-Type', types[extname(file)] ?? 'application/octet-stream');
    res.end(body);
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
let browser;
try {
  browser = await chromium.launch({ headless: true, ...(process.env.CHROMIUM_EXECUTABLE ? { executablePath: process.env.CHROMIUM_EXECUTABLE } : {}) });
  const page = await browser.newPage();
  const errors = [];
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
  const response = await page.goto(`http://127.0.0.1:${server.address().port}${mode === 'frb' ? '/' : '/proof/'}`);
  assert.equal(response.headers()['cross-origin-opener-policy'], undefined);
  assert.equal(response.headers()['cross-origin-embedder-policy'], undefined);
  assert.equal(await page.evaluate(() => crossOriginIsolated), false);

  async function workerValue(url, wasm) {
    return await page.evaluate(async ({ url, wasm }) => {
      // A classic worker; dynamic import loads Dart's wasm runtime without
      // turning the worker into a module worker (importScripts must work).
      const absolute = new URL(url, location.href).href;
      const script = wasm
        ? URL.createObjectURL(new Blob([`import(${JSON.stringify(absolute.replace(/\.wasm$/, '.mjs'))}).then(async m => (await m.compileStreaming(fetch(${JSON.stringify(absolute)}))).instantiate({})).then(i => i.invokeMain()).catch(e => postMessage(JSON.stringify({error:String(e),stack:e.stack})));`], { type: 'text/javascript' }))
        : absolute;
      const worker = new Worker(script, { type: 'classic' });
      try {
        return await new Promise((resolve, reject) => {
          const timer = setTimeout(() => reject(new Error('worker timed out')), 30000);
          worker.onmessage = event => { clearTimeout(timer); resolve(JSON.parse(event.data)); };
          worker.onerror = event => { clearTimeout(timer); reject(new Error(event.message)); };
        });
      } finally {
        worker.terminate();
        if (wasm) URL.revokeObjectURL(script);
      }
    }, { url, wasm });
  }

  if (mode === 'frb') {
    // FRB's generated webPrefix is relative to an ordinary worker URL.
    const value = await workerValue('worker.js', false);
    assert.deepEqual(value, { value: 'rust:5050', hasDocument: false, isolated: false });
    assert.deepEqual(errors, []);
    console.log(JSON.stringify({ proof: 'frb-classic-worker', browser: browser.version(), ...value, errors }));
  } else {
    await page.waitForFunction(() => typeof globalThis.pageValue === 'string');
    const pageValue = JSON.parse(await page.evaluate(() => globalThis.pageValue));
    const worker = await workerValue(`workers/value.web.g.dart.${compiler}`, compiler === 'wasm');
    assert.deepEqual(pageValue, { value: 'a=b with spaces 日本語', flag: true });
    assert.deepEqual(worker, pageValue);
    assert.deepEqual(errors, []);
    console.log(JSON.stringify({ proof: 'page-worker-defines', compiler, browser: browser.version(), page: pageValue, worker, isolated: false, errors }));
  }
} finally {
  await browser?.close();
  await new Promise(resolve => server.close(resolve));
}

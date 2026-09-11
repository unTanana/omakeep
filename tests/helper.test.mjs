import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import { spawn, spawnSync } from 'node:child_process';
import { Readable } from 'node:stream';
import { fileURLToPath } from 'node:url';
import { validUrl, icon, readRequest, MAX_MESSAGE } from '../helper.mjs';

const helper = fileURLToPath(new URL('../helper.mjs', import.meta.url));
const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a6XcAAAAASUVORK5CYII=';
function request(base, data, native = false) {
  let input = Buffer.from(JSON.stringify(data));
  if (native) { const h = Buffer.alloc(4); h.writeUInt32LE(input.length); input = Buffer.concat([h, input]); }
  const result = spawnSync(process.execPath, [helper, native ? '--native' : '--qml'], {
    input, env: { HOME: base, XDG_DATA_HOME: base, PATH: '/bad-path', NODE_OPTIONS: '' }, timeout: 8000,
  });
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr.toString());
  const output = native ? result.stdout.subarray(4) : result.stdout;
  if (native) assert.equal(result.stdout.readUInt32LE(), output.length);
  return JSON.parse(output);
}

test('durable library, capture boundary, independent edits, literal search, paging and hostile files', async (t) => {
  const base = fs.mkdtempSync('/tmp/omakeep-test-');
  t.after(() => fs.rmSync(base, { recursive: true, force: true }));
  const call = (data, native = false) => {
    const result = request(base, data, native); assert.equal(result.ok, true, result.error); return result.result;
  };
  const saved = call({ op: 'capture', url: 'https://example.com/a?x=1#fragment', title: '<b>Example</b>', favicon: png }, true);
  assert.equal(saved.added, true);
  const folder = call({ op: 'createFolder', name: 'Reading' }).id;
  call({ op: 'saveNote', id: saved.id, notes: 'Keep 100% of _this_ — <img src=x>' });
  call({ op: 'move', id: saved.id, folderId: folder });
  assert.equal(call({ op: 'capture', url: 'https://example.com/a?x=1#fragment', title: 'Overwrite?' }, true).added, false);
  let list = call({ op: 'list', folderId: folder, query: '100%' });
  assert.equal(list.items.length, 1); assert.equal(list.items[0].title, '<b>Example</b>');
  assert.equal(list.items[0].favicon, png);
  call({ op: 'renameBookmark', id: saved.id, title: '  Renamed page  ' });
  assert.equal(call({ op: 'capture', url: 'https://example.com/a?x=1#fragment', title: 'Overwrite again?' }, true).added, false);
  const renamed = call({ op: 'list', folderId: folder, query: 'Renamed' }).items[0];
  assert.deepEqual(renamed, { ...list.items[0], title: 'Renamed page' });
  assert.match(call({ op: 'note', id: saved.id }).notes, /100%/);
  for (const title of ['', '   ', 'é'.repeat(2049)])
    assert.equal(request(base, { op: 'renameBookmark', id: saved.id, title }).ok, false);
  assert.equal(request(base, { op: 'renameBookmark', id: 99999, title: 'Missing' }).ok, false);
  assert.equal(request(base, { op: 'renameBookmark', id: saved.id, title: 'Forbidden' }, true).ok, false);
  assert.equal(call({ op: 'list' }).items[0].title, 'Renamed page');
  assert.equal(call({ op: 'list', query: 'missing%' }).items.length, 0);
  call({ op: 'deleteFolder', id: folder });
  assert.equal(call({ op: 'list' }).items[0].folderId, null);
  assert.match(call({ op: 'note', id: saved.id }).notes, /100%/);
  assert.equal(request(base, { op: 'deleteBookmark', id: saved.id }, true).ok, false);
  assert.equal(request(base, { op: 'capture', url: 'file:///etc/passwd' }).ok, false);
  assert.equal(request(base, { op: 'saveNote', id: saved.id, notes: 'a'.repeat(65537) }).ok, false);

  // Simultaneous native/QML processes must retain every capture and deduplicate the shared URL.
  await Promise.all(Array.from({ length: 16 }, (_, i) => new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [helper, '--qml'], { env: { HOME: base, XDG_DATA_HOME: base } });
    let output = ''; child.stdout.on('data', data => { output += data; });
    child.on('error', reject);
    child.on('exit', code => { try { assert.equal(code, 0); assert.equal(JSON.parse(output).ok, true, output); resolve(); } catch (e) { reject(e); } });
    child.stdin.end(JSON.stringify({ op: 'capture', url: `https://concurrent.test/${i % 8}` }));
  })));
  assert.equal(call({ op: 'list' }).items.length, 9);
  assert.match(call({ op: 'note', id: saved.id }).notes, /100%/);
  const file = `${base}/omakeep/bookmarks.sqlite`;
  assert.equal(fs.statSync(file).mode & 0o777, 0o600);
  fs.renameSync(file, `${base}/original`);
  fs.symlinkSync(`${base}/original`, file);
  assert.equal(request(base, { op: 'capture', url: 'https://hostile.test' }).ok, false);
  assert.equal(request(base, { op: 'list' }).ok, false);
  fs.unlinkSync(file);
  spawnSync('/usr/bin/mkfifo', [file]);
  assert.equal(request(base, { op: 'list' }).ok, false);
  fs.unlinkSync(file);
  fs.linkSync(`${base}/original`, file);
  assert.equal(request(base, { op: 'list' }).ok, false);
  fs.unlinkSync(file); fs.renameSync(`${base}/original`, file);
  fs.chmodSync(file, 0o644);
  assert.equal(request(base, { op: 'list' }).ok, false);
  fs.chmodSync(file, 0o600);
  fs.renameSync(`${base}/omakeep`, `${base}/moved`);
  fs.symlinkSync(`${base}/moved`, `${base}/omakeep`);
  assert.equal(request(base, { op: 'list' }).ok, false);
});

test('bounded framing, UTF-8, URLs and optional PNG fallback', async () => {
  const body = Buffer.from('{"op":"capture","url":"https://example.com"}');
  const h = Buffer.alloc(4); h.writeUInt32LE(body.length);
  const result = await readRequest(Readable.from([h.subarray(0, 2), h.subarray(2), body.subarray(0, 5), body.subarray(5)]), true);
  assert.equal(result.op, 'capture');
  await assert.rejects(readRequest(Readable.from([h, body.subarray(0, -1)]), true), /Truncated/);
  h.writeUInt32LE(MAX_MESSAGE + 1);
  await assert.rejects(readRequest(Readable.from([h]), true), /length/);
  await assert.rejects(readRequest(Readable.from([Buffer.alloc(MAX_MESSAGE + 1)])), /large/);
  await assert.rejects(readRequest(Readable.from([Buffer.from([0xff])])), /encoded/);
  for (const url of ['javascript:alert(1)', 'https://user:pass@example.com', 'https://a.test/\nfoo', 'https://a.test/a b'])
    assert.throws(() => validUrl(url));
  assert.equal(validUrl(' https://localhost/a?x=2#h '), 'https://localhost/a?x=2#h');
  assert.ok(icon(png)); assert.equal(icon('<svg/>'), null);
  const oversized = Buffer.from(png, 'base64'); oversized.writeUInt32BE(1000, 16);
  assert.equal(icon(oversized.toString('base64')), null);
});

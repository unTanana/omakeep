import * as fs from 'node:fs';
import { randomBytes } from 'node:crypto';
import { deflateSync, crc32 } from 'node:zlib';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { database, MAX_MESSAGE } from '../helper.mjs';

const temp = fs.mkdtempSync('/tmp/omakeep-bench-');
try {
  fs.mkdirSync(`${temp}/omakeep`, { mode: 0o700 });
  function chunk(type, bytes) {
    const data = Buffer.concat([Buffer.from(type), bytes]);
    const head = Buffer.alloc(4), tail = Buffer.alloc(4);
    head.writeUInt32BE(bytes.length); tail.writeUInt32BE(crc32(data));
    return Buffer.concat([head, data, tail]);
  }
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(32); ihdr.writeUInt32BE(32, 4); ihdr[8] = 8; ihdr[9] = 6;
  const pixels = Buffer.concat(Array.from({ length: 32 }, () => Buffer.concat([Buffer.from([0]), randomBytes(128)])));
  const png = Buffer.concat([Buffer.from('89504e470d0a1a0a', 'hex'), chunk('IHDR', ihdr), chunk('IDAT', deflateSync(pixels)), chunk('IEND', Buffer.alloc(0))]);
  const db = database(null);
  const insert = db.prepare('INSERT INTO bookmarks(url,title,notes,favicon,createdAt,updatedAt) VALUES(?,?,?,?,1,1)');
  db.exec('BEGIN');
  for (let i = 0; i < 10000; i++) insert.run(`https://example.com/${i}`, `Bookmark ${i}`, `Note for bookmark ${i}`, png);
  db.exec('COMMIT');
  const bytes = db.serialize(); db.close();
  fs.writeFileSync(`${temp}/omakeep/bookmarks.sqlite`, bytes, { mode: 0o600 });
  const medians = {};
  for (const op of ['capture', 'list']) {
    const times = [];
    for (let i = 0; i < 7; i++) {
      const start = performance.now();
      const result = spawnSync(process.execPath, [fileURLToPath(new URL('../helper.mjs', import.meta.url)), '--qml'], {
        input: JSON.stringify(op === 'capture' ? { op, url: `https://capture.test/${i}`, title: 'Captured page', favicon: png.toString('base64') } : { op, query: 'bookmark' }),
        env: { HOME: temp, XDG_DATA_HOME: temp }, maxBuffer: MAX_MESSAGE, timeout: 8000,
      });
      assert.ifError(result.error);
      const reply = JSON.parse(result.stdout); assert.equal(reply.ok, true, JSON.stringify(reply));
      if (op === 'list') { assert.ok(reply.result.next); assert.ok(result.stdout.length <= MAX_MESSAGE); }
      times.push(performance.now() - start);
    }
    medians[op] = Math.round(times.sort((a, b) => a - b)[3]);
  }
  console.log(JSON.stringify({ bookmarks: 10000, iconBytes: png.length, databaseMiB: +(bytes.length / 1048576).toFixed(1), medianMsIncludingProcessStartup: medians }, null, 2));
} finally { fs.rmSync(temp, { recursive: true, force: true }); }

import * as fs from 'node:fs';
import { DatabaseSync, constants as sql } from 'node:sqlite';
import { spawnSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

export const MAX_MESSAGE = 256 * 1024;
export const MAX_DATABASE = 64 * 1024 * 1024;
const MAX_FOLDERS = 200;
const C = fs.constants;
const self = fileURLToPath(import.meta.url);
const reads = new Set(['list', 'note']);

function check(condition, message) {
  if (!condition) throw new Error(message);
}

export function text(value, limit, name, empty = true) {
  check(typeof value === 'string' && value.isWellFormed()
    && Buffer.byteLength(value) <= limit && !value.includes('\0')
    && (empty || value.trim().length > 0), `Invalid ${name}.`);
  return value;
}

export function validUrl(value) {
  value = text(value, 16384, 'URL', false).trim();
  check(/^https?:\/\//i.test(value) && !/[\\\x00-\x20\x7f-\x9f]/u.test(value), 'Invalid URL.');
  let parsed;
  try { parsed = new URL(value); } catch { throw new Error('Invalid URL.'); }
  check(['http:', 'https:'].includes(parsed.protocol) && parsed.hostname
    && !parsed.username && !parsed.password, 'Use an HTTP or HTTPS URL without credentials.');
  return value;
}

function id(value, nullable = false) {
  if (nullable && value === null) return null;
  check(Number.isSafeInteger(value) && value > 0, 'Invalid item ID.');
  return value;
}

export function icon(value) {
  if (typeof value !== 'string' || value.length > 21848
      || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)) return null;
  const bytes = Buffer.from(value, 'base64');
  if (bytes.length < 45 || bytes.length > 16384 || bytes.toString('base64') !== value
      || !bytes.subarray(0, 8).equals(Buffer.from('89504e470d0a1a0a', 'hex'))
      || bytes.readUInt32BE(8) !== 13 || bytes.toString('ascii', 12, 16) !== 'IHDR'
      || bytes.readUInt32BE(16) < 1 || bytes.readUInt32BE(16) > 64
      || bytes.readUInt32BE(20) < 1 || bytes.readUInt32BE(20) > 64) return null;
  return bytes;
}

// Linux /proc descriptors keep each parent pinned; no user pathname is reopened.
export function directory(target, privateLeaf = true) {
  check(path.isAbsolute(target) && !target.split('/').includes('..'), 'Use an absolute data directory.');
  let fd = fs.openSync('/', C.O_RDONLY | C.O_DIRECTORY);
  const systemUid = fs.fstatSync(fd).uid;
  try {
    const parts = target.split('/').filter(Boolean);
    for (let i = 0; i < parts.length; i++) {
      const next = `/proc/self/fd/${fd}/${parts[i]}`;
      try { fs.mkdirSync(next, { mode: 0o700 }); }
      catch (error) { if (error.code !== 'EEXIST') throw error; }
      const child = fs.openSync(next, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_NONBLOCK);
      fs.closeSync(fd);
      fd = child;
      const stat = fs.fstatSync(fd);
      check(stat.isDirectory() && [systemUid, process.getuid()].includes(stat.uid), 'Unsafe directory owner.');
      check(!(stat.mode & 0o022) || (stat.uid === systemUid && (stat.mode & 0o1000)), 'Unsafe writable directory.');
      if (privateLeaf && i === parts.length - 1)
        check(stat.uid === process.getuid() && !(stat.mode & 0o077), 'Omakeep data directory must be private (0700).');
    }
    return fd;
  } catch (error) { fs.closeSync(fd); throw error; }
}

export function readOwnedFile(dir, name, limit, forbiddenMode = 0o077) {
  let fd;
  try { fd = fs.openSync(`/proc/self/fd/${dir}/${name}`, C.O_RDONLY | C.O_NOFOLLOW | C.O_NONBLOCK); }
  catch (error) { if (error.code === 'ENOENT') return null; throw error; }
  try {
    const stat = fs.fstatSync(fd);
    check(stat.isFile() && stat.uid === process.getuid() && stat.nlink === 1
      && !(stat.mode & forbiddenMode) && stat.size <= limit, 'Unsafe or oversized private file.');
    const bytes = Buffer.alloc(Math.min(stat.size + 1, limit + 1));
    let offset = 0;
    while (offset < bytes.length) {
      const count = fs.readSync(fd, bytes, offset, bytes.length - offset, null);
      if (!count) break;
      offset += count;
    }
    check(offset === stat.size, 'Private file changed while reading.');
    return { bytes: bytes.subarray(0, offset), mode: stat.mode & 0o777 };
  } finally { fs.closeSync(fd); }
}

export function readPrivate(dir, name, limit) {
  return readOwnedFile(dir, name, limit)?.bytes ?? null;
}

export function writePrivate(dir, name, bytes, mode = 0o600) {
  const temp = `/proc/self/fd/${dir}/.omakeep-${randomBytes(16).toString('hex')}`;
  const fd = fs.openSync(temp, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW, mode);
  try {
    fs.fchmodSync(fd, mode);
    fs.writeFileSync(fd, bytes);
    fs.fsyncSync(fd);
    fs.renameSync(temp, `/proc/self/fd/${dir}/${name}`);
    fs.fsyncSync(dir);
  } finally {
    fs.closeSync(fd);
    try { fs.unlinkSync(temp); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
}

export function database(bytes) {
  const db = new DatabaseSync(':memory:');
  if (bytes) {
    check(bytes.length > 0 && bytes.length <= MAX_DATABASE, 'Invalid library file.');
    db.deserialize(bytes);
  }
  db.limits.length = MAX_MESSAGE;
  db.limits.attach = 0;
  db.limits.triggerDepth = 16;
  db.exec(`PRAGMA trusted_schema=OFF; PRAGMA foreign_keys=ON; PRAGMA temp_store=MEMORY;
    PRAGMA page_size=4096; PRAGMA max_page_count=16384;`);
  if (!bytes) db.exec(`
    CREATE TABLE folders (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE
      CHECK(length(CAST(name AS BLOB)) BETWEEN 1 AND 256)) STRICT;
    CREATE TABLE bookmarks (
      id INTEGER PRIMARY KEY AUTOINCREMENT, url TEXT NOT NULL UNIQUE, title TEXT NOT NULL,
      notes TEXT NOT NULL DEFAULT '', folderId INTEGER REFERENCES folders(id) ON DELETE SET NULL,
      favicon BLOB, createdAt INTEGER NOT NULL, updatedAt INTEGER NOT NULL,
      CHECK(length(CAST(url AS BLOB)) <= 16384), CHECK(length(CAST(title AS BLOB)) <= 4096),
      CHECK(length(CAST(notes AS BLOB)) <= 65536), CHECK(length(favicon) <= 16384)
    ) STRICT;
    PRAGMA user_version=1;
  `);
  check(db.prepare('PRAGMA user_version').get().user_version === 1, 'Unsupported library version.');
  check(db.prepare("SELECT count(*) AS n FROM sqlite_schema WHERE type IN ('trigger', 'view')").get().n === 0,
    'Unexpected library schema.');
  db.setAuthorizer((action) => [sql.SQLITE_ATTACH, sql.SQLITE_DETACH, sql.SQLITE_CREATE_VTABLE].includes(action)
    ? sql.SQLITE_DENY : sql.SQLITE_OK);
  return db;
}

export function operate(db, request) {
  check(request && typeof request === 'object' && !Array.isArray(request), 'Invalid request.');
  switch (request.op) {
    case 'capture': {
      const url = validUrl(request.url);
      const title = text(request.title ?? '', 4096, 'title').trim() || new URL(url).hostname;
      const now = Date.now();
      const added = db.prepare(`INSERT INTO bookmarks(url,title,favicon,createdAt,updatedAt)
        VALUES(?,?,?,?,?) ON CONFLICT(url) DO NOTHING`).run(url, title, icon(request.favicon), now, now).changes > 0;
      return { id: db.prepare('SELECT id FROM bookmarks WHERE url=?').get(url).id, added };
    }
    case 'list': {
      const query = text(request.query ?? '', 4096, 'search');
      const folder = id(request.folderId ?? null, true);
      const before = request.before === undefined || request.before === null ? Number.MAX_SAFE_INTEGER : id(request.before);
      const folders = db.prepare('SELECT id,name FROM folders ORDER BY name COLLATE NOCASE LIMIT ?').all(MAX_FOLDERS + 1);
      check(folders.length <= MAX_FOLDERS, 'Too many folders.');
      for (const folder of folders) { id(folder.id); text(folder.name, 256, 'folder', false); }
      const result = { folders, items: [], next: null };
      let size = Buffer.byteLength(JSON.stringify(result)) + 64;
      // ponytail: literal linear search; add FTS only when the measured 10k-library target fails.
      const rows = db.prepare(`SELECT id,url,title,folderId,favicon,notes!='' AS hasNote FROM bookmarks
        WHERE id < ? AND (? IS NULL OR folderId=?)
        AND (?='' OR instr(lower(title),lower(?)) OR instr(lower(url),lower(?)) OR instr(lower(notes),lower(?)))
        ORDER BY id DESC LIMIT 101`).iterate(before, folder, folder, query, query, query, query);
      for (const row of rows) {
        id(row.id); validUrl(row.url); text(row.title, 4096, 'title'); id(row.folderId, true);
        row.favicon = icon(row.favicon ? Buffer.from(row.favicon).toString('base64') : '')?.toString('base64') ?? '';
        row.hasNote = Boolean(row.hasNote);
        const bytes = Buffer.byteLength(JSON.stringify(row)) + 1;
        if (result.items.length === 100 || size + bytes > MAX_MESSAGE - 128) {
          result.next = result.items.at(-1).id;
          break;
        }
        result.items.push(row);
        size += bytes;
      }
      return result;
    }
    case 'note': {
      const row = db.prepare('SELECT notes FROM bookmarks WHERE id=?').get(id(request.id));
      check(row, 'Bookmark no longer exists.');
      text(row.notes, 65536, 'note');
      return row;
    }
    case 'saveNote': {
      const notes = text(request.notes, 65536, 'note');
      check(db.prepare('UPDATE bookmarks SET notes=?,updatedAt=? WHERE id=?')
        .run(notes, Date.now(), id(request.id)).changes === 1, 'Bookmark no longer exists.');
      return {};
    }
    case 'renameBookmark':
      check(db.prepare('UPDATE bookmarks SET title=?,updatedAt=? WHERE id=?')
        .run(text(request.title, 4096, 'title', false).trim(), Date.now(), id(request.id)).changes === 1, 'Bookmark no longer exists.');
      return {};
    case 'move':
      check(db.prepare('UPDATE bookmarks SET folderId=?,updatedAt=? WHERE id=?')
        .run(id(request.folderId, true), Date.now(), id(request.id)).changes === 1, 'Bookmark no longer exists.');
      return {};
    case 'deleteBookmark':
      db.prepare('DELETE FROM bookmarks WHERE id=?').run(id(request.id));
      return {};
    case 'createFolder': {
      check(db.prepare('SELECT count(*) AS n FROM folders').get().n < MAX_FOLDERS, 'Folder limit reached (200).');
      const name = text(request.name, 256, 'folder', false).trim();
      return { id: Number(db.prepare('INSERT INTO folders(name) VALUES(?)').run(name).lastInsertRowid) };
    }
    case 'renameFolder':
      check(db.prepare('UPDATE folders SET name=? WHERE id=?').run(text(request.name, 256, 'folder', false).trim(), id(request.id)).changes === 1,
        'Folder no longer exists.');
      return {};
    case 'deleteFolder':
      db.prepare('DELETE FROM folders WHERE id=?').run(id(request.id));
      return {};
    default: throw new Error('Unknown operation.');
  }
}

export function cleanEnvironment() {
  const env = { PATH: '/usr/bin:/bin', LANG: 'C.UTF-8' };
  for (const key of ['HOME', 'XDG_DATA_HOME', 'XDG_RUNTIME_DIR', 'WAYLAND_DISPLAY', 'DBUS_SESSION_BUS_ADDRESS'])
    if (process.env[key]) env[key] = process.env[key];
  return env;
}

function execute(dir, request) {
  const db = database(readPrivate(dir, 'bookmarks.sqlite', MAX_DATABASE));
  try {
    const result = operate(db, request);
    if (!reads.has(request.op) && !(request.op === 'capture' && !result.added)) {
      // ponytail: one locked snapshot, capped at 64 MiB; use a descriptor-safe disk API if larger libraries need it.
      const size = db.prepare('PRAGMA page_count').get().page_count * db.prepare('PRAGMA page_size').get().page_size;
      check(size <= MAX_DATABASE, 'Library limit reached (64 MiB).');
      writePrivate(dir, 'bookmarks.sqlite', db.serialize());
    }
    return result;
  } finally { db.close(); }
}

export function run(request) {
  const base = process.env.XDG_DATA_HOME || path.join(process.env.HOME, '.local/share');
  const dir = directory(path.join(base, 'omakeep'));
  try {
    if (!reads.has(request.op)) {
      // flock locks the shared open-file description; our held fd retains it after the child exits.
      const lock = spawnSync('/usr/bin/flock', ['--exclusive', '--timeout', '3', '3'], {
        stdio: ['ignore', 'ignore', 'pipe', dir], env: cleanEnvironment(),
        timeout: 4000, killSignal: 'SIGKILL', maxBuffer: 4096,
      });
      check(!lock.error && lock.status === 0, 'Library is busy. Your draft is kept; retry.');
    }
    return execute(dir, request);
  } finally { fs.closeSync(dir); }
}

export async function readRequest(stream, native = false) {
  const header = Buffer.alloc(4);
  let headerSize = 0, size = 0, expected = null;
  const chunks = [];
  const timer = setTimeout(() => stream.destroy(new Error('Request timed out.')), 3000);
  try {
    for await (let chunk of stream) {
      if (native && headerSize < 4) {
        const count = Math.min(4 - headerSize, chunk.length);
        chunk.copy(header, headerSize, 0, count);
        headerSize += count;
        chunk = chunk.subarray(count);
        if (headerSize === 4) {
          expected = header.readUInt32LE();
          check(expected > 0 && expected <= MAX_MESSAGE, 'Invalid message length.');
        }
      }
      size += chunk.length;
      check(size <= MAX_MESSAGE && (!native || expected === null || size <= expected), 'Message too large.');
      chunks.push(chunk);
      if (native && expected !== null && size === expected) break;
    }
    check(!native || (expected !== null && size === expected), 'Truncated message.');
    const bytes = Buffer.concat(chunks, size);
    return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
  } finally { clearTimeout(timer); }
}

function reply(payload, native) {
  let bytes = Buffer.from(JSON.stringify(payload));
  if (bytes.length > MAX_MESSAGE) bytes = Buffer.from('{"ok":false,"error":"Response too large."}');
  if (native) {
    const header = Buffer.alloc(4);
    header.writeUInt32LE(bytes.length);
    process.stdout.write(header);
  }
  process.stdout.write(bytes);
}

if (process.argv[1] && path.resolve(process.argv[1]) === self) {
  process.umask(0o077);
  const mode = process.argv[2];
  const native = mode === '--native';
  try {
    check(['--native', '--qml'].includes(mode), 'Use --qml or --native.');
    const request = await readRequest(process.stdin, native);
    if (native) check(request?.op === 'capture', 'Browser may only capture bookmarks.');
    const result = run(request);
    reply({ ok: true, result }, native);
    if (native) spawnSync('/usr/bin/notify-send', ['--app-name=Omakeep', '--expire-time=1800', result.added ? 'Saved to Omakeep' : 'Already saved in Omakeep'],
      { env: cleanEnvironment(), timeout: 1000, maxBuffer: 4096, stdio: 'ignore' });
  } catch (error) {
    const message = error.code?.startsWith('SQLITE') || error.code === 'ERR_SQLITE_ERROR'
      ? 'Library operation failed. Check for a duplicate folder name or retry.'
      : error.code ? 'Cannot access the library safely. Check its location and permissions.' : error.message;
    reply({ ok: false, error: String(message).slice(0, 256) }, native);
  }
}

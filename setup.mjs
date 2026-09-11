import * as fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { DatabaseSync } from 'node:sqlite';
import { directory, readPrivate, readOwnedFile, writePrivate } from './helper.mjs';

const root = path.dirname(fileURLToPath(import.meta.url));
const quote = value => "'" + value.replaceAll("'", "'\\''") + "'";
const extension = JSON.parse(fs.readFileSync(path.join(root, 'extension/manifest.json')));
const binding = '\n-- BEGIN Omakeep shortcut\no.bind("SUPER + SHIFT + K", "Omakeep", "omarchy shell shell toggle omakeep \'{}\'")\n-- END Omakeep shortcut\n';
export const extensionId = createHash('sha256').update(Buffer.from(extension.key, 'base64')).digest('hex').slice(0, 32)
  .replace(/[0-9a-f]/g, c => String.fromCharCode(97 + parseInt(c, 16)));

function ownedWrite(dir, name, bytes, mode = 0o600) {
  const existing = readPrivate(dir, name, 256 * 1024);
  if (existing && !existing.equals(bytes)) throw new Error(`Refusing to replace a different ${name}. Remove the previous Omakeep setup first.`);
  if (!existing) writePrivate(dir, name, bytes, mode);
}

function command(executable, args) {
  const result = spawnSync(executable, args, { encoding: 'utf8', maxBuffer: 256 * 1024, timeout: 5000 });
  if (result.error || result.status !== 0) throw new Error(`Could not run ${path.basename(executable)}.`);
  return result.stdout;
}

export function shortcut(remove = false) {
  const config = process.env.XDG_CONFIG_HOME || path.join(process.env.HOME, '.config');
  const dir = directory(path.join(config, 'hypr'), false);
  try {
    const original = readOwnedFile(dir, 'bindings.lua', 256 * 1024, 0o022);
    if (!original) throw new Error('No Hyprland bindings.lua found.');
    const previous = original.bytes;
    const source = previous.toString('utf8');
    const exists = source.includes(binding);
    if ((source.includes('-- BEGIN Omakeep shortcut') || source.includes('-- END Omakeep shortcut'))
        && (!exists || source.indexOf(binding) !== source.lastIndexOf(binding))) throw new Error('Omakeep shortcut block was modified; inspect it manually.');
    if (remove && !exists || !remove && exists) return;
    if (command('/usr/bin/hyprctl', ['configerrors']).trim()) throw new Error('Fix existing Hyprland configuration errors before changing shortcuts.');
    if (!remove) {
      const binds = JSON.parse(command('/usr/bin/hyprctl', ['-j', 'binds']));
      if (binds.some(b => b.modmask === 65 && (String(b.key).toUpperCase() === 'K' || b.keycode === 45)))
        throw new Error('Super+Shift+K is already in use. Choose a shortcut manually.');
    }
    const backups = directory(path.join(process.env.XDG_STATE_HOME || path.join(process.env.HOME, '.local/state'), 'omakeep-backups'));
    try { writePrivate(backups, `bindings-${Date.now()}.lua`, previous); } finally { fs.closeSync(backups); }
    const updated = Buffer.from(remove ? source.replace(binding, '') : source + binding);
    writePrivate(dir, 'bindings.lua', updated, original.mode);
    try {
      command('/usr/bin/hyprctl', ['reload']);
      if (command('/usr/bin/hyprctl', ['configerrors']).trim()) throw new Error('Hyprland rejected the Omakeep shortcut.');
    } catch (error) {
      writePrivate(dir, 'bindings.lua', previous, original.mode);
      command('/usr/bin/hyprctl', ['reload']);
      if (command('/usr/bin/hyprctl', ['configerrors']).trim()) throw new Error('Shortcut rollback needs inspection: Hyprland still reports errors.');
      throw error;
    }
  } finally { fs.closeSync(dir); }
}

export function setup(action, browser = 'chromium') {
  if (!['prepare', 'install', 'remove'].includes(action)) throw new Error('Use: node setup.mjs prepare|install|remove [chromium|google-chrome]');
  if (!['chromium', 'google-chrome'].includes(browser)) throw new Error('Unsupported browser.');
  if (!DatabaseSync.prototype.serialize || !DatabaseSync.prototype.deserialize) throw new Error('Node 26.1 or newer with node:sqlite serialization is required.');
  process.umask(0o077);
  const node = fs.realpathSync(process.execPath);
  const launcher = Buffer.from(`#!/bin/sh\n# Omakeep generated helper launcher\nexec /usr/bin/env -u NODE_OPTIONS -u NODE_PATH -u LD_PRELOAD -u LD_LIBRARY_PATH /usr/bin/timeout --kill-after=1 8 ${quote(node)} ${quote(path.join(root, 'helper.mjs'))} "$@"\n`);
  const repo = directory(root, false);
  try {
    if (action !== 'remove') ownedWrite(repo, 'run-helper', launcher, 0o700);
  } finally { fs.closeSync(repo); }
  if (action === 'prepare') return { extensionId, extensionPath: path.join(root, 'extension') };

  const config = process.env.XDG_CONFIG_HOME || path.join(process.env.HOME, '.config');
  const hosts = directory(path.join(config, browser, 'NativeMessagingHosts'), false);
  const pluginParent = directory(path.join(config, 'omarchy/plugins'), false);
  const nativeName = 'com.omarchy.omakeep.json';
  const nativeLauncher = Buffer.from(`#!/bin/sh\n# Omakeep generated native host\nexec ${quote(path.join(root, 'run-helper'))} --native "$@"\n`);
  const host = Buffer.from(JSON.stringify({ name: 'com.omarchy.omakeep', description: 'Omakeep local bookmark capture',
    path: path.join(root, 'native-host'), type: 'stdio', allowed_origins: [`chrome-extension://${extensionId}/`] }, null, 2) + '\n');
  try {
    const pluginLink = `/proc/self/fd/${pluginParent}/omakeep`;
    let existingLink = null;
    try { existingLink = fs.readlinkSync(pluginLink); } catch (error) { if (error.code !== 'ENOENT') throw new Error('Omakeep plugin path already exists and is not this checkout link.'); }
    if (existingLink !== null && existingLink !== root) throw new Error('Omakeep plugin path belongs to another checkout.');
    const current = readPrivate(hosts, nativeName, 16384);
    if (current && !current.equals(host)) throw new Error('Native host registration belongs to another setup.');
    if (action === 'install') {
      const repo = directory(root, false);
      try { ownedWrite(repo, 'native-host', nativeLauncher, 0o700); } finally { fs.closeSync(repo); }
      ownedWrite(hosts, nativeName, host);
      if (!existingLink) fs.symlinkSync(root, pluginLink);
    } else {
      if (existingLink === root) fs.unlinkSync(pluginLink);
      if (current) fs.unlinkSync(`/proc/self/fd/${hosts}/${nativeName}`);
      const repo = directory(root, false);
      try {
        for (const [name, expected] of [['native-host', nativeLauncher], ['run-helper', launcher]]) {
          const actual = readPrivate(repo, name, 16384);
          if (actual && actual.equals(expected)) fs.unlinkSync(`/proc/self/fd/${repo}/${name}`);
        }
      } finally { fs.closeSync(repo); }
    }
  } finally { fs.closeSync(hosts); fs.closeSync(pluginParent); }
  return { extensionId, browser, extensionPath: path.join(root, 'extension'), plugin: 'omakeep' };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    if (['shortcut', 'unshortcut'].includes(process.argv[2])) { shortcut(process.argv[2] === 'unshortcut'); console.log('Omakeep shortcut updated.'); }
    else console.log(JSON.stringify(setup(process.argv[2], process.argv[3]), null, 2));
  }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}

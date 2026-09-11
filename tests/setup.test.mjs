import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import { pathToFileURL } from 'node:url';

test('local setup is repeatable, refuses foreign registrations and removal preserves data', async t => {
  const temp = fs.mkdtempSync('/tmp/omakeep-setup-');
  t.after(() => fs.rmSync(temp, { recursive: true, force: true }));
  fs.mkdirSync(`${temp}/repo`); fs.mkdirSync(`${temp}/repo/extension`);
  for (const name of ['setup.mjs', 'helper.mjs', 'extension/manifest.json'])
    fs.copyFileSync(new URL(`../${name}`, import.meta.url), `${temp}/repo/${name}`);
  const { setup, extensionId } = await import(pathToFileURL(`${temp}/repo/setup.mjs`));
  process.env.HOME = temp; process.env.XDG_CONFIG_HOME = `${temp}/config`; process.env.XDG_DATA_HOME = `${temp}/data`;
  setup('install'); setup('install');
  const host = `${temp}/config/chromium/NativeMessagingHosts/com.omarchy.omakeep.json`;
  assert.deepEqual(JSON.parse(fs.readFileSync(host)).allowed_origins, [`chrome-extension://${extensionId}/`]);
  assert.equal(fs.readlinkSync(`${temp}/config/omarchy/plugins/omakeep`), `${temp}/repo`);
  fs.mkdirSync(`${temp}/data/omakeep`, { recursive: true, mode: 0o700 });
  fs.writeFileSync(`${temp}/data/omakeep/bookmarks.sqlite`, 'keep this library', { mode: 0o600 });
  const original = fs.readFileSync(host);
  fs.writeFileSync(host, '{}'); assert.throws(() => setup('install'), /another setup/);
  fs.writeFileSync(host, original);
  setup('remove'); setup('remove');
  assert.equal(fs.existsSync(host), false);
  assert.equal(fs.existsSync(`${temp}/config/omarchy/plugins/omakeep`), false);
  assert.equal(fs.readFileSync(`${temp}/data/omakeep/bookmarks.sqlite`, 'utf8'), 'keep this library');
});

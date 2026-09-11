import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

test('shortcut and button capture, optional icon failure, duplicates and native host failure', async () => {
  let clicked, command, sent, title, badge, fail = false, added = true;
  const chrome = {
    runtime: {
      getURL: p => `chrome-extension://test${p}`,
      sendNativeMessage: async (host, payload) => { sent = { host, payload }; if (fail) throw Error('Specified native messaging host not found.'); return { ok: true, result: { added } }; },
    },
    action: {
      onClicked: { addListener: fn => { clicked = fn; } },
      setBadgeText: async p => { badge = p.text; }, setBadgeBackgroundColor: async () => {},
      setTitle: async p => { title = p.title; },
    },
    commands: { onCommand: { addListener: fn => { command = fn; } } },
    tabs: { query: async () => [{ id: 1, url: 'https://example.com', title: 'Page title' }] },
  };
  const context = vm.createContext({ chrome, URL, AbortSignal, fetch: async () => { throw Error('no icon'); } });
  vm.runInContext(fs.readFileSync(new URL('../extension/background.js', import.meta.url), 'utf8'), context);
  await command('save-bookmark');
  assert.equal(sent.host, 'com.omarchy.omakeep'); assert.equal(sent.payload.title, 'Page title');
  assert.equal(sent.payload.favicon, ''); assert.equal(badge, '✓'); assert.equal(title, 'Saved to Omakeep');
  added = false;
  await clicked({ id: 1, url: 'https://example.com', title: 'Page title' });
  assert.equal(title, 'Already saved in Omakeep');
  fail = true;
  await command('save-bookmark'); assert.equal(badge, '!'); assert.match(title, /not connected/);
  await clicked({ id: 1, url: 'chrome://settings' }); assert.match(title, /web page/);
});

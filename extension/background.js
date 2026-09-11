const HOST = 'com.omarchy.omakeep';
let busy = false;

async function favicon(url) {
  try {
    const target = new URL(chrome.runtime.getURL('/_favicon/'));
    target.searchParams.set('pageUrl', url);
    target.searchParams.set('size', '32');
    const response = await fetch(target, { signal: AbortSignal.timeout(500) });
    if (!response.ok) return '';
    const reader = response.body.getReader();
    const parts = [];
    let size = 0;
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 16384) { await reader.cancel(); return ''; }
      parts.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const part of parts) { bytes.set(part, offset); offset += part.length; }
    return btoa(String.fromCharCode(...bytes));
  } catch { return ''; }
}

async function capture(tab) {
  if (busy) return;
  busy = true;
  const target = Number.isInteger(tab?.id) ? { tabId: tab.id } : {};
  try {
    if (!tab?.url || !/^https?:\/\//i.test(tab.url)) throw new Error('Open a web page to save it.');
    await chrome.action.setBadgeText({ ...target, text: '…' });
    const reply = await chrome.runtime.sendNativeMessage(HOST, {
      op: 'capture', url: tab.url, title: tab.title || '', favicon: await favicon(tab.url),
    });
    if (reply?.ok !== true || typeof reply.result?.added !== 'boolean')
      throw new Error(reply?.error || 'Could not save. Check Omakeep setup.');
    await chrome.action.setBadgeBackgroundColor({ ...target, color: '#3f8f8a' });
    await chrome.action.setBadgeText({ ...target, text: '✓' });
    await chrome.action.setTitle({ ...target, title: reply.result.added ? 'Saved to Omakeep' : 'Already saved in Omakeep' });
  } catch (error) {
    await chrome.action.setBadgeBackgroundColor({ ...target, color: '#a13d3d' }).catch(() => {});
    await chrome.action.setBadgeText({ ...target, text: '!' }).catch(() => {});
    const message = error.message?.includes('native messaging host') ? 'Omakeep is not connected. Run local setup.' : String(error.message || 'Could not save.').slice(0, 256);
    await chrome.action.setTitle({ ...target, title: message }).catch(() => {});
  } finally { busy = false; }
}

chrome.action.onClicked.addListener(capture);
chrome.commands.onCommand.addListener(async command => {
  if (command !== 'save-bookmark') return;
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  await capture(tab);
});

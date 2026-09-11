import * as fs from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const root = fileURLToPath(new URL('..', import.meta.url));
const temp = fs.mkdtempSync('/tmp/omakeep-ui-');
try {
  for (const name of ['Commons', 'Ui', 'services']) fs.cpSync(`/usr/share/omarchy/shell/${name}`, `${temp}/${name}`, { recursive: true });
  fs.mkdirSync(`${temp}/omakeep`);
  fs.mkdirSync(`${temp}/data`, { mode: 0o700 });
  for (const name of fs.readdirSync(root)) if (name.endsWith('.qml') || name === 'State.js' || name === 'run-helper') fs.copyFileSync(path.join(root, name), `${temp}/omakeep/${name}`);
  fs.chmodSync(`${temp}/omakeep/run-helper`, 0o700);
  fs.writeFileSync(`${temp}/test.qml`, fs.readFileSync(new URL('qml/tst_ui.qml', import.meta.url), 'utf8')
    .replace('import "../.."', 'import "omakeep"').replace('when: windowShown', 'when: true'));
  for (const reopen of ['0', '1']) {
    const result = spawnSync('/usr/bin/timeout', ['--kill-after=1', reopen === '1' ? '15' : '30', '/usr/bin/quickshell', '-p', `${temp}/test.qml`], {
      env: { ...process.env, QT_QPA_PLATFORM: 'offscreen', QT_QPA_PLATFORMTHEME: 'none', QT_QUICK_CONTROLS_STYLE: 'Basic',
        XDG_DATA_HOME: `${temp}/data`, WAYLAND_DISPLAY: '', QML_IMPORT_PATH: '', OMAKEEP_TEST_REOPEN: reopen },
      encoding: 'utf8', maxBuffer: 1024 * 1024,
    });
    console.log(result.stdout); console.error(result.stderr);
    const output = result.stdout + result.stderr;
    const marker = reopen === '1' ? 'OMAKEEP_RESTART_OK' : 'OMAKEEP_UI_OK';
    if (result.error || result.status !== 0 || !output.includes(marker) || /FAIL!|ERROR:|ReferenceError|TypeError/.test(output)) {
      process.exitCode = 1; break;
    }
  }
} finally { fs.rmSync(temp, { recursive: true, force: true }); }

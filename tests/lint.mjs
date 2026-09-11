import * as fs from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const root = fileURLToPath(new URL('..', import.meta.url));
const temp = fs.mkdtempSync('/tmp/omakeep-lint-');
try {
  fs.symlinkSync('/usr/share/omarchy/shell', `${temp}/qs`);
  const files = fs.readdirSync(root).filter(name => name.endsWith('.qml'));
  const result = spawnSync('/usr/lib/qt6/bin/qmllint', ['-I', temp, '-I', '/usr/lib/qt6/qml', '--json', `${temp}/result.json`, ...files],
    { cwd: root, encoding: 'utf8', maxBuffer: 1024 * 1024, timeout: 15000 });
  if (result.error || result.status !== 0) throw new Error(result.stderr || 'qmllint failed');
  // qmllint --json may exit zero even when individual files report diagnostics.
  const report = JSON.parse(fs.readFileSync(`${temp}/result.json`));
  for (const file of report.files) for (const warning of file.warnings) console.error(`${file.filename}:${warning.line}: ${warning.message}`);
  if (report.files.some(file => !file.success)) process.exitCode = 1;
  else console.log('QML lint passed against the installed Omarchy imports.');
} finally { fs.rmSync(temp, { recursive: true, force: true }); }

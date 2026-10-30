#!/bin/bash
# The real plugin UI in a throwaway Quickshell with the installed Omarchy controls and a throwaway library.
# Offscreen, so it never reaches the desktop. It does not restart the real shell.
set -uo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
temp=$(mktemp -d "${TMPDIR:-/tmp}/omakeep-ui.XXXXXX")
trap 'rm -rf -- "$temp"' EXIT
for name in Commons Ui services; do cp -r "/usr/share/omarchy/shell/$name" "$temp/$name"; done
mkdir -p "$temp/omakeep/bin" "$temp/data"
chmod 700 "$temp/data"
cp "$repo"/*.qml "$repo"/*.js "$temp/omakeep/"
cp "$repo/bin/omakeep-helper" "$temp/omakeep/bin/"
sed -e 's|import "../.."|import "omakeep"|' -e 's|when: windowShown|when: true|' "$repo/tests/qml/tst_ui.qml" >"$temp/test.qml"
# Stand-ins for the helper, only where a failure or an odd reply is the point of the check.
fake() {
  mkdir -p "$temp/fakes/$1/bin"
  printf '#!/bin/sh\n%s\n' "$2" >"$temp/fakes/$1/bin/omakeep-helper"
  chmod +x "$temp/fakes/$1/bin/omakeep-helper"
}
row() { printf '{"id":%s,"url":"https://%s.test","title":"Row %s","folderId":null,"favicon":"","hasNote":false,"preview":""}' "$1" "$1" "$1"; }
fake failing "cat >/dev/null; echo '{\"ok\":false,\"error\":\"Library is busy. Your draft is kept; retry.\"}'"
fake odd "cat >/dev/null; echo '{\"ok\":true,\"result\":{\"folders\":[{\"id\":1,\"name\":\"Good\",\"count\":1},{\"id\":\"bad\"}],\"items\":[{\"id\":7,\"url\":\"https://good.test\",\"title\":\"Good row\",\"folderId\":1,\"favicon\":\"\",\"hasNote\":false,\"preview\":\"\"},{\"id\":\"x\"},null,{\"id\":8,\"url\":\"\",\"title\":\"\",\"folderId\":null,\"favicon\":\"\",\"hasNote\":false,\"preview\":\"\"}],\"next\":null,\"total\":3,\"all\":3}}'"
page="{\"ok\":true,\"result\":{\"folders\":[],\"items\":[$(row 3 | sed 's/"/\\"/g'),$(row 2 | sed 's/"/\\"/g'),$(row 1 | sed 's/"/\\"/g')],\"next\":1,\"total\":4,\"all\":4}}"
last="{\"ok\":true,\"result\":{\"folders\":[],\"items\":[$(row 9 | sed 's/"/\\"/g')],\"next\":null,\"total\":4,\"all\":4}}"
fake paging "if grep -q before; then echo '{\"ok\":false,\"error\":\"Library is busy. Your draft is kept; retry.\"}'; else echo '$(printf '%b' "$page" | sed 's/\\"/"/g')'; fi"
fake pagingok "if grep -q before; then echo '$(printf '%b' "$last" | sed 's/\\"/"/g')'; else echo '$(printf '%b' "$page" | sed 's/\\"/"/g')'; fi"
status=0
for reopen in 0 1; do
  marker=OMAKEEP_UI_OK limit=150
  [ "$reopen" = 1 ] && marker=OMAKEEP_RESTART_OK limit=20
  OMAKEEP_TEST_REOPEN=$reopen OMAKEEP_TEST_FAKES=$temp/fakes OMAKEEP_TEST_SHOTS=${OMAKEEP_TEST_SHOTS:-} QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none QT_QUICK_CONTROLS_STYLE=Basic \
    XDG_DATA_HOME=$temp/data WAYLAND_DISPLAY='' QML_IMPORT_PATH='' \
    timeout --foreground --kill-after=2 "$limit" /usr/bin/quickshell -p "$temp/test.qml" >"$temp/out.txt" 2>&1
  code=$?
  bad=$(grep -Ec 'FAIL!|ERROR:|ReferenceError|TypeError|Unable to assign \[undefined\]|Binding loop' "$temp/out.txt")
  # Offscreen has no browser, so a row click ends in this line and nothing opens.
  opened=1
  [ "$reopen" = 0 ] && opened=$(grep -c "openUrl() for 'https://example.com" "$temp/out.txt")
  if [ "$code" != 0 ] || ! grep -q "$marker" "$temp/out.txt" || [ "$bad" != 0 ] || [ "$opened" -lt 1 ]; then
    grep -Ev 'qt\.qpa|window masks' "$temp/out.txt" | tail -30
    echo "ui: failed (run $reopen, exit $code)"
    status=1
    break
  fi
done
[ "$status" = 0 ] && echo "ui: passed"
exit "$status"

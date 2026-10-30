#!/bin/bash
# qmllint against the installed Omarchy imports. Its exit code can be zero with diagnostics, so read the report.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
temp=$(mktemp -d "${TMPDIR:-/tmp}/omakeep-lint.XXXXXX")
trap 'rm -rf -- "$temp"' EXIT
ln -s /usr/share/omarchy/shell "$temp/qs"
timeout 30 /usr/lib/qt6/bin/qmllint -I "$temp" -I /usr/lib/qt6/qml --json "$temp/result.json" ./*.qml
jq -r '.files[] | .filename as $f | .warnings[] | "\($f):\(.line // 0): \(.message)"' "$temp/result.json" >&2
jq -e 'all(.files[]; .success)' "$temp/result.json" >/dev/null
echo "lint: passed against the installed Omarchy imports"

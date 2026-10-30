#!/bin/bash
# The browser worker and State.js in headless Chromium, on a throwaway profile.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
temp=$(mktemp -d "${TMPDIR:-/tmp}/omakeep-js.XXXXXX")
trap 'rm -rf -- "$temp"' EXIT
cp "$repo/tests/js.html" "$repo/extension/background.js" "$repo/State.js" "$temp/"
timeout -k 2 30 /usr/bin/chromium --headless=new --disable-gpu --no-first-run --user-data-dir="$temp/profile" \
  --virtual-time-budget=5000 --dump-dom "file://$temp/js.html" 2>/dev/null >"$temp/dom.html"
line=$(grep -o '<pre id="out">[^<]*' "$temp/dom.html" | sed 's/<pre id="out">//')
echo "js: ${line:-no result}"
[[ $line == PASS* ]]

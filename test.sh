#!/bin/bash
# Runs every check. Each one uses throwaway data and leaves the real library alone.
set -uo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
export CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/omakeep-target}
cargo=(cargo)
command -v mise >/dev/null && cargo=(mise exec rust@1.98.0 -- cargo)
status=0
"${cargo[@]}" test --locked 2>&1 | grep -E '^test result|FAILED|panicked|^error' || status=1
[ "${PIPESTATUS[0]}" = 0 ] || status=1
tests/setup.test.sh || status=1
tests/run-js.sh || status=1
tests/run-ui.sh || status=1
tests/lint.sh || status=1
omarchy plugin validate . || status=1
[ "$status" = 0 ] && echo "All checks passed." || echo "Some checks failed."
exit "$status"

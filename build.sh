#!/bin/bash
# Rebuilds bin/omakeep-helper. Rust is needed only here, never at run time.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
# The shell watches real plugin folders and reloads on any change, so cargo's output stays outside.
export CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/omakeep-target}
# Keeps home paths out of the binary, and lets two machines compare builds.
export RUSTFLAGS="-C target-feature=+crt-static --remap-path-prefix=$PWD=. --remap-path-prefix=$HOME=~"
cargo=(cargo)
command -v mise >/dev/null && cargo=(mise exec rust@1.98.0 -- cargo)
# One binary per chip, kept side by side; setup links bin/omakeep-helper to this machine's.
arch=$(uname -m)
"${cargo[@]}" build --release --locked --target "$arch-unknown-linux-gnu"
built=$CARGO_TARGET_DIR/$arch-unknown-linux-gnu/release/omakeep-helper
cp -- "$built" "$built.out"
mkdir -p bin
mv -f -- "$built.out" "bin/omakeep-helper-$arch" # One mv: a running helper keeps its file, and the watcher sees one change.
sha256sum "bin/omakeep-helper-$arch"

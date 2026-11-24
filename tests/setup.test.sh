#!/bin/bash
# Setup in a fake HOME with a fake hyprctl. Never touches the real config.
set -uo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
T=$(mktemp -d "${TMPDIR:-/tmp}/omakeep-setup.XXXXXX")
trap 'rm -rf -- "$T"' EXIT
mkdir -p "$T/repo/extension" "$T/repo/bin" "$T/config/hypr" "$T/data/omakeep"
cp "$repo/setup.sh" "$T/repo/"
cp "$repo/extension/manifest.json" "$T/repo/extension/"
printf '#!/bin/sh\nexit 0\n' >"$T/repo/bin/omakeep-helper"
chmod +x "$T/repo/bin/omakeep-helper"
cat >"$T/hyprctl" <<'H'
#!/bin/bash
echo "$@" >>"$FAKE_LOG"
case "$*" in
  configerrors) cat "$FAKE_ERRORS" 2>/dev/null ;;
  "-j binds") cat "$FAKE_BINDS" ;;
esac
exit 0
H
chmod +x "$T/hyprctl"
export HOME=$T XDG_CONFIG_HOME=$T/config XDG_STATE_HOME=$T/state OMAKEEP_TEST_HYPRCTL=$T/hyprctl
export FAKE_LOG=$T/hypr.log FAKE_ERRORS=$T/errors FAKE_BINDS=$T/binds
echo '[]' >"$T/binds"
S=$T/repo/setup.sh
H=$T/config/chromium/NativeMessagingHosts/com.omarchy.omakeep.json
P=$T/config/omarchy/plugins/omakeep
B=$T/config/hypr/bindings.lua
pass=0 fail=0
ok() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1"; fi; }

ok "extension id stays the same" '[ "$($S prepare | jq -r .extensionId)" = lefgnegnkcnkapehnnkfnkmdfiaahnmf ]'
$S install >/dev/null
ok "install twice" '$S install >/dev/null'
ok "origin" '[ "$(jq -r ".allowed_origins[0]" $H)" = chrome-extension://lefgnegnkcnkapehnnkfnkmdfiaahnmf/ ]'
ok "host runs the binary directly" '[ "$(jq -r .path $H)" = $T/repo/bin/omakeep-helper ]'
ok "host name" '[ "$(jq -r .name $H)" = com.omarchy.omakeep ]'
ok "host mode 600" '[ "$(stat -c %a $H)" = 600 ]'
ok "plugin link" '[ "$(readlink $P)" = $T/repo ]'
echo 'keep this library' >"$T/data/omakeep/bookmarks.sqlite"
cp "$H" "$T/orig"
echo '{}' >"$H"
ok "refuses a foreign host file" '! $S install 2>/dev/null'
ok "foreign host file untouched" '[ "$(cat $H)" = "{}" ]'
cp "$T/orig" "$H"
rm "$P"
ln -s /somewhere/else "$P"
ok "refuses another checkout" '! $S install 2>/dev/null'
rm "$P"
mkdir "$P"
ok "refuses a real folder that is not this one" '! $S install 2>/dev/null'
rmdir "$P"
ln -s "$T/repo" "$P"
$S remove >/dev/null
ok "remove twice" '$S remove >/dev/null'
ok "host gone" '[ ! -e $H ]'
ok "link gone" '[ ! -e $P ]'
ok "library kept" '[ "$(cat $T/data/omakeep/bookmarks.sqlite)" = "keep this library" ]'
ok "binary kept" '[ -x $T/repo/bin/omakeep-helper ]'
chmod -x "$T/repo/bin/omakeep-helper"
ok "refuses a missing helper" '! $S install 2>/dev/null'
chmod +x "$T/repo/bin/omakeep-helper"

# A plugin installed as a real folder runs setup from inside that folder.
mkdir -p "$T/config/omarchy/plugins"
mv "$T/repo" "$P"
ok "works from an installed plugin folder" '$P/setup.sh install >/dev/null'
ok "keeps the plugin folder" '[ -d $P ] && [ ! -L $P ]'
ok "host follows the folder" '[ "$(jq -r .path $H)" = $P/bin/omakeep-helper ]'
ok "removal leaves the folder" '$P/setup.sh remove >/dev/null && [ -d $P ]'
mv "$P" "$T/repo"

printf 'o.bind("A")\n\n\n' >"$B"
chmod 644 "$B"
cp "$B" "$T/b0"
$S shortcut >/dev/null
ok "block added" 'grep -q "BEGIN Omakeep" $B'
ok "mode kept" '[ "$(stat -c %a $B)" = 644 ]'
ok "reload called" 'grep -q reload $T/hypr.log'
ok "backup made" '[ "$(ls $T/state/omakeep-backups | wc -l)" = 1 ]'
ok "backup exact" 'cmp -s $T/b0 $T/state/omakeep-backups/*'
n=$(wc -l <"$T/hypr.log")
$S shortcut >/dev/null
ok "second run does nothing" '[ "$(wc -l <$T/hypr.log)" = $n ]'
$S unshortcut >/dev/null
ok "removed exactly, trailing newlines kept" 'cmp -s $T/b0 $B'
echo '[{"modmask":65,"key":"k","keycode":0}]' >"$T/binds"
ok "refuses a used key" '! $S shortcut 2>/dev/null'
ok "file untouched after refusal" 'cmp -s $T/b0 $B'
echo '[]' >"$T/binds"
echo 'an error' >"$T/errors"
ok "refuses when errors exist" '! $S shortcut 2>/dev/null'
rm "$T/errors"
cat >"$T/hyprctl" <<'H'
#!/bin/bash
case "$*" in
  configerrors) [ -f "$FAKE_ERRORS" ] && cat "$FAKE_ERRORS" ;;
  "-j binds") cat "$FAKE_BINDS" ;;
  reload) if grep -q 'BEGIN Omakeep' "$XDG_CONFIG_HOME/hypr/bindings.lua"; then echo boom >"$FAKE_ERRORS"; else rm -f "$FAKE_ERRORS"; fi ;;
esac
exit 0
H
ok "a rejected shortcut reports" '! $S shortcut 2>/dev/null'
ok "rollback restored the file" 'cmp -s $T/b0 $B'
printf 'x\n-- BEGIN Omakeep shortcut\nedited\n' >"$B"
ok "an edited block is refused" '! $S shortcut 2>/dev/null'

echo "setup: $pass passed, $fail failed"
[ "$fail" = 0 ]

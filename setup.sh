#!/bin/bash
# Registers Omakeep with this desktop. Nothing here runs on its own, and it installs no packages.
# Usage: ./setup.sh prepare|install|remove [chromium|google-chrome], or ./setup.sh shortcut|unshortcut
set -euo pipefail
umask 077
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
config=${XDG_CONFIG_HOME:-$HOME/.config}
state=${XDG_STATE_HOME:-$HOME/.local/state}
hyprctl=${OMAKEEP_TEST_HYPRCTL:-/usr/bin/hyprctl}
helper=$root/bin/omakeep-helper
host_name=com.omarchy.omakeep
die() { echo "$*" >&2; exit 1; }
for tool in jq sha256sum base64; do command -v "$tool" >/dev/null || die "Missing $tool."; done

extension_id() {
  jq -er .key "$root/extension/manifest.json" | base64 -d | sha256sum | cut -c1-32 | tr 0-9a-f a-p
}
# Reads a file with its exact bytes; command substitution would eat trailing newlines.
exact() { local c; c=$(cat -- "$1"; printf x); printf '%s' "${c%x}"; }
publish() { # target mode content
  local t; t=$(mktemp "$1.omakeep.XXXXXX")
  printf '%s' "$3" >"$t"; chmod "$2" "$t"; sync "$t"; mv -f -- "$t" "$1"
}
owned_write() { # target mode content: refuse to replace someone else's file
  if [[ -e $1 || -L $1 ]]; then
    [[ -f $1 && ! -L $1 && $(exact "$1"; printf x) == "$3"x ]] || die "Refusing to replace a different ${1##*/}. Remove the previous Omakeep setup first."
  else publish "$1" "$2" "$3"; fi
}

setup() {
  local action=$1 browser=${2:-chromium} id hosts host plugins link
  [[ $action == prepare || $action == install || $action == remove ]] || die "Use: ./setup.sh prepare|install|remove [chromium|google-chrome]"
  [[ $browser == chromium || $browser == google-chrome ]] || die "Unsupported browser."
  id=$(extension_id)
  if [[ $action != remove ]]; then
    [[ -x $helper ]] || die "Missing $helper. Run ./build.sh."
    "$helper" --version >/dev/null 2>&1 || die "$helper does not run on this system."
  fi
  if [[ $action == prepare ]]; then
    jq -n --arg id "$id" --arg path "$root/extension" '{extensionId:$id,extensionPath:$path}'; return
  fi
  hosts=$config/$browser/NativeMessagingHosts
  host=$hosts/$host_name.json
  plugins=$config/omarchy/plugins
  link=$plugins/omakeep
  mkdir -p -- "$hosts" "$plugins"
  [[ ! -e $link || -L $link || $link -ef $root ]] || die "Omakeep plugin path already exists and is not this checkout link."
  [[ ! -L $link || $(readlink -- "$link") == "$root" ]] || die "Omakeep plugin path belongs to another checkout."
  local json current=""
  json=$(jq -n --arg path "$helper" --arg origin "chrome-extension://$id/" \
    '{name:"com.omarchy.omakeep",description:"Omakeep local bookmark capture",path:$path,type:"stdio",allowed_origins:[$origin]}')$'\n'
  [[ ! -e $host ]] || current=$(exact "$host"; printf x)
  [[ -z $current || $current == "$json"x ]] || die "Native host registration belongs to another setup. Remove it first."
  if [[ $action == install ]]; then
    owned_write "$host" 600 "$json"
    [[ -e $link ]] || ln -s -- "$root" "$link"
  else
    [[ ! -L $link ]] || rm -- "$link"
    [[ ! -e $host ]] || rm -- "$host"
  fi
  jq -n --arg id "$id" --arg b "$browser" --arg path "$root/extension" '{extensionId:$id,browser:$b,extensionPath:$path,plugin:"omakeep"}'
}

binding=$'\n-- BEGIN Omakeep shortcut\no.bind("SUPER + SHIFT + K", "Omakeep", "omarchy shell shell toggle omakeep \'{}\'")\n-- END Omakeep shortcut\n'
shortcut() {
  local remove=$1 file=$config/hypr/bindings.lua source updated backups
  [[ -f $file ]] || die "No Hyprland bindings.lua found."
  source=$(exact "$file"; printf x); source=${source%x}
  if [[ $source == *"-- BEGIN Omakeep shortcut"* || $source == *"-- END Omakeep shortcut"* ]]; then
    [[ $source == *"$binding"* && $source != *"$binding"*"$binding"* ]] || die "Omakeep shortcut block was modified; inspect it manually."
    (( remove )) || return 0
    updated=${source/"$binding"/}
  else
    (( ! remove )) || return 0
    updated=$source$binding
  fi
  [[ -z $("$hyprctl" configerrors) ]] || die "Fix existing Hyprland configuration errors before changing shortcuts."
  if (( ! remove )) && "$hyprctl" -j binds | jq -e 'any(.[]; .modmask == 65 and ((.key|tostring|ascii_upcase) == "K" or .keycode == 45))' >/dev/null; then
    die "Super+Shift+K is already in use. Choose a shortcut manually."
  fi
  backups=$state/omakeep-backups; mkdir -p -- "$backups"
  publish "$backups/bindings-$(date +%s%3N).lua" 600 "$source"
  local mode; mode=$(stat -c %a -- "$file")
  publish "$file" "$mode" "$updated"
  if ! "$hyprctl" reload >/dev/null || [[ -n $("$hyprctl" configerrors) ]]; then
    publish "$file" "$mode" "$source"
    "$hyprctl" reload >/dev/null
    [[ -z $("$hyprctl" configerrors) ]] || die "Shortcut rollback needs inspection: Hyprland still reports errors."
    die "Hyprland rejected the Omakeep shortcut."
  fi
}

case ${1:-} in
  shortcut) shortcut 0; echo "Omakeep shortcut updated." ;;
  unshortcut) shortcut 1; echo "Omakeep shortcut updated." ;;
  *) setup "${1:-}" "${2:-chromium}" ;;
esac

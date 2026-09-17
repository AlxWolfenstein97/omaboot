#!/usr/bin/env bash
#
# Full clean-slate: menu, cache/state, and the ### omaboot colour block in
# limine.conf. Boot entries / cmdline stay untouched.
#
# Clearing limine colours needs sudo (same class as Style → Unlock themes
# staying until changed). Attempt clear before disable; if non-interactive
# sudo fails, open one floating terminal best-effort.
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_id="io.github.alxwolfenstein97.omaboot"
state="$HOME/.local/state/omarchy/omaboot"
cache="$HOME/.cache/omarchy/omaboot"
menu_lock="$HOME/.local/state/omarchy/style-extenders/menu.lock"

note() { printf 'omaboot: %s\n' "$1"; }
warn() { printf 'omaboot: %s\n' "$1" >&2; }

export OMABOOT_PLUGIN_DIR="$here"
mkdir -p "$(dirname "$menu_lock")"
(
  flock 9
  "$here/bin/omaboot" uninstall-menu || true
) 9>"$menu_lock"

if ! "$here/bin/omaboot" clear --quiet; then
  warn "could not clear limine.conf colour block (sudo required) — opening floating terminal"
  if command -v omarchy-launch-floating-terminal-with-presentation >/dev/null 2>&1; then
    omarchy-launch-floating-terminal-with-presentation \
      "$here/bin/omaboot clear" >/dev/null 2>&1 &
  else
    warn "run: $here/bin/omaboot clear"
  fi
fi

rm -rf "$state" "$cache"
mkdir -p "$state"
touch "$state/uninstalled"
note "cleared state/cache (tombstone left so quiet install cannot resurrect)"

omarchy-shell -q omarchy.menu refresh >/dev/null 2>&1 || true

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "$plugin_id" >/dev/null 2>&1 || true
fi

note "done — no omaboot menu or managed limine colour block left"
note "plugin files remain at $here until you omit/remove the plugin"
note "optional: omarchy pkg drop python-pillow  # if nothing else needs Pillow"
exit 0

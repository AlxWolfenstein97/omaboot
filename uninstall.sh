#!/usr/bin/env bash
#
# Clean-slate: menu, cache/state. Best-effort clear of the ### omaboot colour
# block in limine.conf once (sudo). Same class as Style → Unlock themes: paint
# may stay until you pick a stock / Tokyo Night boot look again — we do not
# open a floating-terminal retry.
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_id="io.github.alxwolfenstein97.omaboot"
state="$HOME/.local/state/omarchy/omaboot"
cache="$HOME/.cache/omarchy/omaboot"
menu_lock="$HOME/.local/state/omarchy/style-extenders/menu.lock"

note() { printf 'omaboot: %s\n' "$1"; }

export OMABOOT_PLUGIN_DIR="$here"
mkdir -p "$(dirname "$menu_lock")"
(
  flock 9
  "$here/bin/omaboot" uninstall-menu || true
) 9>"$menu_lock"

# Best-effort once — no floating-terminal fight if sudo is unavailable.
if ! "$here/bin/omaboot" clear --quiet 2>/dev/null; then
  note "limine colour block left in place (sudo needed) — pick a stock boot theme or run: $here/bin/omaboot clear"
fi

rm -rf "$state" "$cache"
mkdir -p "$state"
touch "$state/uninstalled"
note "cleared state/cache (tombstone left so quiet install cannot resurrect)"

omarchy-shell -q omarchy.menu refresh >/dev/null 2>&1 || true
omarchy-shell -q shell rescanPlugins >/dev/null 2>&1 || true

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "$plugin_id" >/dev/null 2>&1 || true
fi

note "done — no omaboot menu left; limine paint stays until cleared or you pick stock again"
note "plugin files remain at $here until you omit/remove the plugin"
note "optional: omarchy pkg drop python-pillow  # if nothing else needs Pillow"
exit 0

#!/usr/bin/env bash
#
# Clean-slate: menu, cache/state. Best-effort clear of the ### omaboot colour
# block in limine.conf once (sudo -n / quiet). Omarchy's plugin remove does
# not run this script — it only deletes the plugin dir — so do not rely on a
# floating-terminal sudo dance here. Prepare before removal: `omaboot clear`
# (or pick Tokyo Night) while the plugin is still installed.
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

# Best-effort once. No nested floating terminal — same class as quiet install:
# sudo that needs a password is the user's job before they remove the plugin.
if "$here/bin/omaboot" clear --quiet 2>/dev/null; then
  note "cleared omaboot limine colour block"
else
  note "limine colour block left in place (sudo needed)"
  note "prepare before removal: $here/bin/omaboot clear   # or Boot Themes → Tokyo Night"
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

note "done — no omaboot menu left; Limine paint only cleared if sudo worked"
note "plugin files remain at $here until you omit/remove the plugin"
note "optional: omarchy pkg drop python-pillow  # if nothing else needs Pillow"
exit 0

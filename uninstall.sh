#!/usr/bin/env bash
#
# Clean-slate: menu, cache/state. Best-effort clear of the ### omaboot colour
# block in limine.conf (sudo; floating terminal if password needed). If the
# prompt is dismissed, Limine stays painted — prepare with `omaboot clear`
# before remove.
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

# Best-effort theme reset (sudo). Prefer an immediate clear; if passwordless
# sudo is unavailable, open one floating terminal so the reset still happens
# instead of leaving Limine painted after the plugin is gone.
reset_cmd="$here/bin/omaboot clear --quiet"
if "$reset_cmd" 2>/dev/null; then
  note "cleared omaboot limine colour block"
elif sudo -n "$here/bin/omaboot" clear --quiet 2>/dev/null; then
  note "cleared omaboot limine colour block"
elif command -v omarchy-launch-floating-terminal-with-presentation >/dev/null 2>&1; then
  note "sudo needed to reset Limine colours — opening a floating terminal"
  omarchy-launch-floating-terminal-with-presentation \
    "$here/bin/omaboot clear" >/dev/null 2>&1 || true
  note "if you dismiss that prompt, Limine stays painted — run: $here/bin/omaboot clear"
else
  note "limine colour block left in place (sudo needed) — prepare before removal: $here/bin/omaboot clear"
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

note "done — no omaboot menu left; Limine colours cleared when sudo succeeded"
note "plugin files remain at $here until you omit/remove the plugin"
note "optional: omarchy pkg drop python-pillow  # if nothing else needs Pillow"
exit 0

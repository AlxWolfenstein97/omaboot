#!/usr/bin/env bash
#
# Full clean-slate: menu, cache/state, and the ### omaboot colour block in
# limine.conf. Boot entries / cmdline stay untouched.
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_id="io.github.alxwolfenstein97.omaboot"
state="$HOME/.local/state/omarchy/omaboot"
cache="$HOME/.cache/omarchy/omaboot"

note() { printf 'omaboot: %s\n' "$1"; }
warn() { printf 'omaboot: %s\n' "$1" >&2; }

export OMABOOT_PLUGIN_DIR="$here"
"$here/bin/omaboot" uninstall-menu || true

if ! "$here/bin/omaboot" clear --quiet; then
  warn "could not clear limine.conf colour block (sudo?) — menu/cache still removed"
fi

rm -rf "$state" "$cache"
note "cleared state/cache"

omarchy-shell -q omarchy.menu refresh >/dev/null 2>&1 || true

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "$plugin_id" >/dev/null 2>&1 || true
fi

note "done — no omaboot menu or managed limine colour block left"
note "plugin files remain at $here until you omit/remove the plugin"
exit 0

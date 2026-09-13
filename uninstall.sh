#!/usr/bin/env bash
#
# Remove OmaBoot menu wiring. Does not rewrite /boot/limine.conf — your last
# applied palette (and any custom cmdline) stays until you change it yourself.
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_id="io.github.alxwolfenstein97.omaboot"
state="$HOME/.local/state/omarchy/omaboot"
cache="$HOME/.cache/omarchy/omaboot"

note() { printf 'omaboot: %s\n' "$1"; }

export OMABOOT_PLUGIN_DIR="$here"
"$here/bin/omaboot" uninstall-menu || true

rm -rf "$state" "$cache"
note "cleared state/cache"

omarchy-shell -q omarchy.menu refresh >/dev/null 2>&1 || true

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "$plugin_id" >/dev/null 2>&1 || true
fi

note "done — plugin files left at $here; limine.conf colours left as last applied"
exit 0

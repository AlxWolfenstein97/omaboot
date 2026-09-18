#!/usr/bin/env bash
#
# Menu + cache/state. Opens a floating terminal to clear the ### omaboot Limine
# colour block (sudo) — we clean up our extra paint. Optional y/N pkg drop in
# the same floater. Omarchy's plugin remove does not run this script.
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_id="io.github.alxwolfenstein97.omaboot"
state="$HOME/.local/state/omarchy/omaboot"
cache="$HOME/.cache/omarchy/omaboot"
menu_lock="$HOME/.local/state/omarchy/style-extenders/menu.lock"

note() { printf 'omaboot: %s\n' "$1"; }

launch_cleanup_floater() {
  local -a have=()
  local pkg
  for pkg in "$@"; do
    pacman -Q "$pkg" &>/dev/null && have+=("$pkg")
  done
  local list="${have[*]}"
  local script="$state/uninstall-floater.sh"
  mkdir -p "$state"
  {
    printf '%s\n' '#!/usr/bin/env bash' 'set -uo pipefail'
    printf '%s\n' "printf '%s\n' 'OmaBoot — uninstall'"
    printf '%s\n' "printf '%s\n' 'io.github.alxwolfenstein97.omaboot'"
    printf '%s\n' "printf '%s\n' 'Style → Boot Themes — Limine colour mockups + apply'"
    printf '%s\n' "printf '%s\n' '────────────────────────────────'"
    printf '%s\n' "printf '%s\n' 'Will remove / reset (sudo):'"
    printf '%s\n' "printf '%s\n' '  • ### omaboot colour block (managed markers)'"
    printf '%s\n' "printf '%s\n' '  • restore Omarchy default Limine colours (Tokyo Night)'"
    printf '%s\n' "printf '%s\n' '────────────────────────────────'"
    printf '%s\n' "printf '%s\n' ''"
    printf '%s\n' "if $(printf '%q ' "$here/bin/omaboot" clear); then"
    printf '%s\n' "  printf 'Omarchy default (Tokyo Night) Limine colours restored\n'"
    printf '%s\n' 'else'
    printf '%s\n' "  printf 'clear failed — limine.conf may still have ### omaboot markers\n' >&2"
    printf '%s\n' 'fi'

# --- itemized optional drops (scan installed; one y/N each) ---
    if ((${#have[@]})); then
      printf '%s\n' ''
      printf '%s\n' "printf '%s\n' 'Optional package drops — scanned; only installed packages listed.'"
      printf '%s\n' "printf '%s\n' 'Answer n / Enter to keep. Close with Done when finished.'"
      for pkg in "${have[@]}"; do
        case $pkg in
          python-pillow)
            printf '%s\n' "printf '%s\n' ''"
            printf '%s\n' "printf '%s\n' 'python-pillow'"
            printf '%s\n' "printf '%s\n' '  Used by Style carousel plugins (OmaBoot/OmaVT/OmaOBS/OmaHud/OmaCursor/OmaTTY).'"
            printf '%s\n' "printf '%s\n' '  MangoHud → python-matplotlib → pillow; goverlay → MangoHud. Lutris may too.'"
            printf '%s\n' "printf '%s\n' '  Removing it breaks Style mockups until reinstalled; clear/uninstall still work without it.'"
            printf '%s\n' "printf '%s\n' '  If drop fails because those still need it — that is fine; keep Pillow.'"
            printf '%s\n' "req=\$(pacman -Qi python-pillow 2>/dev/null | awk -F': ' '/^Required By/{print \$2}')"
            printf '%s\n' "printf '  pacman Required By: %s\n' \"\${req:-none}\""
            printf '%s\n' "read -r -p 'Drop python-pillow? [y/N] ' a"
            printf '%s\n' "case \$a in"
            printf '%s\n' "  [yY]|[yY][eE][sS])"
            printf '%s\n' "    if omarchy pkg drop python-pillow; then printf 'dropped python-pillow\n'"
            printf '%s\n' "    else printf 'not dropped (other packages still need it — that is fine)\n'; fi"
            printf '%s\n' "    ;;"
            printf '%s\n' "  *) printf 'kept python-pillow\n' ;;"
            printf '%s\n' "esac"
            ;;
          terminus-font)
            printf '%s\n' "printf '%s\n' ''"
            printf '%s\n' "printf '%s\n' 'terminus-font — Terminus console faces for TTY Fonts'"
            printf '%s\n' "read -r -p 'Drop terminus-font? [y/N] ' a"
            printf '%s\n' "case \$a in"
            printf '%s\n' "  [yY]|[yY][eE][sS]) omarchy pkg drop terminus-font && printf 'dropped terminus-font\n' || printf 'not dropped\n' ;;"
            printf '%s\n' "  *) printf 'kept terminus-font\n' ;;"
            printf '%s\n' "esac"
            ;;
          python-numpy)
            printf '%s\n' "printf '%s\n' ''"
            printf '%s\n' "printf '%s\n' 'python-numpy — fast Adwaita cursor remaps (OmaCursor)'"
            printf '%s\n' "req=\$(pacman -Qi python-numpy 2>/dev/null | awk -F': ' '/^Required By/{print \$2}')"
            printf '%s\n' "printf '  pacman Required By: %s\n' \"\${req:-none}\""
            printf '%s\n' "read -r -p 'Drop python-numpy? [y/N] ' a"
            printf '%s\n' "case \$a in"
            printf '%s\n' "  [yY]|[yY][eE][sS])"
            printf '%s\n' "    if omarchy pkg drop python-numpy; then printf 'dropped python-numpy\n'"
            printf '%s\n' "    else printf 'not dropped (still required elsewhere — fine)\n'; fi"
            printf '%s\n' "    ;;"
            printf '%s\n' "  *) printf 'kept python-numpy\n' ;;"
            printf '%s\n' "esac"
            ;;
          adw-gtk-theme)
            printf '%s\n' "printf '%s\n' ''"
            printf '%s\n' "printf '%s\n' 'adw-gtk-theme — GTK theme Chroma paints over'"
            printf '%s\n' "read -r -p 'Drop adw-gtk-theme? [y/N] ' a"
            printf '%s\n' "case \$a in"
            printf '%s\n' "  [yY]|[yY][eE][sS]) omarchy pkg drop adw-gtk-theme && printf 'dropped adw-gtk-theme\n' || printf 'not dropped\n' ;;"
            printf '%s\n' "  *) printf 'kept adw-gtk-theme\n' ;;"
            printf '%s\n' "esac"
            ;;
          *)
            printf '%s\n' "printf '%s\n' ''"
            printf '%s\n' "printf 'Package: %s\n' $(printf %q "$pkg")"
            printf '%s\n' "read -r -p \"Drop $pkg? [y/N] \" a"
            printf '%s\n' "case \$a in"
            printf '%s\n' "  [yY]|[yY][eE][sS]) omarchy pkg drop $pkg && printf 'dropped\n' || printf 'not dropped\n' ;;"
            printf '%s\n' "  *) printf 'kept\n' ;;"
            printf '%s\n' "esac"
            ;;
        esac
      done
    fi

  } >"$script"
  chmod 755 "$script"
  if command -v omarchy-launch-floating-terminal-with-presentation >/dev/null 2>&1; then
    note "opening floating terminal to reset Limine paint (+ optional pkg drop)"
    omarchy-launch-floating-terminal-with-presentation "bash $(printf %q "$script")" >/dev/null 2>&1 &
  else
    note "run: $here/bin/omaboot clear"
    ((${#have[@]})) && note "optional: omarchy pkg drop $list"
  fi
}


export OMABOOT_PLUGIN_DIR="$here"

mkdir -p "$state"
touch "$state/uninstalled"
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "$plugin_id" >/dev/null 2>&1 || true
fi

mkdir -p "$(dirname "$menu_lock")"
(
  flock 9
  "$here/bin/omaboot" uninstall-menu || true
) 9>"$menu_lock"

rm -rf "$cache"
find "$state" -mindepth 1 ! -name uninstalled -delete 2>/dev/null || true
touch "$state/uninstalled"
note "cleared state/cache (tombstone left so quiet install cannot resurrect)"

omarchy-shell -q omarchy.menu refresh >/dev/null 2>&1 || true
omarchy-shell -q shell rescanPlugins >/dev/null 2>&1 || true

launch_cleanup_floater python-pillow

note "done — no omaboot menu left; Limine paint reset in floating terminal"
note "plugin files remain at $here until you omit/remove the plugin"
exit 0

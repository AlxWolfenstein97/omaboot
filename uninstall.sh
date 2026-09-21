#!/usr/bin/env bash
#
# Menu + cache/state. Clears ### omaboot Limine colour block in this TTY (sudo)
# + optional y/N pkg drop. --yes does both inline (no prompts). No floaters.
# Omarchy's plugin remove does not run this script.
#
set -euo pipefail

assume_yes=0
for arg in "$@"; do
  case $arg in --yes|-y) assume_yes=1 ;; esac
done

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_id="io.github.alxwolfenstein97.omaboot"
state="$HOME/.local/state/omarchy/omaboot"
cache="$HOME/.cache/omarchy/omaboot"
menu_lock="$HOME/.local/state/omarchy/style-extenders/menu.lock"

note() { printf 'omaboot: %s\n' "$1"; }

try_pkg_drop() {
  # Best-effort: drop packages we may have pulled. If something else still
  # needs them, pacman refuses and we leave them — that is fine.
  local pkg
  for pkg in "$@"; do
    pacman -Q "$pkg" &>/dev/null || continue
    if command -v omarchy >/dev/null 2>&1 && omarchy pkg drop "$pkg"; then
      note "dropped $pkg"
    else
      note "kept $pkg (still required elsewhere or drop failed — fine)"
    fi
  done
}

ask_pkg_drop() {
  # Interactive TTY only — no floating terminal (harder to dismiss mid-cleanup).
  local -a have=()
  local pkg a req
  for pkg in "$@"; do
    pacman -Q "$pkg" &>/dev/null && have+=("$pkg")
  done
  ((${#have[@]})) || return 0
  if [[ ! -t 0 && ! -t 1 ]]; then
    note "no TTY — skip optional pkg drop (re-run from a terminal, or uninstall.sh --yes)"
    return 0
  fi
  note "optional package drops — n / Enter keeps; pacman may refuse if still required"
  for pkg in "${have[@]}"; do
    case $pkg in
      python-pillow)
        note "python-pillow — Style carousel mockups (shared); MangoHud/goverlay/Lutris may need it"
        req=$(pacman -Qi python-pillow 2>/dev/null | awk -F': ' '/^Required By/{print $2}')
        note "  pacman Required By: ${req:-none}"
        ;;
      python-numpy)
        note "python-numpy — OmaCursor Adwaita remaps"
        req=$(pacman -Qi python-numpy 2>/dev/null | awk -F': ' '/^Required By/{print $2}')
        note "  pacman Required By: ${req:-none}"
        ;;
      terminus-font)
        note "terminus-font — OmaTTY console faces"
        ;;
      adw-gtk-theme)
        note "adw-gtk-theme — GTK theme Chroma paints over"
        ;;
      *)
        note "package: $pkg"
        ;;
    esac
    read -r -p "Drop $pkg? [y/N] " a || a=
    case $a in
      [yY]|[yY][eE][sS]) try_pkg_drop "$pkg" ;;
      *) note "kept $pkg" ;;
    esac
  done
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

if (( assume_yes )); then
  note "full wipe (--yes): resetting Limine paint inline"
  if "$here/bin/omaboot" clear; then
    note "Omarchy default Limine colours restored"
  else
    note "clear failed — limine.conf may still have ### omaboot markers"
  fi
  note "full wipe (--yes): trying package drops (kept if still required elsewhere)"
  try_pkg_drop python-pillow
elif [[ -t 0 || -t 1 ]]; then
  note "resetting Limine paint in this TTY (may prompt for sudo)"
  if "$here/bin/omaboot" clear; then
    note "Omarchy default Limine colours restored"
  else
    note "clear failed — limine.conf may still have ### omaboot markers"
  fi
  ask_pkg_drop python-pillow
else
  note "no TTY — Limine paint / pkgs not cleared; re-run from a terminal or: uninstall.sh --yes"
fi

note "done — no omaboot menu left"
if (( assume_yes )); then
  note "full wipe (--yes): removing plugin $plugin_id"
  if command -v omarchy >/dev/null 2>&1; then
    # Leave the tree before Omarchy deletes it out from under us.
    cd "${HOME:-/}" || cd /
    omarchy plugin remove "$plugin_id" --yes \
      || note "plugin remove failed — try: omarchy plugin remove $plugin_id --yes"
  else
    note "omarchy CLI missing — delete by hand: $here"
  fi
else
  note "plugin files remain at $here until you omit/remove the plugin"
  note "  omarchy plugin remove $plugin_id"
fi

exit 0

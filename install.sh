#!/usr/bin/env bash
#
# OmaBoot installer. Safe to re-run: rewrites what it owns, leaves limine
# boot entries alone. Does NOT install a theme-set hook — applying needs sudo.
#
# Flags:
#   --quiet   less chatter (used by the shell service on startup)
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
quiet=0
for arg in "$@"; do
  case $arg in
    --quiet) quiet=1 ;;
  esac
done

note() { (( quiet )) || printf 'omaboot: %s\n' "$1"; }
warn() { printf 'omaboot: %s\n' "$1" >&2; }

plugin_id="io.github.alxwolfenstein97.omaboot"
state="$HOME/.local/state/omarchy/omaboot"

# Tombstone from uninstall: Service --quiet must not resurrect wiring.
if [[ -f $state/uninstalled ]]; then
  if (( quiet )); then
    exit 0
  fi
  rm -f "$state/uninstalled"
fi

mkdir -p "$state"

chmod 755 "$here"/bin/* "$here/check.sh" \
  "$here/install.sh" "$here/uninstall.sh" 2>/dev/null || true

export OMABOOT_PLUGIN_DIR="$here"

# Packages need sudo. Interactive install can ask in this TTY; Service --quiet
# must not open floating sudo — deps are interactive-only.
pull_pkgs() {
  local -a missing=()
  local pkg
  for pkg in "$@"; do
    pacman -Q "$pkg" &>/dev/null || missing+=("$pkg")
  done
  if ((${#missing[@]} == 0)); then
    rm -f "$state/pkgs-prompted"
    return 0
  fi

  if ! command -v omarchy >/dev/null 2>&1; then
    warn "install manually: pacman -S ${missing[*]}"
    return 1
  fi

  note "installing ${missing[*]}"
  if (( ! quiet )) && [[ -t 0 || -t 1 ]]; then
    if omarchy pkg add "${missing[@]}"; then
      rm -f "$state/pkgs-prompted"
      return 0
    fi
    warn "could not install: ${missing[*]}"
    return 1
  fi

  if [[ -f $state/pkgs-prompted ]]; then
    warn "still missing ${missing[*]} — run: omarchy pkg add ${missing[*]}"
    return 1
  fi
  mkdir -p "$state"
  touch "$state/pkgs-prompted"
  local cmd="omarchy pkg add ${missing[*]}"
  [[ -n ${PULL_PKGS_AFTER:-} ]] && cmd+=" && ${PULL_PKGS_AFTER}"
  if command -v omarchy-launch-floating-terminal-with-presentation >/dev/null 2>&1; then
    warn "sudo needed for ${missing[*]} — opening a floating terminal"
    omarchy-launch-floating-terminal-with-presentation "$cmd" >/dev/null 2>&1 &
  else
    warn "run: $cmd"
  fi
  return 1
}

# Pillow draws Style carousel mockups — install before warming previews.
if (( quiet )); then
  pacman -Q python-pillow &>/dev/null \
    || warn "missing python-pillow — re-run install.sh interactively (or: omarchy pkg add python-pillow)"
else
  pull_pkgs python-pillow || true
fi

# Style extenders all rewrite the same extensions file. Shell-service --quiet
# starts them in parallel — flock so we don't clobber each other's rows.
# Quiet path debounces menu refresh (one within 3s across parallel Services);
# interactive also rescans plugins so mid-session enable shows the new row.
menu_lock="$HOME/.local/state/omarchy/style-extenders/menu.lock"
menu_sha="$HOME/.local/state/omarchy/style-extenders/menu.sha"
menu_file="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
mkdir -p "$(dirname "$menu_lock")"
(
  flock 9
  "$here/bin/omaboot" install-menu
  if [[ -f $menu_file ]]; then
    new_sha=$(sha256sum "$menu_file" 2>/dev/null | awk '{print $1}')
    old_sha=$(cat "$menu_sha" 2>/dev/null || true)
    if [[ -n $new_sha && $new_sha != "$old_sha" ]]; then
      printf '%s\n' "$new_sha" >"$menu_sha"
      if command -v omarchy-shell >/dev/null 2>&1; then
        # Debounce: parallel quiet Services all rewrite the menu; one refresh
        # within 3s is enough (avoids stacked Hypr strokes). Interactive always
        # refreshes + rescan so mid-session enable shows the new row.
        stamp="$HOME/.local/state/omarchy/style-extenders/menu.refresh"
        do_refresh=1
        if (( quiet )) && [[ -f $stamp ]]; then
          now=$(date +%s)
          then=$(stat -c %Y "$stamp" 2>/dev/null || echo 0)
          if (( now - then < 3 )); then
            do_refresh=0
          fi
        fi
        if (( do_refresh )); then
          touch "$stamp"
          omarchy-shell -q omarchy.menu refresh >/dev/null 2>&1 || true
          if (( ! quiet )); then
            omarchy-shell -q shell rescanPlugins >/dev/null 2>&1 || true
          fi
        fi
      fi
    fi
  fi
) 9>"$menu_lock"
if (( ! quiet )); then
  note "Style → Boot Themes is live; if the row is missing, run: omarchy-shell shell rescanPlugins"
fi

# Warm mockups once on interactive install — not on every shell-start --quiet.
if (( ! quiet )); then
  (
    "$here/bin/omaboot" preview >/dev/null 2>&1 || true
  ) &
fi

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin enable "$plugin_id" >/dev/null 2>&1 || true
fi

note "done — Style > Boot Themes, or '$here/bin/omaboot switcher'"
note "applying prompts for sudo in a floating terminal (not tied to theme set)"
exit 0

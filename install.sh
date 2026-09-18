#!/usr/bin/env bash
#
# OmaBoot installer. Safe to re-run: menu written once (quiet skips rewrite when
# // omaboot:start markers already exist). Leaves limine boot entries alone.
# Does NOT install a theme-set hook — applying needs sudo.
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
runtime_dir="${XDG_RUNTIME_DIR:-/tmp}/omarchy-omaboot"
pkgs_stamp="$runtime_dir/pkgs-prompted"

# Tombstone from uninstall. Disable-first in uninstall.sh means a later quiet
# Service run is a re-enable / re-add — clear tombstone + prompt stamps so the
# Style menu and package floaters can run again (old quiet-exit left peeps stuck
# with no floater after wipe).
if [[ -f $state/uninstalled ]]; then
  # Per-plugin prompt stamps + shared Pillow claim. Claim survives an ignored
  # floater and would block pillow-only plugins (OmaBoot/OmaVT/OmaOBS) on
  # same-session reinstall — drop it with the tombstone. Shell restart does
  # *not* clear these (XDG_RUNTIME_DIR); only logout/reboot or reinstall.
  rm -f "$state/uninstalled" "$pkgs_stamp"     "$runtime_dir/drm-prompted"     "$state/udev-prompted" "$state/udev-skipped" 2>/dev/null || true
  style_rt="${XDG_RUNTIME_DIR:-/tmp}/omarchy-style-extenders"
  mkdir -p "$style_rt"
  (
    flock 8
    ledger="$style_rt/shared-pkgs-claimed"
    if [[ -f $ledger ]]; then
      grep -vxF python-pillow "$ledger" >"$ledger.tmp" 2>/dev/null || true
      if [[ -s $ledger.tmp ]]; then
        mv -f "$ledger.tmp" "$ledger"
      else
        rm -f "$ledger" "$ledger.tmp"
      fi
    fi
  ) 8>"$style_rt/pkgs.lock"
fi


mkdir -p "$state"

chmod 755 "$here"/bin/* "$here/check.sh" \
  "$here/install.sh" "$here/uninstall.sh" 2>/dev/null || true

export OMABOOT_PLUGIN_DIR="$here"

# Packages need sudo. Shared python-pillow is claimed under a flock so parallel
# quiet Services do not each open a Pillow floater. Claim is session-scoped;
# same-session reinstall clears it with the uninstall tombstone (shell restart does not). Scan pacman -Q first.
# Floater: plugin header + missing pkgs only; closable via Done / default answers.
pull_pkgs() {
  local -a missing=()
  local pkg
  local style_rt="${XDG_RUNTIME_DIR:-/tmp}/omarchy-style-extenders"
  local shared_ledger="$style_rt/shared-pkgs-claimed"
  local claim_tmp
  mkdir -p "$style_rt" "$runtime_dir" "$state"

  for pkg in "$@"; do
    pacman -Q "$pkg" &>/dev/null || missing+=("$pkg")
  done

  if ((${#missing[@]})); then
    claim_tmp=$(mktemp)
    (
      flock 8
      local claimed="" line
      [[ -f $shared_ledger ]] && claimed=$(cat "$shared_ledger" 2>/dev/null || true)
      local -a still=()
      for pkg in "${missing[@]}"; do
        if [[ $pkg == python-pillow ]] && grep -qxF python-pillow <<<"$claimed"; then
          continue
        fi
        still+=("$pkg")
        if [[ $pkg == python-pillow ]]; then
          printf '%s\n' python-pillow >>"$shared_ledger"
        fi
      done
      printf '%s\n' "${still[@]}" >"$claim_tmp"
    ) 8>"$style_rt/pkgs.lock"
    mapfile -t missing <"$claim_tmp"
    rm -f "$claim_tmp"
    # drop empty line from mapfile
    local -a cleaned=()
    for pkg in "${missing[@]}"; do
      [[ -n $pkg ]] && cleaned+=("$pkg")
    done
    missing=("${cleaned[@]}")
  fi

  if ((${#missing[@]} == 0)); then
    rm -f "$pkgs_stamp"
    return 0
  fi

  if ! command -v omarchy >/dev/null 2>&1; then
    warn "OmaBoot needs ${missing[*]} for: Style → Boot Themes — Limine colour mockups + apply — install manually: pacman -S ${missing[*]}"
    return 1
  fi

  note "OmaBoot needs ${missing[*]} — Style → Boot Themes — Limine colour mockups + apply"
  if (( ! quiet )) && [[ -t 0 || -t 1 ]]; then
    printf '%s\n' "OmaBoot"
    printf '%s\n' "io.github.alxwolfenstein97.omaboot"
    printf '%s\n' "Style → Boot Themes — Limine colour mockups + apply"
    printf '%s\n' "────────────────────────────────"
    printf '%s\n' "Needs to install (sudo / pacman) — only packages missing on this system:"
    for pkg in "${missing[@]}"; do
      case $pkg in
        python-pillow) printf '  • %s — %s\n' "$pkg" 'draw Boot Themes carousel mockups' ;;
        *) printf '  • %s\n' "$pkg" ;;
      esac
    done
    printf '%s\n' "────────────────────────────────"
    printf '%s\n' ""
    if omarchy pkg add "${missing[@]}"; then
      rm -f "$pkgs_stamp"
      return 0
    fi
    warn "OmaBoot could not install: ${missing[*]}"
    return 1
  fi

  if [[ -f $pkgs_stamp ]]; then
    warn "OmaBoot still missing ${missing[*]} (Style → Boot Themes — Limine colour mockups + apply) — run: omarchy pkg add ${missing[*]}"
    return 1
  fi
  mkdir -p "$runtime_dir"
  touch "$pkgs_stamp"
  local script="$state/install-floater.sh"
  {
    printf '%s\n' '#!/usr/bin/env bash' 'set -uo pipefail'
    printf '%s\n' "printf '%s\\n' 'OmaBoot'"
    printf '%s\n' "printf '%s\\n' 'io.github.alxwolfenstein97.omaboot'"
    printf '%s\n' "printf '%s\\n' 'Style → Boot Themes — Limine colour mockups + apply'"
    printf '%s\n' "printf '%s\\n' '────────────────────────────────'"
    printf '%s\n' "printf '%s\\n' 'Needs to install (sudo / pacman) — only packages missing on this system:'"
    for pkg in "${missing[@]}"; do
      case $pkg in
        python-pillow) printf '%s\n' "printf '  • %s — %s\\n' 'python-pillow' 'draw Boot Themes carousel mockups'" ;;
        *) printf '%s\n' "printf '  • %s\\n' $(printf %q "$pkg")" ;;
      esac
    done
    printf '%s\n' "printf '%s\\n' '────────────────────────────────'"
    printf '%s\n' "printf '%s\\n' ''"
    printf '%s\n' "omarchy pkg add ${missing[*]}"

  } >"$script"
  chmod 755 "$script"
  if command -v omarchy-launch-floating-terminal-with-presentation >/dev/null 2>&1; then
    warn "OmaBoot missing ${missing[*]} (Style → Boot Themes — Limine colour mockups + apply) — opening floating terminal"
    omarchy-launch-floating-terminal-with-presentation "bash $(printf %q "$script")" >/dev/null 2>&1 &
  else
    warn "OmaBoot: run omarchy pkg add ${missing[*]}"
  fi
  return 1
}




# Pillow draws Style carousel mockups — install before warming previews.
# Interactive: ask in this TTY. Quiet/Service: one floating terminal once
# (pkgs-prompted), once per login session (runtime stamp); again after reboot or reinstall.
pull_pkgs python-pillow || true

# Style extenders share omarchy-menu.jsonc — flock so parallel Services don't
# clobber each other. Interactive: always install-menu. Quiet: only if our
# markers are absent (no rewrite/normalize every boot). Refresh only when written.
menu_lock="$HOME/.local/state/omarchy/style-extenders/menu.lock"
menu_sha="$HOME/.local/state/omarchy/style-extenders/menu.sha"
menu_file="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
mkdir -p "$(dirname "$menu_lock")"
(
  flock 9
  # Scrub Style rows for siblings removed via plugin remove (no uninstall.sh).
  scrubbed=0
  scrub_out=$(python3 - <<'ORPHANSCRUB' || true
from pathlib import Path
import re
menu = Path.home() / ".config/omarchy/extensions/omarchy-menu.jsonc"
if not menu.is_file():
    raise SystemExit(0)
plugins = Path.home() / ".config/omarchy/plugins"
pairs = [
    ("omacursor", "io.github.alxwolfenstein97.omacursor"),
    ("omaobs", "io.github.alxwolfenstein97.omaobs"),
    ("omaboot", "io.github.alxwolfenstein97.omaboot"),
    ("omavt", "io.github.alxwolfenstein97.omavt"),
    ("omatty", "io.github.alxwolfenstein97.omatty"),
    ("omahud", "io.github.alxwolfenstein97.omahud"),
]
text = menu.read_text(encoding="utf-8")
orig = text
for marker, pid in pairs:
    if (plugins / pid).is_dir():
        continue
    start, end = f"// {marker}:start", f"// {marker}:end"
    if start not in text:
        continue
    text = re.sub(re.escape(start) + r".*?" + re.escape(end) + r"\n?", "", text, flags=re.S)
if text != orig:
    menu.write_text(text, encoding="utf-8")
    print("scrubbed-orphan-style-menus")
ORPHANSCRUB
  )
  [[ $scrub_out == *scrubbed-orphan-style-menus* ]] && scrubbed=1
  write_menu=1
  if (( quiet )) && [[ -f $menu_file ]] && grep -qF '// omaboot:start' "$menu_file"; then
    write_menu=0
  fi
  if (( write_menu )); then
    "$here/bin/omaboot" install-menu
    if [[ -f $menu_file ]]; then
      new_sha=$(sha256sum "$menu_file" 2>/dev/null | awk '{print $1}')
      old_sha=$(cat "$menu_sha" 2>/dev/null || true)
      if [[ -n $new_sha && $new_sha != "$old_sha" ]]; then
        printf '%s\n' "$new_sha" >"$menu_sha"
        if command -v omarchy-shell >/dev/null 2>&1; then
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
            # Quiet Service installs need rescan too — otherwise Style rows
            # (esp. OBS Themes) stay invisible until a manual shell restart.
            omarchy-shell -q shell rescanPlugins >/dev/null 2>&1 || true
          fi
        fi
      fi
    fi
  fi
  if (( scrubbed && ! write_menu )); then
    if [[ -f $menu_file ]]; then
      new_sha=$(sha256sum "$menu_file" 2>/dev/null | awk '{print $1}')
      old_sha=$(cat "$menu_sha" 2>/dev/null || true)
      if [[ -n $new_sha && $new_sha != "$old_sha" ]]; then
        printf '%s\n' "$new_sha" >"$menu_sha"
      fi
    fi
    if command -v omarchy-shell >/dev/null 2>&1; then
      stamp="$HOME/.local/state/omarchy/style-extenders/menu.refresh"
      touch "$stamp"
      omarchy-shell -q omarchy.menu refresh >/dev/null 2>&1 || true
      omarchy-shell -q shell rescanPlugins >/dev/null 2>&1 || true
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

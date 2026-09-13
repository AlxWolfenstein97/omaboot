#!/usr/bin/env bash
# Lightweight self-check for OmaBoot (no sudo, no live /boot writes).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
pass() { printf 'ok  %s\n' "$1"; }
bad()  { printf 'FAIL %s\n' "$1"; fail=1; }

[[ -x $here/bin/omaboot ]] || bad "omaboot not executable"
[[ -x $here/bin/omaboot-switcher ]] || bad "omaboot-switcher not executable"
[[ -f $here/manifest.json ]] || bad "manifest.json missing"
[[ -f $here/lib/omaboot.py ]] || bad "lib/omaboot.py missing"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/themes/fixture" "$tmp/state" "$tmp/cache" \
  "$tmp/.config/omarchy/themes" "$tmp/.config/omarchy/extensions" \
  "$tmp/.local/state/omarchy/current" \
  "$tmp/default/limine"

cat >"$tmp/themes/fixture/colors.toml" <<'EOF'
mode = "dark"
accent = "#FF3D9A"
background = "#0B0618"
foreground = "#F2E8FF"
dark_background = "#070412"
darker_background = "#04020C"
lighter_background = "#1A1030"
muted = "#5A4A78"
selection = "#2A1848"
red = "#FF3355"
green = "#3DFF9A"
yellow = "#FFD400"
blue = "#5B7CFF"
magenta = "#FF3D9A"
cyan = "#00E8FF"
EOF

# Stock Omarchy Limine default (Tokyo Night) — same family as default Plymouth.
cat >"$tmp/default/limine/limine.conf" <<'EOF'
interface_branding: Omarchy Bootloader
interface_branding_color: 9ece6a
interface_help_color: 9ece6a
interface_help_color_bright: 9ece6a
term_background: 1a1b26
backdrop: 1a1b26
term_palette: 15161e;f7768e;9ece6a;e0af68;7aa2f7;bb9af7;7dcfff;a9b1d6
term_palette_bright: 414868;f7768e;9ece6a;e0af68;7aa2f7;bb9af7;7dcfff;c0caf5
term_foreground: c0caf5
term_foreground_bright: c0caf5
term_background_bright: 24283b
EOF

# Fake limine.conf with custom cmdline (iommu-style extras) that must survive.
cat >"$tmp/limine.conf" <<'EOF'
### Read more at config document: https://github.com/limine-bootloader/limine/blob/trunk/CONFIG.md
#timeout: 3
default_entry: 2
interface_branding: Omarchy Bootloader
interface_branding_color: 9ece6a
interface_help_color: 9ece6a
interface_help_color_bright: 9ece6a
hash_mismatch_panic: no

term_background: 1a1b26
backdrop: 1a1b26

# Terminal colors (Tokyo Night palette)
term_palette: 15161e;f7768e;9ece6a;e0af68;7aa2f7;bb9af7;7dcfff;a9b1d6
term_palette_bright: 414868;f7768e;9ece6a;e0af68;7aa2f7;bb9af7;7dcfff;c0caf5

# Text colors
term_foreground: c0caf5
term_foreground_bright: c0caf5
term_background_bright: 24283b
/+Omarchy
comment: Omarchy
  //linux
  protocol: efi
  path: boot():/EFI/Linux/omarchy_linux.efi
  cmdline: root=PARTUUID=deadbeef rw intel_iommu=on iommu=pt video=efifb:off quiet splash

/EFI fallback
comment: Default EFI loader
protocol: efi
path: boot():/EFI/BOOT/BOOTX64.EFI
EOF

ln -s "$tmp/themes/fixture" "$tmp/.config/omarchy/themes/fixture"
printf 'fixture\n' >"$tmp/.local/state/omarchy/current/theme.name"

export OMABOOT_HOME="$tmp"
export OMABOOT_PLUGIN_DIR="$here"
export OMARCHY_PATH="$tmp"
export OMABOOT_STATE_DIR="$tmp/state"
export OMABOOT_CACHE_DIR="$tmp/cache"
export OMABOOT_LIMINE_CONF="$tmp/limine.conf"

if "$here/bin/omaboot" list | head -1 | grep -qx default; then
  pass "list leads with default"
else
  bad "list leads with default"
fi

if "$here/bin/omaboot" list | grep -qx fixture; then
  pass "list discovers fixture"
else
  bad "list discovers fixture"
fi

if "$here/bin/omaboot" set fixture --quiet; then
  pass "set fixture"
else
  bad "set fixture"
fi

grep -q '### omaboot:start' "$tmp/limine.conf" && pass "managed block start" || bad "managed block start"
grep -q '### omaboot:end' "$tmp/limine.conf" && pass "managed block end" || bad "managed block end"
grep -q 'theme: fixture' "$tmp/limine.conf" && pass "theme tag" || bad "theme tag"
grep -q 'interface_branding_color: 3dff9a' "$tmp/limine.conf" && pass "brand green" || bad "brand green"
grep -q 'term_background: 0b0618' "$tmp/limine.conf" && pass "background" || bad "background"
grep -q 'intel_iommu=on iommu=pt' "$tmp/limine.conf" && pass "custom cmdline kept" || bad "custom cmdline kept"
grep -q 'interface_branding: Omarchy Bootloader' "$tmp/limine.conf" && pass "branding text kept" || bad "branding text kept"
grep -q 'default_entry: 2' "$tmp/limine.conf" && pass "default_entry kept" || bad "default_entry kept"
# Stock palette lines should not remain outside the block as duplicates.
stock_outside=$(awk '
  /### omaboot:start/{inblock=1; next}
  /### omaboot:end/{inblock=0; next}
  !inblock && /^term_palette:/ {print}
' "$tmp/limine.conf" | wc -l)
[[ $stock_outside -eq 0 ]] && pass "no duplicate term_palette" || bad "no duplicate term_palette"

# Second apply replaces the one block (not append another).
"$here/bin/omaboot" set fixture --quiet
blocks=$(grep -c '### omaboot:start' "$tmp/limine.conf" || true)
[[ $blocks -eq 1 ]] && pass "single block after re-set" || bad "single block after re-set"

[[ "$(cat "$tmp/state/current")" == "fixture" ]] && pass "state current" || bad "state current"

if "$here/bin/omaboot" preview fixture >/dev/null; then
  [[ -f $tmp/cache/previews/fixture.png ]] && pass "preview png" || bad "preview png"
else
  bad "preview fixture"
fi

# Stock Default — reads packaged limine.conf, same family as default Plymouth unlock.
if "$here/bin/omaboot" set default --quiet; then
  pass "set default"
else
  bad "set default"
fi
grep -q 'theme: default' "$tmp/limine.conf" && pass "default theme tag" || bad "default theme tag"
grep -q 'term_background: 1a1b26' "$tmp/limine.conf" && pass "default bg #1a1b26" || bad "default bg #1a1b26"
grep -q 'interface_branding_color: 9ece6a' "$tmp/limine.conf" && pass "default brand green" || bad "default brand green"
grep -q 'intel_iommu=on iommu=pt' "$tmp/limine.conf" && pass "cmdline after default" || bad "cmdline after default"
[[ "$(cat "$tmp/state/current")" == "default" ]] && pass "state default" || bad "state default"

if "$here/bin/omaboot" preview default >/dev/null; then
  [[ -f $tmp/cache/previews/default.png ]] && pass "default preview png" || bad "default preview png"
else
  bad "preview default"
fi

# Append-once path: conf with no colour keys at all.
cat >"$tmp/limine-bare.conf" <<'EOF'
default_entry: 1
interface_branding: Custom Box
/+OS
  protocol: efi
  path: boot():/EFI/Linux/os.efi
  cmdline: root=UUID=abc rw custom_flag=1
EOF
export OMABOOT_LIMINE_CONF="$tmp/limine-bare.conf"
"$here/bin/omaboot" set fixture --quiet
grep -q '### omaboot:start' "$tmp/limine-bare.conf" && pass "append block when missing" || bad "append block when missing"
grep -q 'custom_flag=1' "$tmp/limine-bare.conf" && pass "bare cmdline kept" || bad "bare cmdline kept"
grep -q 'interface_branding: Custom Box' "$tmp/limine-bare.conf" && pass "custom branding kept" || bad "custom branding kept"

if command -v omarchy >/dev/null 2>&1; then
  if omarchy plugin validate "$here" >/dev/null 2>&1; then
    pass "omarchy plugin validate"
  else
    bad "omarchy plugin validate"
  fi
fi

if (( fail )); then
  echo "omaboot check: FAILED"
  exit 1
fi
echo "omaboot check: all good"
exit 0

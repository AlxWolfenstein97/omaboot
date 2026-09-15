#!/usr/bin/env python3
"""OmaBoot — Style-menu Limine boot palettes from any Omarchy theme.

Discovers every theme with a colors.toml (no extra theme assets required),
renders centered Limine-style mockups for the Style carousel, and patches
only a managed colour block in limine.conf (sudo). Boot entries and any
custom cmdline stay untouched. Not hooked to theme-set — boot is not
user-land and needs a password. Mockups are illustrative — Limine has no
headless renderer, so these are not WYSIWYG boot screenshots.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont

PLUGIN_ID = "io.github.alxwolfenstein97.omaboot"
BLOCK_START = "### omaboot:start"
BLOCK_END = "### omaboot:end"
MENU_START = "  // omaboot:start"
MENU_END = "  // omaboot:end"

HEX_RE = re.compile(r"^#?[0-9A-Fa-f]{6}$")
ENTRY_LINE_RE = re.compile(r"^/")  # Limine boot entries start with /

# Aesthetic keys we own. Both spellings so stock or user British aliases get
# scooped into the managed block instead of left as duplicates.
MANAGED_KEYS = frozenset(
    {
        "interface_branding_color",
        "interface_branding_colour",
        "interface_help_color",
        "interface_help_colour",
        "interface_help_color_bright",
        "interface_help_colour_bright",
        "term_background",
        "backdrop",
        "term_palette",
        "term_palette_bright",
        "term_foreground",
        "term_foreground_bright",
        "term_background_bright",
    }
)

# Written form (American, matches stock Omarchy limine.conf).
WRITE_KEYS = (
    "interface_branding_color",
    "interface_help_color",
    "interface_help_color_bright",
    "term_background",
    "backdrop",
    "term_palette",
    "term_palette_bright",
    "term_foreground",
    "term_foreground_bright",
    "term_background_bright",
)


def home() -> Path:
    return Path(os.environ.get("OMABOOT_HOME", Path.home())).expanduser()


def omarchy_path() -> Path:
    return Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"))


def plugin_dir() -> Path:
    override = os.environ.get("OMABOOT_PLUGIN_DIR")
    if override:
        return Path(override).expanduser()
    return Path(__file__).resolve().parent.parent


def limine_conf_path() -> Path:
    override = os.environ.get("OMABOOT_LIMINE_CONF")
    if override:
        return Path(override).expanduser()
    return Path("/boot/limine.conf")


def paths() -> dict[str, Path]:
    h = home()
    return {
        "user_themes": h / ".config/omarchy/themes",
        "stock_themes": omarchy_path() / "themes",
        "state": Path(os.environ.get("OMABOOT_STATE_DIR", h / ".local/state/omarchy/omaboot")),
        "cache": Path(os.environ.get("OMABOOT_CACHE_DIR", h / ".cache/omarchy/omaboot")),
        "menu": h / ".config/omarchy/extensions/omarchy-menu.jsonc",
        "current_theme_name": h / ".local/state/omarchy/current/theme.name",
        "limine": limine_conf_path(),
    }


def note(msg: str) -> None:
    print(f"omaboot: {msg}", file=sys.stderr)


def slugify(name: str) -> str:
    cleaned = re.sub(r"<[^>]+>", "", name or "")
    return cleaned.strip().lower().replace(" ", "-")


def pretty_name(slug: str) -> str:
    return re.sub(
        r"(^|-)([a-z])",
        lambda m: (" " if m.group(1) == "-" else "") + m.group(2).upper(),
        slugify(slug),
    )


def parse_hex(value: str, fallback: str) -> str:
    raw = (value or fallback).strip().strip('"').strip("'")
    if not HEX_RE.match(raw):
        raw = fallback
    if not raw.startswith("#"):
        raw = "#" + raw
    return raw.lower()


def bare_hex(value: str, fallback: str = "000000") -> str:
    return parse_hex(value, fallback).lstrip("#")


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    h = bare_hex(value)
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def rgb_to_hex(rgb: tuple[int, int, int]) -> str:
    return "#{:02x}{:02x}{:02x}".format(*(max(0, min(255, int(c))) for c in rgb))


def mix(a: str, b: str, t: float) -> str:
    ar, ag, ab = hex_to_rgb(a)
    br, bg, bb = hex_to_rgb(b)
    return rgb_to_hex(
        (
            round(ar + (br - ar) * t),
            round(ag + (bg - ag) * t),
            round(ab + (bb - ab) * t),
        )
    )


def lighten(color: str, amount: float) -> str:
    return mix(color, "#ffffff", amount)


def darken(color: str, amount: float) -> str:
    return mix(color, "#000000", amount)


def read_colors_toml(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, _, value = stripped.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key:
            data[key] = value
    return data


def theme_dir(slug: str) -> Path | None:
    slug = slugify(slug)
    for root in (paths()["user_themes"], paths()["stock_themes"]):
        candidate = root / slug
        if (candidate / "colors.toml").is_file():
            return candidate
    return None


def list_theme_slugs() -> list[str]:
    found: set[str] = set()
    for root in (paths()["user_themes"], paths()["stock_themes"]):
        if not root.is_dir():
            continue
        for entry in root.iterdir():
            if entry.name.startswith("."):
                continue
            if entry.is_dir() or entry.is_symlink():
                if (entry / "colors.toml").is_file():
                    found.add(entry.name)
    return sorted(found)


def current_omarchy_slug() -> str | None:
    name_path = paths()["current_theme_name"]
    if name_path.is_file():
        return slugify(name_path.read_text(encoding="utf-8").strip())
    return None


def current_omaboot_slug() -> str | None:
    current = paths()["state"] / "current"
    if current.is_file():
        return slugify(current.read_text(encoding="utf-8").strip())
    return None


def palette_from_theme(slug: str) -> dict[str, Any]:
    """Map colors.toml → Limine keys without assuming a stock Omarchy palette."""
    directory = theme_dir(slug)
    if directory is None:
        raise FileNotFoundError(f"theme not found or missing colors.toml: {slug}")

    raw = read_colors_toml(directory / "colors.toml")

    background = parse_hex(raw.get("background", ""), "#1a1b26")
    dark_background = parse_hex(raw.get("dark_background", ""), darken(background, 0.2))
    darker_background = parse_hex(raw.get("darker_background", ""), darken(background, 0.35))
    lighter_background = parse_hex(raw.get("lighter_background", ""), lighten(background, 0.12))
    foreground = parse_hex(raw.get("foreground", ""), "#a9b1d6")
    bright_foreground = parse_hex(
        raw.get("bright_foreground", raw.get("light_foreground", "")),
        lighten(foreground, 0.15),
    )
    muted = parse_hex(raw.get("muted", ""), lighten(dark_background, 0.25))
    accent = parse_hex(raw.get("accent", raw.get("blue", "")), "#7aa2f7")
    red = parse_hex(raw.get("red", ""), "#f7768e")
    green = parse_hex(raw.get("green", ""), accent)
    yellow = parse_hex(raw.get("yellow", ""), "#e0af68")
    blue = parse_hex(raw.get("blue", ""), accent)
    magenta = parse_hex(raw.get("magenta", ""), "#bb9af7")
    cyan = parse_hex(raw.get("cyan", ""), "#7dcfff")

    bright_red = parse_hex(raw.get("bright_red", ""), lighten(red, 0.1))
    bright_green = parse_hex(raw.get("bright_green", ""), lighten(green, 0.1))
    bright_yellow = parse_hex(raw.get("bright_yellow", ""), lighten(yellow, 0.1))
    bright_blue = parse_hex(raw.get("bright_blue", ""), lighten(blue, 0.1))
    bright_magenta = parse_hex(raw.get("bright_magenta", ""), lighten(magenta, 0.1))
    bright_cyan = parse_hex(raw.get("bright_cyan", ""), lighten(cyan, 0.1))

    # Branding tint: prefer green when the theme ships one, else accent.
    brand = green if raw.get("green") else accent

    term_palette = ";".join(
        bare_hex(c)
        for c in (
            dark_background,
            red,
            green,
            yellow,
            blue,
            magenta,
            cyan,
            foreground,
        )
    )
    term_palette_bright = ";".join(
        bare_hex(c)
        for c in (
            muted,
            bright_red,
            bright_green,
            bright_yellow,
            bright_blue,
            bright_magenta,
            bright_cyan,
            bright_foreground,
        )
    )

    return {
        "slug": slugify(slug),
        "name": pretty_name(slug),
        "background": background,
        "dark_background": dark_background,
        "darker_background": darker_background,
        "lighter_background": lighter_background,
        "foreground": foreground,
        "bright_foreground": bright_foreground,
        "muted": muted,
        "accent": accent,
        "brand": brand,
        "red": red,
        "green": green,
        "yellow": yellow,
        "blue": blue,
        "magenta": magenta,
        "cyan": cyan,
        "limine": {
            "interface_branding_color": bare_hex(brand),
            "interface_help_color": bare_hex(brand),
            "interface_help_color_bright": bare_hex(brand),
            "term_background": bare_hex(background),
            "backdrop": bare_hex(background),
            "term_palette": term_palette,
            "term_palette_bright": term_palette_bright,
            "term_foreground": bare_hex(bright_foreground),
            "term_foreground_bright": bare_hex(bright_foreground),
            "term_background_bright": bare_hex(lighter_background),
        },
    }


def render_block(palette: dict[str, Any]) -> str:
    lines = [
        BLOCK_START,
        f"# Omarchy boot palette — managed by omaboot ({PLUGIN_ID})",
        f"# theme: {palette['slug']}",
        "# Edit via Style → Boot Themes. Everything outside this block is left alone.",
    ]
    for key in WRITE_KEYS:
        lines.append(f"{key}: {palette['limine'][key]}")
    lines.append(BLOCK_END)
    return "\n".join(lines) + "\n"


def _is_managed_assignment(line: str) -> bool:
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        return False
    if ":" not in stripped:
        return False
    key = stripped.split(":", 1)[0].strip().lower()
    return key in MANAGED_KEYS


def _strip_managed_outside_block(text: str) -> str:
    """Drop loose managed colour lines and any prior omaboot block."""
    # Remove existing managed block first.
    text = re.sub(
        re.escape(BLOCK_START) + r".*?" + re.escape(BLOCK_END) + r"\n?",
        "",
        text,
        flags=re.S,
    )
    out: list[str] = []
    for line in text.splitlines(keepends=True):
        if _is_managed_assignment(line):
            continue
        # Drop the stock "Terminal colors (...)" comment that only describes
        # the palette we just removed — leave every other comment alone.
        if re.match(r"^#\s*Terminal colors\b", line.strip()):
            continue
        out.append(line)
    return "".join(out)


def patch_limine_conf(existing: str, palette: dict[str, Any]) -> str:
    """Insert or replace the managed colour block; preserve all other content.

    Boot entries (lines starting with `/`), custom cmdline, iommu flags,
    timeout, branding text, etc. are never rewritten — only aesthetic keys.
    """
    cleaned = _strip_managed_outside_block(existing)
    block = render_block(palette)

    lines = cleaned.splitlines(keepends=True)
    insert_at = len(lines)
    for index, line in enumerate(lines):
        if ENTRY_LINE_RE.match(line):
            insert_at = index
            break

    # Keep a blank line before the first entry when we insert ahead of one.
    prefix = lines[:insert_at]
    suffix = lines[insert_at:]
    while prefix and prefix[-1].strip() == "":
        prefix.pop()
    while suffix and suffix[0].strip() == "":
        suffix.pop(0)

    parts: list[str] = []
    if prefix:
        parts.append("".join(prefix).rstrip("\n") + "\n\n")
    parts.append(block)
    if suffix:
        parts.append("\n" + "".join(suffix).lstrip("\n"))
        if not parts[-1].endswith("\n"):
            parts[-1] += "\n"
    return "".join(parts)


def read_limine_conf() -> str:
    path = limine_conf_path()
    if path.is_file() and os.access(path, os.R_OK):
        return path.read_text(encoding="utf-8")
    result = subprocess.run(
        ["sudo", "cat", "--", str(path)],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        err = (result.stderr or result.stdout or "").strip() or f"exit {result.returncode}"
        raise RuntimeError(f"failed to read {path}: {err}")
    return result.stdout


def write_limine_conf(content: str) -> None:
    path = limine_conf_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    if os.access(path.parent, os.W_OK) and (not path.exists() or os.access(path, os.W_OK)):
        atomic_write(path, content)
        return

    # Privileged path: stage then install so a partial tee cannot truncate the
    # live boot config if sudo fails mid-write.
    with tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8",
        prefix="omaboot-limine.",
        suffix=".conf",
        delete=False,
    ) as handle:
        handle.write(content)
        handle.flush()
        os.fsync(handle.fileno())
        staged = handle.name

    try:
        script = (
            "set -euo pipefail\n"
            f'dest={json.dumps(str(path))}\n'
            f'src={json.dumps(staged)}\n'
            'tmp=$(mktemp --tmpdir="$(dirname -- "$dest")" ".$(basename -- "$dest").omaboot.XXXXXXXX")\n'
            'cp --reflink=never -- "$src" "$tmp"\n'
            'chown root:root -- "$tmp"\n'
            'chmod 644 -- "$tmp"\n'
            'mv -f -- "$tmp" "$dest"\n'
        )
        result = subprocess.run(
            ["sudo", "/bin/bash", "-c", script],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            err = (result.stderr or result.stdout or "").strip() or f"exit {result.returncode}"
            raise RuntimeError(f"failed to write {path}: {err}")
    finally:
        try:
            os.unlink(staged)
        except FileNotFoundError:
            pass


def atomic_write(path: Path, content: str | bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        if isinstance(content, bytes):
            with os.fdopen(fd, "wb") as handle:
                handle.write(content)
                handle.flush()
                os.fsync(handle.fileno())
        else:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(content)
                handle.flush()
                os.fsync(handle.fileno())
        os.replace(tmp, path)
    finally:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass


def try_font(size: int) -> ImageFont.ImageFont:
    candidates = [
        "/usr/share/fonts/liberation/LiberationMono-Regular.ttf",
        "/usr/share/fonts/Adwaita/AdwaitaMono-Regular.ttf",
        "/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf",
        "/usr/share/fonts/TTF/DejaVuSansMono.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
        "/usr/share/fonts/noto/NotoSansMono-Regular.ttf",
    ]
    for path in candidates:
        if Path(path).is_file():
            try:
                return ImageFont.truetype(path, size=size)
            except OSError:
                continue
    return ImageFont.load_default()


def branding_label(existing_conf: str | None = None) -> str:
    if existing_conf:
        for line in existing_conf.splitlines():
            stripped = line.strip()
            if ":" not in stripped:
                continue
            key, _, value = stripped.partition(":")
            if key.strip().lower() == "interface_branding" and value.strip():
                return value.strip()
    return "Omarchy Bootloader"


# omarchy-menu-images thumbnails every source to 1536×864 (16:9) with
# smartcrop BEFORE the Style carousel shows it in a 768×475 tile. Matching
# that size avoids a second crop. Current Limine chrome is dead-centered, so
# side gutters are mostly empty — carousel crop barely touches the subject.
MOCKUP_SIZE = (1536, 864)


def omarchy_pkg_version() -> str:
    """Best-effort Omarchy package version for the footer stamp (e.g. 4.0.3-1)."""
    try:
        out = subprocess.check_output(
            ["pacman", "-Q", "omarchy"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        parts = out.split()
        if len(parts) >= 2:
            return parts[1]
    except (OSError, subprocess.SubprocessError):
        pass
    return "4.0.3-1"


def _text_size(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.ImageFont) -> tuple[int, int]:
    bbox = draw.textbbox((0, 0), text, font=font)
    return bbox[2] - bbox[0], bbox[3] - bbox[1]


def _draw_help_pair(
    draw: ImageDraw.ImageDraw,
    x: int,
    y: int,
    key: str,
    label: str,
    font: ImageFont.ImageFont,
    key_rgb: tuple[int, int, int],
    label_rgb: tuple[int, int, int],
    gap: int = 8,
) -> int:
    """Draw KEY + label; return width consumed."""
    draw.text((x, y), key, font=font, fill=key_rgb)
    kw, _ = _text_size(draw, key, font)
    lx = x + kw + gap
    draw.text((lx, y), label, font=font, fill=label_rgb)
    lw, _ = _text_size(draw, label, font)
    return kw + gap + lw


def _center_help_row(
    draw: ImageDraw.ImageDraw,
    y: int,
    pairs: list[tuple[str, str]],
    font: ImageFont.ImageFont,
    key_rgb: tuple[int, int, int],
    label_rgb: tuple[int, int, int],
    canvas_w: int,
    pair_gap: int = 28,
) -> None:
    widths = []
    for key, label in pairs:
        kw, _ = _text_size(draw, key, font)
        lw, _ = _text_size(draw, label, font)
        widths.append(kw + 8 + lw)
    total = sum(widths) + pair_gap * (len(pairs) - 1)
    x = (canvas_w - total) // 2
    for index, (key, label) in enumerate(pairs):
        used = _draw_help_pair(draw, x, y, key, label, font, key_rgb, label_rgb)
        x += used + pair_gap


def render_mockup(
    palette: dict[str, Any],
    dest: Path,
    size: tuple[int, int] = MOCKUP_SIZE,
    branding: str = "Omarchy Bootloader",
    version: str | None = None,
) -> Path:
    """Limine-like boot chrome from palette (current Omarchy 4 / Limine 12 layout).

    Dead-centered: branding, help under the title, snapshot tree with
    ``N | timestamp`` rows, inverse selection, version footer. Not a framebuffer
    capture — Limine has no headless renderer. Layout tracked from a QEMU
    Tokyo Night capture of current Omarchy Limine (older Manual shot was 2.x/3.x).
    """
    w, h = size
    bg = palette["background"]
    brand = palette["brand"]
    fg = palette["bright_foreground"]
    version_ink = palette.get("cyan", palette["accent"])
    ver = version or omarchy_pkg_version()

    bg_rgb = hex_to_rgb(bg)
    brand_rgb = hex_to_rgb(brand)
    fg_rgb = hex_to_rgb(fg)
    version_rgb = hex_to_rgb(version_ink)
    # Limine reverse-video selection: bright fg block, dark ink.
    sel_bg_rgb = fg_rgb
    sel_fg_rgb = bg_rgb

    img = Image.new("RGB", size, bg_rgb)
    draw = ImageDraw.Draw(img)

    font_help = try_font(20)
    font_brand = try_font(28)
    font_menu = try_font(24)
    font_ver = try_font(18)

    # --- Header cluster (centered): branding, then two help rows ---
    brand_w, brand_h = _text_size(draw, branding, font_brand)
    header_top = 64
    draw.text(((w - brand_w) // 2, header_top), branding, font=font_brand, fill=brand_rgb)

    help1_y = header_top + brand_h + 18
    _center_help_row(
        draw,
        help1_y,
        [("ARROWS", "Select"), ("ENTER", "Expand")],
        font_help,
        brand_rgb,
        fg_rgb,
        w,
    )
    help2_y = help1_y + 28
    _center_help_row(
        draw,
        help2_y,
        [("S", "Firmware Setup"), ("B", "Blank Entry")],
        font_help,
        brand_rgb,
        fg_rgb,
        w,
    )

    # --- Centered tree (current Limine + limine-snapper-sync naming) ---
    lines: list[tuple[str, bool]] = [
        ("[-] Omarchy", False),
        ("  -> linux", False),
        ("  [-] Snapshots", False),
        ("    [+] 5 | 2026-09-15 03:27:20", False),
        ("    [+] 4 | 2026-09-15 03:27:06", True),
        ("    [+] 3 | 2026-09-15 03:26:43", False),
        ("    [+] 2 | 2026-09-15 03:26:25", False),
        ("    [+] 1 | 2026-09-15 03:23:26", False),
    ]
    line_widths = [_text_size(draw, text, font_menu)[0] for text, _ in lines]
    tree_w = max(line_widths)
    tree_x = (w - tree_w) // 2

    line_h = 32
    tree_h = line_h * len(lines)
    content_top = help2_y + 48
    content_bottom = h - 64
    tree_y = content_top + max(0, (content_bottom - content_top - tree_h) // 2)

    for index, (text, selected) in enumerate(lines):
        y = tree_y + index * line_h
        tw, th = _text_size(draw, text, font_menu)
        if selected:
            pad_x, pad_y = 6, 3
            box = (
                tree_x - pad_x,
                y - pad_y,
                tree_x + tw + pad_x,
                y + th + pad_y,
            )
            draw.rectangle(box, fill=sel_bg_rgb)
            draw.text((tree_x, y), text, font=font_menu, fill=sel_fg_rgb)
        else:
            draw.text((tree_x, y), text, font=font_menu, fill=fg_rgb)

    # Version stamp — bottom-center (Omarchy package version on current Limine).
    ver_w, _ = _text_size(draw, ver, font_ver)
    draw.text(((w - ver_w) // 2, h - 48), ver, font=font_ver, fill=version_rgb)

    dest.parent.mkdir(parents=True, exist_ok=True)
    img.save(dest, format="PNG", optimize=True)
    return dest


def preview_path(slug: str) -> Path:
    return paths()["cache"] / "previews" / f"{slugify(slug)}.png"


def generate_preview(slug: str, branding: str | None = None) -> Path:
    palette = palette_from_theme(slug)
    return render_mockup(palette, preview_path(slug), branding=branding or "Omarchy Bootloader")


def bust_image_picker_cache(preview_root: Path) -> None:
    """Invalidate omarchy-menu-images rows/thumbnails for our preview dir."""
    try:
        os.utime(preview_root, None)
    except OSError:
        pass

    cache_dir = Path(
        os.environ.get(
            "OMABOOT_IMAGE_SELECTOR_CACHE",
            home() / ".cache/omarchy/image-selector",
        )
    )
    if not cache_dir.is_dir():
        return

    needle = str(preview_root.resolve())
    for path in cache_dir.iterdir():
        name = path.name
        if not (
            name.endswith(".rows")
            or name.endswith(".signature")
            or name.endswith(".fast-signature")
            or name.endswith(".rows.lock")
        ):
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        if needle in text or str(preview_root) in text:
            path.unlink(missing_ok=True)

    index = cache_dir / "index.tsv"
    if index.is_file():
        try:
            lines = index.read_text(encoding="utf-8", errors="ignore").splitlines()
        except OSError:
            lines = []
        kept: list[str] = []
        for line in lines:
            parts = line.split("\t")
            if parts and (needle in parts[0] or str(preview_root) in parts[0]):
                if len(parts) >= 3:
                    (cache_dir / f"{parts[2]}.jpg").unlink(missing_ok=True)
                    (cache_dir / f"{parts[2]}.jpg.lock").unlink(missing_ok=True)
                continue
            kept.append(line)
        try:
            atomic_write(index, ("\n".join(kept) + ("\n" if kept else "")))
        except OSError:
            pass


def generate_all_previews(branding: str | None = None) -> list[Path]:
    out: list[Path] = []
    preview_root = paths()["cache"] / "previews"
    preview_root.mkdir(parents=True, exist_ok=True)
    wanted = set(list_theme_slugs())
    for existing in preview_root.glob("*.png"):
        if existing.stem not in wanted:
            existing.unlink(missing_ok=True)
    label = branding or "Omarchy Bootloader"
    for slug in sorted(wanted):
        out.append(generate_preview(slug, branding=label))
    bust_image_picker_cache(preview_root)
    return out


def set_theme(slug: str, *, quiet: bool = False, dry_run: bool = False) -> int:
    slug = slugify(slug)
    if theme_dir(slug) is None:
        note(f"theme not found: {slug}")
        return 1

    palette = palette_from_theme(slug)
    existing = read_limine_conf()
    before_entries = [ln for ln in existing.splitlines() if ENTRY_LINE_RE.match(ln)]
    patched = patch_limine_conf(existing, palette)
    after_entries = [ln for ln in patched.splitlines() if ENTRY_LINE_RE.match(ln)]
    if before_entries != after_entries:
        note("refusing to write: boot entry lines would change")
        return 1
    if BLOCK_START not in patched or BLOCK_END not in patched:
        note("refusing to write: managed block missing after patch")
        return 1

    if dry_run:
        sys.stdout.write(patched)
        return 0

    write_limine_conf(patched)

    state = paths()["state"]
    state.mkdir(parents=True, exist_ok=True)
    atomic_write(state / "current", slug + "\n")
    atomic_write(state / "last-block.conf", render_block(palette))

    if not quiet:
        note(f"limine.conf ← {pretty_name(slug)} ({limine_conf_path()})")
        note("boot entries and cmdline left untouched; reboot to see the palette")
    return 0


def remove_marked(content: str, start: str, end: str) -> str:
    pattern = re.compile(re.escape(start) + r".*?" + re.escape(end) + r"\n?", re.S)
    return pattern.sub("", content)


def menu_action() -> str:
    switcher = plugin_dir() / "bin" / "omaboot-switcher"
    setter = plugin_dir() / "bin" / "omaboot-set"
    # Same privilege pattern as Style → Unlock: picker first, then a floating
    # terminal so sudo can prompt for a password.
    return (
        f'theme="$({switcher})"; '
        f'[[ -n $theme ]] && omarchy-launch-floating-terminal-with-presentation '
        f'"{setter} $(printf %q "$theme")"'
    )


def install_menu_entry() -> None:
    path = paths()["menu"]
    content = path.read_text(encoding="utf-8") if path.is_file() else "{\n}\n"
    content = remove_marked(content, MENU_START, MENU_END)
    entries = [
        (
            "style.boot",
            {
                "icon": "󰣆",
                "label": "Boot Themes",
                "aliases": ["boot", "limine", "bootloader"],
                "description": "Preview Omarchy palettes on a Limine mockup and patch /boot/limine.conf colours (sudo)",
                "action": menu_action(),
            },
        )
    ]
    brace = content.find("{")
    if brace < 0:
        raise RuntimeError(f"menu config has no root object: {path}")
    body = [MENU_START]
    for key, value in entries:
        body.append(f"  {json.dumps(key)}: {json.dumps(value, ensure_ascii=False)},")
    body.append(MENU_END)
    insertion = "\n".join(body) + "\n"
    atomic_write(path, content[: brace + 1] + "\n" + insertion + content[brace + 1 :])


def uninstall_menu_entry() -> None:
    path = paths()["menu"]
    if not path.is_file():
        return
    content = path.read_text(encoding="utf-8")
    if MENU_START in content:
        atomic_write(path, remove_marked(content, MENU_START, MENU_END))


def cmd_list(_: argparse.Namespace) -> int:
    for slug in list_theme_slugs():
        print(slug)
    return 0


def cmd_current(_: argparse.Namespace) -> int:
    slug = current_omaboot_slug()
    if not slug:
        return 1
    print(slug)
    return 0


def cmd_preview(args: argparse.Namespace) -> int:
    branding = None
    try:
        branding = branding_label(read_limine_conf())
    except Exception:
        branding = "Omarchy Bootloader"

    if args.theme:
        if theme_dir(args.theme) is None:
            note(f"theme not found: {args.theme}")
            return 1
        path = generate_preview(args.theme, branding=branding)
        print(path)
        return 0
    written = generate_all_previews(branding=branding)
    print(len(written))
    return 0


def cmd_set(args: argparse.Namespace) -> int:
    return set_theme(args.theme, quiet=args.quiet, dry_run=args.dry_run)


def cmd_show(args: argparse.Namespace) -> int:
    slug = slugify(args.theme)
    if theme_dir(slug) is None:
        note(f"theme not found: {slug}")
        return 1
    palette = palette_from_theme(slug)
    sys.stdout.write(render_block(palette))
    return 0


def cmd_switcher(_: argparse.Namespace) -> int:
    branding = "Omarchy Bootloader"
    try:
        branding = branding_label(read_limine_conf())
    except Exception:
        pass
    generate_all_previews(branding=branding)
    preview_dir = paths()["cache"] / "previews"
    current = current_omaboot_slug() or current_omarchy_slug()
    selected = ""
    if current and (preview_dir / f"{current}.png").is_file():
        selected = str(preview_dir / f"{current}.png")

    cmd = [
        "omarchy-menu-images",
        "--print-name",
        "--show-labels",
        "--filterable",
    ]
    if selected:
        cmd.extend(["--selected", selected])
    cmd.append(str(preview_dir))

    try:
        result = subprocess.run(cmd, check=False, capture_output=True, text=True)
    except FileNotFoundError:
        note("omarchy-menu-images not found")
        return 1

    choice = (result.stdout or "").strip()
    if result.returncode != 0 and not choice:
        return result.returncode or 1
    if choice:
        print(choice)
    return 0


def cmd_install_menu(_: argparse.Namespace) -> int:
    install_menu_entry()
    note(f"menu entry → {paths()['menu']}")
    return 0


def cmd_uninstall_menu(_: argparse.Namespace) -> int:
    uninstall_menu_entry()
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="omaboot", description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("list", help="List Omarchy theme slugs with colors.toml").set_defaults(func=cmd_list)
    sub.add_parser("current", help="Print the last applied omaboot theme slug").set_defaults(func=cmd_current)

    preview = sub.add_parser("preview", help="Render Limine mockup PNG(s)")
    preview.add_argument("theme", nargs="?", help="Theme slug; omit for all")
    preview.set_defaults(func=cmd_preview)

    show = sub.add_parser("show", help="Print the managed limine colour block for a theme")
    show.add_argument("theme", help="Theme slug")
    show.set_defaults(func=cmd_show)

    setter = sub.add_parser("set", help="Patch limine.conf with a theme palette (sudo)")
    setter.add_argument("theme", help="Theme slug")
    setter.add_argument("--quiet", action="store_true")
    setter.add_argument("--dry-run", action="store_true", help="Print patched conf to stdout")
    setter.set_defaults(func=cmd_set)

    sub.add_parser("switcher", help="Open image picker; print chosen slug").set_defaults(func=cmd_switcher)
    sub.add_parser("install-menu", help="Add Style → Boot Themes").set_defaults(func=cmd_install_menu)
    sub.add_parser("uninstall-menu", help="Remove Style → Boot Themes").set_defaults(func=cmd_uninstall_menu)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return int(args.func(args))
    except BrokenPipeError:
        return 0
    except Exception as exc:  # noqa: BLE001 — CLI surface
        note(str(exc))
        return 1


if __name__ == "__main__":
    sys.exit(main())

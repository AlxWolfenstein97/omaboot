# OmaBoot

**Omarchy themes your desktop. OmaBoot carries the same palette into the Limine
bootloader — mockup previews in the Style menu, then a managed colour block in
`/boot/limine.conf`.**

![OmaBoot on Hackerman — Limine mockup wearing the Omarchy palette](preview.png)

Stock Omarchy paints Hyprland, the terminal, and your GTK apps. The boot menu
keeps the install-day Tokyo Night hex. Your desktop wears Hackerman neon; the
firmware menu still looks like 2024.

OmaBoot closes that gap the same way Style → Unlock works for Plymouth: a
labelled image picker, one mockup per installed theme, and an apply step that
asks for sudo in a floating terminal. Boot is not user-land, so this is
**not** tied to `omarchy theme set`.

## Goals (and honest limits)

These Style plugins extend Omarchy’s theme system **without requiring theme
authors — or you — to ship anything extra**. Official themes, your forks, and
third-party installs all work as long as they have a `colors.toml`. That
“every theme” contract is intentional: once the desktop can follow farther,
making *another* theme is more worth it. Longer origin / stop-line:
[Chroma](https://github.com/AlxWolfenstein97/chroma).

| Goal | What that means here |
|------|----------------------|
| Zero extra assets | No per-theme Limine art. Colours come from `colors.toml` alone. |
| Extreme compatibility | Stock + user + foreign themes all appear in the picker automatically. |
| True Theme Vibe | Mockups track real Limine chrome + your theme’s hex — **much closer**, if not identical, to what those colours look like on bare metal. Still **not** a framebuffer capture. |
| Carousel-safe | Mockups are 1536×864 (menu-images thumbnail size) with ~8% side / ~48px vertical safe margins so the 768×475 tile crop does not shave the subject. |
| Slow pickers are OK | Warming every theme PNG takes a moment; that is the cost of generating previews instead of bundling assets. |

We are **not** putting WYSIWYG screenshots in themes. Themes stay palette-only;
OmaBoot draws the chrome itself. True pixel-identical boot art would need QEMU /
reboot loops or per-theme bitmaps — that narrows the scope we refuse to narrow.
Plymouth Unlock looks “real” because Omarchy already ships unlock chrome; boot
does not, so we draw from the palette against a single Limine layout.

### Why a picker (and no theme-set hook)?

Boot needs sudo and only shows up after reboot — not something to rewrite on
every `omarchy theme set`. The Style carousel is still the point: preview how
Limine would wear **every** installed theme’s palette without rebooting twenty
times. Same “one surface, many themes, faster than manual” idea as OmaOBS /
OmaCursor / OmaVT.

## What you get

- **Style → Boot Themes** in the Omarchy menu — same carousel picker as Unlock /
  Theme / Background.
- **Live theme discovery** — every Omarchy theme with a `colors.toml` under
  `~/.config/omarchy/themes` or `$OMARCHY_PATH/themes`.
- **Mockups** — Limine-like chrome (corner help keys, centered branding,
  snapshot tree, inverse selection) coloured from that theme’s palette.
- **Safe patch** — one `### omaboot:start` … `### omaboot:end` block in
  `/boot/limine.conf`. Appended once if missing; replaced as a whole when you
  change themes. Boot entries, timeout, branding *text*, and any custom cmdline
  stay untouched — the patcher never rewrites non-colour lines.
- **No theme-set hook** — applying needs a password; pick when you mean it.

## Mockups: True Theme Vibe (not theme-bundled WYSIWYG)

Limine has no headless renderer, and we will not ask theme authors to ship boot
screenshots. Instead the drawer in `lib/omaboot.py` paints a **single** Limine
layout once, then recolours it from each theme’s `colors.toml`.

**How that layout was locked in:** Omarchy’s stock Limine colours *are* Tokyo
Night. The [System snapshots](https://omarchy.org/manual/system-snapshots/)
page of the [Official Omarchy Manual](https://omarchy.org/manual/) shows a
clean Limine boot screen in that palette (help keys, centered branding, snapshot
tree, inverse selection, version stamp). That shot was the layout reference —
not something we redistribute, and not something themes carry. Match the chrome
to that Tokyo Night example, then every other installed theme inherits the same
silhouette with *its* hex. One clear colour example → the rest fall into place.

Stock Limine vibe (Tokyo Night mockup — compare to the Manual boot screenshot):

![OmaBoot Tokyo Night mockup — stock Limine layout + palette](preview-tokyo-night.png)

Hero above is the same chrome on **Hackerman**, so the picker story is obvious:
same Limine, different theme colours. Not every Style plugin will land this
close; this is the start of that bar.

Carousel crop stays honest: content is centered inside safe margins so
`omarchy-menu-images` does not shave the subject.

## Install

```sh
omarchy plugin add https://github.com/AlxWolfenstein97/omaboot.git --enable
```

That clones into `~/.config/omarchy/plugins/io.github.alxwolfenstein97.omaboot`.
Or from a checkout:

```sh
~/.config/omarchy/plugins/io.github.alxwolfenstein97.omaboot/install.sh
omarchy plugin enable io.github.alxwolfenstein97.omaboot
```

**Needs:** Limine (`/boot/limine.conf`), Omarchy’s image picker, Python 3 with
Pillow (`python-pillow` on Arch), and sudo for apply.

## How it works

1. `bin/omaboot-switcher` renders PNG mockups into
   `~/.cache/omarchy/omaboot/previews/`, then opens `omarchy-menu-images`.
2. On selection, Style launches a floating terminal running `omaboot-set`
   (same privilege pattern as Unlock), which prompts for sudo and patches
   `/boot/limine.conf`.
3. Colour keys (`term_*`, `backdrop`, branding/help colours) live inside the
   managed block. Everything else in the file is preserved.

CLI:

```sh
omaboot list
omaboot preview              # warm all mockups
omaboot switcher             # picker → prints slug
omaboot show tokyo-night     # print managed block
omaboot set tokyo-night      # patch limine.conf (sudo)
omaboot set tokyo-night --dry-run
omaboot current
```

## Remove

```sh
~/.config/omarchy/plugins/io.github.alxwolfenstein97.omaboot/uninstall.sh
omarchy plugin disable io.github.alxwolfenstein97.omaboot
omarchy plugin remove io.github.alxwolfenstein97.omaboot
```

Uninstall removes the menu row and cache/state. It does **not** rewrite
`limine.conf` — your last applied palette stays until you change it.

## Limits, honestly

- Limine only reads the conf at boot — reboot to see the new palette on bare
  metal.
- There is no separate Plymouth-style **Default** tile: Omarchy’s stock Limine
  palette is Tokyo Night in practice, so pick **Tokyo Night** for install-day
  colours.
- `omarchy refresh limine` replaces the whole conf from Omarchy defaults; run
  Boot Themes again afterwards if you still want a themed palette.

## Check

```sh
bash ~/.config/omarchy/plugins/io.github.alxwolfenstein97.omaboot/check.sh
```

## Credits

- **Layout reference:** Limine boot screenshot on
  [System snapshots](https://omarchy.org/manual/system-snapshots/) in the
  [Official Omarchy Manual](https://omarchy.org/manual/) (Tokyo Night / stock
  Omarchy Limine). Used as a layout + vibe target only — not redistributed.
- Hero mockup: official **Hackerman** theme (the loudest stock neon Omarchy
  ships). Compare mockup: stock **Tokyo Night**.
- Sibling plugins: [OmaOBS](https://github.com/AlxWolfenstein97/omaobs),
  [OmaVT](https://github.com/AlxWolfenstein97/omavt),
  [OmaTTY](https://github.com/AlxWolfenstein97/omatty),
  [OmaCursor](https://github.com/AlxWolfenstein97/omacursor),
  [Chroma](https://github.com/AlxWolfenstein97/chroma).
- [Omarchy](https://omarchy.org/) — theme pipeline, Style menu image picker,
  and Limine defaults this plugin patches carefully.

## License

MIT — see [LICENSE](LICENSE).

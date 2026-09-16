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
| True Theme Vibe | Mockups track **current** Limine chrome + your theme’s hex — **much closer**, if not identical, to what those colours look like on bare metal. Still **not** a framebuffer capture. |
| Carousel-safe | Mockups are 1536×864 (menu-images thumbnail size). Current Limine is dead-centered, so the 768×475 tile crop mostly shaves empty sides. |
| Snappy pickers | Mockups warm in parallel across CPU cores — opens like Omarchy’s stock art carousels. |

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
- **Mockups** — current Limine chrome (centered branding + help, snapshot tree
  with `N | timestamp`, inverse selection, version footer) coloured from that
  theme’s palette.
- **Safe patch** — one `### omaboot:start` … `### omaboot:end` block in
  `/boot/limine.conf`. Appended once if missing; replaced as a whole when you
  change themes. Boot entries, timeout, branding *text*, and any custom cmdline
  stay untouched — the patcher never rewrites non-colour lines.
- **No theme-set hook** — applying needs a password; pick when you mean it.

## Mockups: True Theme Vibe (not theme-bundled WYSIWYG)

Limine has no headless renderer, and we will not ask theme authors to ship boot
screenshots. Instead the drawer in `lib/omaboot.py` paints a **single** Limine
layout once, then recolours it from each theme’s `colors.toml`. At this point
the Tokyo Night mockup is close enough that asking for a framebuffer feels like
a joke — still not pixel-identical UEFI output, but the *vibe* is there.

**How it was done**

1. Grab a clean **current** Omarchy Limine screen in QEMU (no capture card) on
   stock Tokyo Night — five joke update checks so Snapshots had rows, second
   entry highlighted like the Manual used to.
2. Trace that chrome in Pillow: centered branding, help under the title,
   `-> linux` / Snapshots tree, `[+] N | timestamp` rows, inverse selection,
   package version footer. Dead-centered so the Style carousel crop barely
   matters.
3. Recolour the same silhouette from every installed theme’s `colors.toml`.
   Themes stay palette-only; the plugin owns the art.

The [System snapshots](https://omarchy.org/manual/system-snapshots/) page of the
[Official Omarchy Manual](https://omarchy.org/manual/) still shows a Tokyo Night
boot screen, but that shot is **dated** (2.x / early 3.x corner-help layout). We
matched it first; this release tracks live Limine 12 / Omarchy 4 chrome instead.

**Compare — real QEMU capture vs generated mockup (same theme):**

| Real Limine (QEMU, Tokyo Night) | OmaBoot mockup (Tokyo Night) |
| --- | --- |
| ![Real Omarchy Limine on Tokyo Night — QEMU reference](reference-limine-tokyo-night.png) | ![OmaBoot Tokyo Night mockup — same layout, drawn from colors.toml](preview-tokyo-night.png) |

Hero at the top is the same chrome on **Hackerman**, so the picker story is
obvious: same Limine, different theme colours. Not every Style plugin will land
this close; this is the start of that bar.

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

**Needs (installer pulls these if missing):**

| Package | Why |
|---------|-----|
| `python-pillow` | Draws the Style → Boot Themes mockup PNGs. Without it the carousel is empty on first open. |

Also needs Limine (`/boot/limine.conf`), Omarchy’s image picker, and sudo for
apply. `install.sh` installs Pillow **before** warming mockups.

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

## Disable vs remove

| Action | What happens |
|--------|----------------|
| `omarchy plugin disable …` | Shell service stops. No theme-set hook here — last limine colour block stays until you uninstall or clear it. |
| `./uninstall.sh` then disable / remove | Menu, cache/state, and the `### omaboot` colour block in `limine.conf` gone (sudo). Boot entries / cmdline untouched. Shared packages stay. |
| `omarchy pkg drop python-pillow` | Optional. Only if nothing else on the machine needs Pillow. |

**Full wipe** — copy-paste to remove plugin wiring *and* the shared package this
installer may have pulled (skip the `pkg drop` line if something else still
needs Pillow):

```sh
~/.config/omarchy/plugins/io.github.alxwolfenstein97.omaboot/uninstall.sh
omarchy plugin disable io.github.alxwolfenstein97.omaboot
omarchy plugin remove io.github.alxwolfenstein97.omaboot
omarchy pkg drop python-pillow
```

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

- **Layout reference:** [`reference-limine-tokyo-night.png`](reference-limine-tokyo-night.png)
  — QEMU capture of current Omarchy Limine on stock Tokyo Night (centered chrome,
  snapshot `N | timestamp` rows, `4.0.3-1` footer). Compare to
  [`preview-tokyo-night.png`](preview-tokyo-night.png). The
  [System snapshots](https://omarchy.org/manual/system-snapshots/) Manual shot
  was the earlier (2.x / early 3.x) vibe target only.
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

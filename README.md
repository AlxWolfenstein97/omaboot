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

## What you get

- **Style → Boot Themes** in the Omarchy menu — same carousel picker as Unlock /
  Theme / Background.
- **Live theme discovery** — every Omarchy theme with a `colors.toml` under
  `~/.config/omarchy/themes` or `$OMARCHY_PATH/themes`.
- **Mockups** — a simplified Limine frame (branding, help, menu rows, 16-colour
  strip) coloured from that theme’s palette.
- **Safe patch** — one `### omaboot:start` … `### omaboot:end` block in
  `/boot/limine.conf`. Appended once if missing; replaced as a whole when you
  change themes. Boot entries, timeout, branding *text*, and any custom cmdline
  stay untouched — the patcher never rewrites non-colour lines.
- **No theme-set hook** — applying needs a password; pick when you mean it.

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
- Mockups are illustrative, not a pixel-perfect Limine framebuffer.
- `omarchy refresh limine` replaces the whole conf from Omarchy defaults; run
  Boot Themes again afterwards if you still want a themed palette.

## Check

```sh
bash ~/.config/omarchy/plugins/io.github.alxwolfenstein97.omaboot/check.sh
```

## Credits

- Hero mockup: official **Hackerman** theme (the loudest stock neon Omarchy
  ships).
- Sibling plugin: [OmaOBS](https://github.com/AlxWolfenstein97/omaobs) — same
  Style-menu mockup pipeline for OBS Studio.
- [Omarchy](https://omarchy.org/) — theme pipeline, Style menu image picker,
  and Limine defaults this plugin patches carefully.

## License

MIT — see [LICENSE](LICENSE).

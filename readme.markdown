# quicklook-nfo

> A modern, configurable Quicklook plugin for NFO/DIZ files

- Faithful CP437 decoding, so box-drawing and block art render as intended
- Four bundled DOS text-mode bitmap fonts, or any fixed-pitch system font
- Integer zoom (1×, 2×, 3×) that keeps pixel glyphs crisp
- Light and dark color pairs, following the system appearance or pinned
- SAUCE metadata parsing

## Settings

Open `/Applications/Quicklook NFO.app` — it is a single "Quicklook NFO Settings"
window, and every edit saves immediately; there is no OK/Apply.

![Screenshot](https://github.com/idleberg/quicklook-nfo/blob/main/.github/resources/settings.png)

- **Font** — four bundled DOS text-mode fonts, then any fixed-pitch family
  installed on the system. Only the bundled ones are guaranteed to line up;
  picking a system font shows a warning saying so.
  - **Px437 IBM VGA 8x16** — default; the 80×25 cell most `.nfo` art targets.
  - **Px437 IBM VGA 9x16** — the true VGA cell, one pixel wider per column.
  - **Px437 IBM VGA 9x8** — 80×50 mode.
  - **Px437 IBM EGA 8x14** — EGA-era art.
- **Size** — 1×, 2× or 3×. Whole multiples of the font's own cell height, so
  pixel glyphs never land between screen pixels.
- **Light** / **Dark** — a text/background pair each, edited independently.
  Black on silver and silver on black by default.
- **Appearance** — System, Light or Dark, deciding which pair a preview uses.
  System follows whatever is showing the preview.
- **Reset** — back to the default font, size and colors.

## License

This work is licensed under the [Apache License, Version 2.0](LICENSE-APACHE) or [The MIT License](LICENSE-MIT). The included, unmodified fonts are taken from [The Ultimate Oldschool PC Font Pack](https://int10h.org/oldschool-pc-fonts/) and are licensed under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).

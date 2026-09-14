# diznfo

> A modern, configurable viewer and Quicklook plugin for NFO/DIZ files

**Features**

- Faithful CP437 decoding, so box-drawing and block art render as intended
- Four bundled DOS text-mode bitmap fonts, or any fixed-pitch system font
- Zoom in powers of two (0.25× to 4×) that keeps pixel glyphs crisp
- Light and dark color pairs, following the system appearance or pinned
- SAUCE metadata parsing
- ANSI art (`.ans`, or `.nfo` / `.diz` with escape codes) in the VGA palette,
  including iCE colors
- Opens `.nfo` / `.diz` read-only, with an unlock button for editing; edits
  are written back as CP437 with the SAUCE record intact

![Screenshot](https://github.com/idleberg/diznfo/blob/main/.github/resources/quicklook.png)

## Installation

```sh
brew install idleberg/asahi/diznfo
```

## Usage

Open an `.nfo` or `.diz` in Diznfo (double-click, or drop it on the app). The
document opens read-only; the lock in the toolbar allows editing, and while
editing anything past the file's standard width is shaded, so overrunning it is
visible. ANSI art has no lock: it is always read-only and ignores the color
settings, since its colors are part of the artwork. `⌘+` / `⌘-` / `⌘0` zoom, and those are the same setting the Settings
window and the QuickLook preview use.

## Settings

`⌘,` opens Settings. Every edit saves immediately; there is no OK/Apply, and
the QuickLook preview picks the change up on its next render.

![Screenshot](https://github.com/idleberg/diznfo/blob/main/.github/resources/settings.png)

- **Font** — four bundled DOS text-mode fonts, then any fixed-pitch family
  installed on the system. Only the bundled ones are guaranteed to line up;
  picking a system font shows a warning saying so.
  - **Px437 IBM VGA 8x16** — default; the 80×25 cell most `.nfo` art targets.
  - **Px437 IBM VGA 9x16** — the true VGA cell, one pixel wider per column.
  - **Px437 IBM VGA 9x8** — 80×50 mode.
  - **Px437 IBM EGA 8x14** — EGA-era art.
- **Size** — 0.25× to 4×. Powers of two of the font's own cell height, so pixel
  glyphs never land between screen pixels in either direction.
- **Light** / **Dark** — a text/background pair each, edited independently.
  Black on silver and silver on black by default.
- **Appearance** — System, Light or Dark, deciding which pair a preview uses.
  System follows whatever is showing the preview.
- **Reset** — back to the default font, size and colors.

## License

This work is licensed under the [Apache License, Version 2.0](LICENSE-APACHE) or [The MIT License](LICENSE-MIT). The included, unmodified fonts are taken from [The Ultimate Oldschool PC Font Pack](https://int10h.org/oldschool-pc-fonts/) and are licensed under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).

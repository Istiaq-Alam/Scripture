# DESIGN.md — Scripture site

Surface: landing page for the five terminal installers in this repository.
Mode: Persuade. One audience (developers setting up a machine), one primary action
(browse the scripts), one offer (readable bash installers).

## Direction

Night shift instrument panel. The product is a terminal wizard, so the page borrows its
world: graphite surfaces, one amber phosphor accent, monospace only where a command or a
hash is shown. The richness sits in the terminal preview, not in the chrome.

Signature detail: the amber block cursor, used in the wordmark, the hero terminal and the
favicon. Keycaps appear only where the page explains arrow key controls.

## Color

| Token | Value | Use |
|---|---|---|
| `--bg` | `#131209` | Page background |
| `--surface` | `#181818` | Terminal, script list, panel, CTA |
| `--raised` | `#1F1F1F` | Code blocks, chips, keycaps |
| `--line` | `rgba(242,239,228,.10)` | Hairline dividers and borders |
| `--line-strong` | `rgba(242,239,228,.18)` | Button and control borders |
| `--text` | `#F2EFE4` | Primary text |
| `--text-2` | `#B7B1A1` | Body and secondary text |
| `--muted` | `#918B7D` | Metadata, captions |
| `--amber` | `#FFB000` | Primary button, focus ring, active step, selection |
| `--amber-ink` | `#1A1300` | Text on amber |
| `--ok` | `#8FB89A` | Completed check marks only |

No gradients on surfaces or text. No glows or colored shadows. Depth comes from surface
steps, hairlines and one neutral shadow on the floating terminal.

## Type

Families: Geist for all interface text, Geist Mono for commands, hashes, keycaps and
terminal output only. Weights 400, 500, 600. No italics, no 700 to 900.

| Style | Size / line height |
|---|---|
| Heading 1 | 60 / 60, mobile 36 / 40 |
| Heading 2 | 36 / 40, mobile 30 / 36 |
| Heading 3 | 24 / 32 |
| Title 2 | 18 / 28 |
| Body 3 | 16 / 24 |
| Body 6 | 14 / 20 |
| Caption 4 | 12 / 16 |

Heading tracking stops at -0.03em. Small text keeps zero or positive tracking.
Headings use `text-wrap: balance`, body uses `text-wrap: pretty`.

## Spacing

4, 8, 12, 16, 20, 24, 28, 32, 40, 48, 64, 80, 96, 128. Section rhythm is 96px desktop and
64px mobile. Wrap is 1120px with 24px gutters, 20px under 760px.

## Radius

Controls 8, cards and panels 16, chips 6, keycaps 4. Nested elements step down with their
padding.

## Platform switcher

The scripts section shows one platform at a time: Linux, macOS, Windows. It reuses the
filter button shape, the amber active state and 8px gaps. Only the selected platform's
command, metadata, download and source link are visible; the choice is kept in `?os=`.
On a detail page the same control becomes three small page tabs, with the current one
marked in amber.

## Motion

One curve: `cubic-bezier(.22,1,.36,1)`. Hover and press 150ms, entrances 700ms, menu and
accordion 220ms. Hero elements enter once with a 70ms stagger. Sections rise 32px once on
scroll. The tagline lights one word at a time. `prefers-reduced-motion` removes all of it.

The hero terminal replays the setup-skills wizard: the command types in, the design menu
moves, the skill steps print with a braille spinner, and the run ends on INSTALL REPORT.
It loops while the card is on screen and stops when it scrolls away, and it follows the
platform switch: bash under `$` for Linux and macOS, `irm` and `.\setup-skills.ps1` under
`PS>` with a `pwsh` label for Windows. A 24px pause control sits in the title bar (44px on
touch). The text is decorative and `aria-hidden`; a static summary replaces it for screen
readers, `prefers-reduced-motion` users and no-JS visits. Reduced-motion visitors get the
same control as an explicit Play action, so the animation is opt-in rather than automatic.

## Deviations from the skill defaults, on purpose

- The hero heading is solid `--text`, not a white to gray gradient, because the Unslop pass
  bans gradient text.
- The nav uses a quiet translucent bar across the top instead of a centered floating pill,
  so the page width stays aligned to the 1120px wrap.
- Backgrounds use only the allowed dark surface steps from the landing page skill.

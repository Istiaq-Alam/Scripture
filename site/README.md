# Scripture site

Static download page for the fifteen installers in this repository: five jobs, each in a
Linux, macOS and Windows version. One detail page per script and platform with its full
source, line numbers and line anchors. Plain HTML, CSS and JavaScript on a small
dependency free Node server.

## Run locally

```bash
cd site
npm install
npm start
```

`npm start` copies every script from `linux/`, `mac/` and `windows/` into
`public/downloads/<platform>/`, hashes each one, writes
`public/downloads/manifest.json`, generates `public/scripts/<slug>-<os>.html` for each
variant, then serves the site at <http://localhost:3000>.

## Build and deploy

```bash
npm run build
```

Deploy `site/public` to any static host. Every path is relative, so the build works at a
domain root or under a subdirectory.

### GitHub Pages

The workflow in `.github/workflows/pages.yml` builds the site and publishes `site/public`
as a Pages artifact on every push to `main`.

1. Push the repository to GitHub.
2. Open **Settings → Pages** and set **Source** to **GitHub Actions**.
3. Push to `main` or run the workflow manually.
4. The site lands at `https://<user>.github.io/<repo>/`, or at the root of a
   `<user>.github.io` repository.

### Vercel

Set the project root to `site`, the build command to `npm run build` and the output
directory to `public`.

### Content types

`server.mjs` serves `.sh` and `.ps1` files as attachments with a plain text type. Pages
serves them as plain files; the `download` attribute and `curl`/`irm` still work.

## Pages

| Path | Contents |
|---|---|
| `/` | Hero, platform switcher, script list, search and privilege filters, safety, FAQ |
| `/scripts/setup-skills-linux.html` etc. | One page per script and platform: checksum, source viewer, platform tabs |
| `/scripts/laravel-windows.html` | Same page shape for the PowerShell variant |

Platform is detected from the browser and can be forced with `?os=linux`, `?os=mac` or
`?os=windows`. Search and privilege filters are written to the URL too
(`?q=laravel&sudo=no&os=mac`), so a filtered view can be shared. Source lines are
addressable: `/scripts/laravel-mac.html#L120`.

Without JavaScript the Linux variants stay visible and every platform is reachable from
the detail pages, which link to each other.

## Data and generation

`scripts/data.mjs` is the single source of truth:

```js
{
  slug: "laravel",
  name: "Laravel",
  summary: "…",
  variants: {
    linux:   { source: "linux/setup-laravel.sh",   file: "linux/setup-laravel.sh",   … },
    mac:     { source: "mac/setup-laravel.sh",     file: "mac/setup-laravel.sh",     … },
    windows: { source: "windows/setup-laravel.ps1", file: "windows/setup-laravel.ps1", … },
  },
}
```

`OSES` in the same file holds the labels, install templates and checksum commands. The
home page rows are still written into `public/index.html`, so keep them in step when you
add a script: five cards, three `.variant` blocks each, with `data-os`.

## SEO, sharing and icons

The site URL is defined once in `scripts/data.mjs` (`SITE.url`) and used for the
canonical link, `og:url` and absolute `og:image` URLs on every generated page.
`public/index.html` and the legal pages carry the same absolute URLs by hand, so update
them if the domain or repository path changes.

- `og.png` is generated from `scripts/og.html` at 1200x630 and referenced with absolute
  URLs, which is what social platforms need. A relative `og:image` resolves against the
  sharing site's guess and breaks.
- Icons live in `public/`: `favicon.ico` (16/32/48), `favicon-32x32.png`,
  `apple-touch-icon.png` (180) and `icon-192.png` / `icon-512.png`, generated from
  `favicon.svg`.
- `manifest.json` declares the app name, colors and the 32 to 512px icon set.

The meta description is kept at or below 160 characters; `scripts/checks.mjs` fails if it
grows past that or if a canonical, OG or icon tag goes missing.

## Checks

```bash
npm run shots            # screenshots at 1440, 820 and 390, plus OS views; overflow and console checks
npm run og               # regenerates public/og.png
node scripts/checks.mjs  # menu, clipboard, OS switch, search, filters, links, anchors, hashes
```

The browser checks need a local Chromium. They use `/usr/bin/chromium` unless `CHROME_PATH`
is set.

## Editing

- `scripts/data.mjs` is the single source of truth for names, summaries, requirements,
  footprints, privileges and flags of every platform variant.
- `scripts/pages.mjs` generates the fifteen detail pages; do not edit them by hand.
- Copy, terminal preview and page sections live in `public/index.html`.
- Design tokens are in `public/styles.css` and documented at `../DESIGN.md`. The platform
  switch reuses the filter button and amber active state.
- The social card is `scripts/og.html`, rendered by `scripts/og.mjs`.
- Adding a platform: add a folder, an `OSES` entry, a variant for every script in
  `data.mjs`, a button in the OS switch, and a `.variant` block per card.

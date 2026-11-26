# Scripture site

Static download page for the five installers in the repository root. Plain HTML, CSS and
JavaScript on a small dependency free Node server.

## Run locally

```bash
cd site
npm install
npm start
```

`npm start` copies the five scripts from the repo root into `public/downloads`, hashes each
one, writes `public/downloads/manifest.json`, then serves the site at
<http://localhost:3000>.

## Build and deploy

```bash
npm run build
```

Deploy `site/public` to any static host. On Vercel, set the project root to `site`, the build
command to `npm run build` and the output directory to `public`.

`server.mjs` serves shell scripts as `text/x-shellscript` with
`Content-Disposition: attachment`. A static host will serve them as plain files instead; the
`download` attribute on each link still saves them, and `curl` in the install command ignores
the header either way.

## Checks

```bash
npm run shots            # screenshots at 1440, 820 and 390, overflow and console checks
npm run og               # regenerates public/og.png
node scripts/checks.mjs  # menu, clipboard, links, download hashes, no-JS and 320px checks
```

The browser checks need a local Chromium. They use `/usr/bin/chromium` unless `CHROME_PATH`
is set.

## Editing

- Copy, script details and the terminal preview live in `public/index.html`.
- Design tokens are in `public/styles.css` and documented at `../DESIGN.md`.
- The social card is `scripts/og.html`, rendered by `scripts/og.mjs`.
- Adding a script: add it to `SCRIPTS` in `scripts/sync.mjs`, then add a row to the list in
  `public/index.html`.

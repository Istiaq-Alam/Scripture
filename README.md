# Scripture

**Your dev setup, in one script.**

Scripture is a small collection of readable bash installers plus a static site that
publishes them. Each script does one job end to end, prints what it changed, and can be
read in full before you run it. No hidden package manager, no daemon, no telemetry.

[![Deploy site to GitHub Pages](https://github.com/Istiaq-Alam/Scripture/actions/workflows/pages.yml/badge.svg)](https://github.com/Istiaq-Alam/Scripture/actions/workflows/pages.yml)

---

## The scripts

| Script | What it does | Needs | Touches |
|---|---|---|---|
| [`Setup-skills.sh`](Setup-skills.sh) | Installs five design skills, a `DESIGN.md` and the rules file your coding agent reads at the start of every session. Prints a report at the end, including what it skipped. | git, Node 18+, npx | `.claude/skills`, `.agents/skills`, `DESIGN.md`, `CLAUDE.md`, `AGENTS.md`, `.mcp.json`, `skill-instructions.md` |
| [`setup-laravel.sh`](setup-laravel.sh) | Guided Laravel install: picks a PHP that can run the current Laravel, provisions MySQL, MariaDB, PostgreSQL, SQLite or SQL Server, then creates the project, writes `.env`, migrates and builds assets. | PHP 8.2+, Composer, a database | A new project folder, its `.env`, system packages, a database |
| [`setup-freebuff-zsh.sh`](setup-freebuff-zsh.sh) | Verifies a Gemini API key against Google's OpenAI-compatible endpoint, installs the Freebuff CLI, and writes one marked block into `~/.zshrc`. Removes the old `.bashrc` block it used to write. | zsh, npm, a Gemini key | `~/.zshrc`, the global `freebuff` npm package |
| [`gitcli.sh`](gitcli.sh) | First push for a local project: checks git, writes a conservative `.gitignore`, stages what is safe to publish, commits and pushes. | git, curl, figlet, lolcat | `.gitignore`, a commit, your remote |
| [`ClaudeCode.sh`](ClaudeCode.sh) | Installs Ollama, picks a Gemma model that fits your RAM, adds Node.js and Claude Code, then writes the local `ANTHROPIC_*` endpoints to your shell config. Ends with a test prompt. | curl, sudo, Node.js if missing | Ollama, a Gemma model, Claude Code, six exports in `.zshrc` or `.bashrc` |

All five are interactive. Run them from the folder you want them to change, on Linux.

### Quick start

Download it, read it, then run it. Piping a script straight into `bash` skips the reading
step, which is the one thing this repo is trying to make easy.

```bash
curl -fsSLO https://raw.githubusercontent.com/Istiaq-Alam/Scripture/main/Setup-skills.sh
less Setup-skills.sh
bash Setup-skills.sh
```

### `Setup-skills.sh` flags

The script asks before doing anything optional; flags skip the question.

| Flag | Effect |
|---|---|
| `--brand <name>` | Pick a design system immediately, for example `linear` or `apple`. |
| `--list` | Print every available design and exit. |
| `--skip-design` | Install the skills only, without a `DESIGN.md`. |
| `--debug` | Show the full output of every command. |
| `--security` / `--no-security` | Force the Claude-Red offensive security skills on or off. |
| `--superpowers` / `--no-superpowers` | Force the Superpowers workflow skills on or off. |
| `--unslop` / `--no-unslop` | Force the Unslop design skill on or off. |

It installs Impeccable, the Taste skill, Vercel's Web Design Guidelines and the
landing page design skill, then mirrors them into both `.claude/skills` and
`.agents/skills` so Claude Code and other agents find the same files. An existing
`DESIGN.md` is kept as `DESIGN.md.bak`. Design systems come from
[voltagent/awesome-design-md](https://github.com/voltagent/awesome-design-md), previewable
at [getdesign.md](https://getdesign.md/).

### About `ClaudeCode.sh`

It points Claude Code at a local Ollama server instead of the hosted API by exporting the
`ANTHROPIC_BASE_URL` and related variables in your shell config. Nothing leaves the
machine, and the only key involved is a placeholder the local server accepts.

---

## The site

`site/` is a static download page for those five scripts: one detail page per script with
its full source, line numbers, line anchors and a SHA-256 checksum. Plain HTML, CSS and
JavaScript served by a dependency free Node server. No framework, no build tool.

```bash
cd site
npm install
npm start
```

`npm start` copies the five scripts into `public/downloads`, hashes each one, writes
`downloads/manifest.json`, regenerates `public/scripts/<slug>.html`, then serves
<http://localhost:3000>. The only dev dependency is `playwright-core`, used by the
screenshot check.

```bash
npm run build             # sync, hash and regenerate detail pages
npm run shots             # screenshots at 1440, 820 and 390 plus overflow and console checks
npm run og                # regenerate public/og.png
node scripts/checks.mjs   # menu, clipboard, search, filters, links, anchors, hashes
```

The browser checks need a local Chromium: they use `/usr/bin/chromium` unless `CHROME_PATH`
is set.

Deploy `site/public` to any static host. Every path is relative, so it works at a domain
root or under a subdirectory. The workflow in [`.github/workflows/pages.yml`](.github/workflows/pages.yml)
builds and publishes to GitHub Pages on every push to `main`; set **Settings → Pages →
Source** to **GitHub Actions** once.

Search and privilege filters are written to the URL (`?q=laravel&sudo=no`), and source
lines are addressable: `/scripts/laravel.html#L120`.

More detail lives in [`site/README.md`](site/README.md), including how to add a sixth
script.

---

## Repository layout

```text
.
├── Setup-skills.sh          design skills, DESIGN.md and agent rules
├── setup-laravel.sh         guided Laravel install
├── setup-freebuff-zsh.sh    Freebuff CLI and Gemini key in ~/.zshrc
├── gitcli.sh                first commit and push
├── ClaudeCode.sh            Ollama, Gemma and Claude Code
├── mysql-manual.md          MySQL and MariaDB CLI cheatsheet
├── terminal.html            standalone terminal style blog mockup
├── themes/                  design analyses of nine product sites
├── DESIGN.md                design system for the site, the source of truth
├── AGENTS.md                agent rules (CLAUDE.md is the same file)
├── skill-instructions.md    skills and workflow an agent reads each session
├── skills-lock.json         pinned skill sources and hashes
├── .mcp.json                Playwright MCP server
└── site/                    the static site
    ├── scripts/             data, page generator, sync, checks, screenshots, OG card
    ├── public/              index, styles, app, legal pages, generated output
    └── server.mjs           local static server
```

`themes/` holds written design analyses (Linear, Apple, Notion, Resend, Cal.com,
Intercom, SAP, Zapier, Mintlify). They informed `DESIGN.md` and are reference material,
not part of the build.

---

## Editing the site

- `DESIGN.md` owns color, type, spacing, radius and motion. The site follows it exactly;
  hex values and spacing steps are not invented inline.
- `site/scripts/data.mjs` is the single source of truth for names, summaries, requirements
  and flags. The home page rows are hand written in `public/index.html`, so keep the two
  in step.
- Detail pages are generated by `site/scripts/pages.mjs`. Do not edit them by hand.
- `AGENTS.md` and `skill-instructions.md` describe the review pipeline (design audit,
  accessibility checks, browser QA) that changes to the site are expected to pass.

---

## Notes

- Linux first. The installers use `apt`, `dnf`, `pacman` or `zypper` and assumptions about
  shell config files; macOS and Windows are untested.
- Several scripts will ask for `sudo`, change system packages or write to your shell
  config. Read the source before you run it.
- Some scripts reference external services and models by name (Ollama, Gemini, Claude
  Code, GitHub). Their terms and availability are theirs, not this repository's.
- No license file is included yet. Add one before reusing this code in your own project.

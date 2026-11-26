# Scripture

**Your dev setup, in one script.** For Linux, macOS and Windows.

Scripture is a small collection of readable setup scripts plus a static site that
publishes them. Every script does one job end to end, prints what it changed, and can be
read in full before you run it. No daemon, no telemetry, no package to trust.

[![Deploy site to GitHub Pages](https://github.com/Istiaq-Alam/Scripture/actions/workflows/pages.yml/badge.svg)](https://github.com/Istiaq-Alam/Scripture/actions/workflows/pages.yml)

---

## The scripts

Five jobs, one version per platform:

| Script | What it does |
|---|---|
| **Setup skills** | Installs five design skills, a `DESIGN.md` and the rules file your coding agent reads at the start of every session. Prints a report at the end, including what it skipped. |
| **Laravel** | Guided Laravel install: picks a PHP that can run the current Laravel, provisions MySQL, MariaDB, PostgreSQL or SQLite, creates the project, writes `.env`, migrates and builds assets. |
| **Freebuff** | Verifies a Gemini API key, installs the Freebuff CLI and writes one marked block into your shell profile. Replaces that block on later runs. |
| **GitHub helper** | First push for a local project: writes a conservative `.gitignore`, stages what is safe, commits and pushes. Creates a helper for later pushes. |
| **Claude Code on Ollama** | Installs Ollama, picks a Gemma model that fits your RAM, adds Node.js and Claude Code, then points the Anthropic endpoints at the local server. Ends with a test prompt. |

| Platform | Folder | Shell | Packages |
|---|---|---|---|
| Linux | [`linux/`](linux) | bash | apt, dnf, pacman, zypper |
| macOS | [`mac/`](mac) | bash | Homebrew |
| Windows | [`windows/`](windows) | PowerShell | winget |

Each family runs the same wizard: a cover panel, numbered steps, arrow key menus, a
spinner per long command and a report of what it wrote and what it skipped.

### Quick start

Download the file, read it, then run it. Piping a script straight into a shell skips the
reading step, which is the one thing this repo is trying to make easy.

**Linux and macOS**

```bash
curl -fsSLO https://raw.githubusercontent.com/Istiaq-Alam/Scripture/main/linux/setup-skills.sh
less setup-skills.sh
bash setup-skills.sh
```

**Windows** (PowerShell 5.1 or later)

```powershell
irm https://raw.githubusercontent.com/Istiaq-Alam/Scripture/main/windows/setup-skills.ps1 -OutFile setup-skills.ps1
notepad setup-skills.ps1
powershell -ExecutionPolicy Bypass -File .\setup-skills.ps1
```

The site in [`site/`](site) offers the same files, detected from your operating system,
with a sha256 for each.

| Job | Linux | macOS | Windows |
|---|---|---|---|
| Setup skills | `linux/setup-skills.sh` | `mac/setup-skills.sh` | `windows/setup-skills.ps1` |
| Laravel | `linux/setup-laravel.sh` | `mac/setup-laravel.sh` | `windows/setup-laravel.ps1` |
| Freebuff | `linux/setup-freebuff-zsh.sh` | `mac/setup-freebuff-zsh.sh` | `windows/setup-freebuff.ps1` |
| GitHub helper | `linux/gitcli.sh` | `mac/gitcli.sh` | `windows/gitcli.ps1` |
| Claude Code | `linux/claude-code.sh` | `mac/claude-code.sh` | `windows/claude-code.ps1` |

### Setup skills flags

The script asks before doing anything optional; flags skip the question.

| bash (Linux, macOS) | PowerShell (Windows) | Effect |
|---|---|---|
| `--brand <name>` | `-Brand <name>` | Pick a design system immediately, for example `linear` or `apple`. |
| `--list` | `-List` | Print every available design and exit. |
| `--skip-design` | `-SkipDesign` | Install the skills only, without a `DESIGN.md`. |
| `--debug` | `-Debug` | Show the full output of every command. |
| `--security` / `--no-security` | `-Security` / `-NoSecurity` | Force the Claude-Red offensive security skills on or off. |
| `--superpowers` / `--no-superpowers` | `-Superpowers` / `-NoSuperpowers` | Force the Superpowers workflow skills on or off. |
| `--unslop` / `--no-unslop` | `-Unslop` / `-NoUnslop` | Force the Unslop design skill on or off. |

It installs Impeccable, the Taste skill, Vercel's Web Design Guidelines and the landing
page design skill, then mirrors them into both `.claude/skills` and `.agents/skills` so
Claude Code and other agents find the same files. An existing `DESIGN.md` is kept as
`DESIGN.md.bak`. Design systems come from
[voltagent/awesome-design-md](https://github.com/voltagent/awesome-design-md), previewable
at [getdesign.md](https://getdesign.md/).

### Platform differences

- **Linux** installs packages through the system manager and asks for sudo only there.
- **macOS** uses Homebrew, starts services with `brew services`, and never calls sudo.
- **Windows** uses `winget`, refreshes PATH after installs, and may show an administrator
  prompt. PHP, Composer and the databases are installed only when missing; Composer's
  installer is checked against its published signature.

### About Claude Code on Ollama

The Claude Code scripts point Claude Code at a local Ollama server instead of the hosted
API, by setting the `ANTHROPIC_*` variables. Nothing leaves the machine, and the only key
involved is a placeholder the local server accepts.

---

## The site

`site/` is a static download page for all fifteen files: per-script, per-platform pages
with full source, line numbers, line anchors and a SHA-256 checksum. Plain HTML, CSS and
JavaScript served by a dependency free Node server. No framework, no build tool.

```bash
cd site
npm install
npm start
```

`npm start` copies every script into `public/downloads/<platform>/`, hashes each one,
writes `downloads/manifest.json`, regenerates `public/scripts/<slug>-<os>.html`, then
serves <http://localhost:3000>. The only dev dependency is `playwright-core`.

The page detects your platform from the browser, remembers an explicit choice in `?os=`
(`?os=windows&q=laravel`), and switches each row's command, tag, download, source link and
help text. Without JavaScript the Linux variant stays visible and the detail pages carry
their own platform tabs.

```bash
npm run build             # sync, hash and regenerate all fifteen detail pages
npm run shots             # screenshots at 1440, 820 and 390 plus overflow and console checks
npm run og                # regenerate public/og.png
node scripts/checks.mjs   # menu, clipboard, OS switch, search, filters, links, anchors, hashes
```

The browser checks need a local Chromium: they use `/usr/bin/chromium` unless `CHROME_PATH`
is set.

Deploy `site/public` to any static host. Every path is relative, so it works at a domain
root or under a subdirectory. The workflow in [`.github/workflows/pages.yml`](.github/workflows/pages.yml)
builds and publishes to GitHub Pages on every push to `main`; set **Settings → Pages →
Source** to **GitHub Actions** once.

More detail lives in [`site/README.md`](site/README.md), including how to add a sixth
script or a fourth platform.

---

## Repository layout

```text
.
├── linux/                   bash installers for apt, dnf, pacman and zypper
├── mac/                     bash installers built on Homebrew
├── windows/                 PowerShell installers built on winget
├── mysql-manual.md          MySQL and MariaDB CLI cheatsheet
├── terminal.html            standalone terminal style blog mockup
├── themes/                  design analyses of nine product sites
├── DESIGN.md                design system for the site, the source of truth
├── AGENTS.md                agent rules (CLAUDE.md is the same file)
├── skill-instructions.md    skills and workflow an agent reads each session
├── skills-lock.json         pinned skill sources and hashes
├── .mcp.json                Playwright MCP server
└── site/                    the static site
    ├── scripts/             catalog, page generator, sync, checks, screenshots, OG card
    ├── public/              index, styles, app, legal pages, generated output
    └── server.mjs           local static server
```

`themes/` holds written design analyses (Linear, Apple, Notion, Resend, Cal.com,
Intercom, SAP, Zapier, Mintlify). They informed `DESIGN.md` and are reference material,
not part of the build.

---

## Editing

- `DESIGN.md` owns color, type, spacing, radius and motion. The site follows it exactly.
- `site/scripts/data.mjs` is the single source of truth for every platform variant: source
  path, download path, tag, requirements, writes, privilege level, note and flags.
- Detail pages are generated by `site/scripts/pages.mjs`. Do not edit them by hand.
- Adding a platform means adding a folder, `OSES` and per-script variants in `data.mjs`,
  a button in the OS switch, and a `.variant` block per card in `public/index.html`.
  The CSS keys off `data-os`.
- `AGENTS.md` and `skill-instructions.md` describe the review pipeline (design audit,
  accessibility checks, browser QA) that changes to the site are expected to pass.

---

## Notes

- The Linux scripts are the originals and have been exercised on that platform. The macOS
  and Windows ports mirror their steps with Homebrew and winget; their syntax is checked
  in this repository, but CI does not execute installers on those systems.
- Several scripts change system packages, databases or shell profiles. Read the source
  before you run it.
- External services and models (Ollama, Gemini, Claude Code, GitHub, Homebrew, winget) are
  governed by their own terms and availability.
- No license file is included yet. Add one before reusing this code in your own project.

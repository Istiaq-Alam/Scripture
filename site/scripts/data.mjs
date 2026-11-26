// One source of truth for the catalog: downloads, list rows and detail pages.
// Every script ships one variant per operating system.

export const OSES = [
  {
    id: "linux",
    label: "Linux",
    short: "Linux",
    ext: "sh",
    shell: "bash",
    installTemplate: "bash <(curl -fsSL {url})",
    checksum: "shasum -a 256 {file}",
    note: "apt, dnf, pacman or zypper",
  },
  {
    id: "mac",
    label: "macOS",
    short: "macOS",
    ext: "sh",
    shell: "bash",
    installTemplate: "bash <(curl -fsSL {url})",
    checksum: "shasum -a 256 {file}",
    note: "Homebrew",
  },
  {
    id: "windows",
    label: "Windows",
    short: "Windows",
    ext: "ps1",
    shell: "PowerShell",
    installTemplate: "irm {url} -OutFile {file}; .\\{file}",
    checksum: "Get-FileHash {file} -Algorithm SHA256",
    note: "winget and PowerShell",
  },
];

const skillFlags = [
  ["--brand <name>", "Pick a design immediately, for example linear or apple."],
  ["--list", "Print every available design and exit."],
  ["--skip-design", "Install the skills only, without a DESIGN.md."],
  ["--debug", "Show the full output of every command."],
  ["--security / --no-security", "Force the Claude Red security skills on or off."],
  ["--superpowers / --no-superpowers", "Force the Superpowers workflow skills on or off."],
  ["--unslop / --no-unslop", "Force the Unslop design skill on or off."],
];

const skillFlagsPowerShell = [
  ["-Brand <name>", "Pick a design immediately, for example linear or apple."],
  ["-List", "Print every available design and exit."],
  ["-SkipDesign", "Install the skills only, without a DESIGN.md."],
  ["-Debug", "Show the full output of every command."],
  ["-Security / -NoSecurity", "Force the Claude Red security skills on or off."],
  ["-Superpowers / -NoSuperpowers", "Force the Superpowers workflow skills on or off."],
  ["-Unslop / -NoUnslop", "Force the Unslop design skill on or off."],
];

export const SCRIPTS = [
  {
    slug: "setup-skills",
    name: "Setup skills",
    brief: "Design skills, a DESIGN.md and the rules your agent reads.",
    summary:
      "Installs five design skills, a DESIGN.md and the rules file your agent reads at the start of every session. Prints a report at the end, including what it skipped.",
    variants: {
      linux: {
        source: "linux/setup-skills.sh",
        file: "linux/setup-skills.sh",
        tag: "no sudo",
        needs: "git, Node 18+, npx",
        writes:
          ".claude/skills, .agents/skills, DESIGN.md, CLAUDE.md, AGENTS.md, .mcp.json, skill-instructions.md",
        sudo: "No sudo",
        sudoFilter: "no",
        note: "Run it from the project root you want to change. An existing DESIGN.md is kept as DESIGN.md.bak. Optional packs are offered in an arrow key menu and can be forced with a flag.",
        flags: skillFlags,
      },
      mac: {
        source: "mac/setup-skills.sh",
        file: "mac/setup-skills.sh",
        tag: "no sudo",
        needs: "git, Node 18+, npx",
        writes:
          ".claude/skills, .agents/skills, DESIGN.md, CLAUDE.md, AGENTS.md, .mcp.json, skill-instructions.md",
        sudo: "No sudo",
        sudoFilter: "no",
        note: "Run it from the project root you want to change, in Terminal or iTerm. Node and git are required; Homebrew is not. An existing DESIGN.md is kept as DESIGN.md.bak.",
        flags: skillFlags,
      },
      windows: {
        source: "windows/setup-skills.ps1",
        file: "windows/setup-skills.ps1",
        tag: "no admin",
        needs: "git, Node 18+, npx",
        writes:
          ".claude/skills, .agents/skills, DESIGN.md, CLAUDE.md, AGENTS.md, .mcp.json, skill-instructions.md",
        sudo: "No admin",
        sudoFilter: "no",
        note: "Run it from the project root in PowerShell. If the execution policy blocks local scripts, start it with powershell -ExecutionPolicy Bypass -File .\\setup-skills.ps1. An existing DESIGN.md is kept as DESIGN.md.bak.",
        flags: skillFlagsPowerShell,
      },
    },
  },
  {
    slug: "laravel",
    name: "Laravel",
    brief: "PHP, a database and a working app in one guided run.",
    summary:
      "A guided Laravel install: choose PHP, choose a database, run migrations and finish with a working app in a new folder.",
    variants: {
      linux: {
        source: "linux/setup-laravel.sh",
        file: "linux/setup-laravel.sh",
        tag: "sudo",
        needs: "PHP 8.2+, Composer, a database",
        writes: "A new project folder, its .env, system packages and a database",
        sudo: "sudo for packages",
        sudoFilter: "yes",
        note: "Creates the project with composer create-project, installs missing packages through apt, dnf, pacman or zypper, provisions the database, then runs migrations and the starter kit steps.",
        flags: [],
      },
      mac: {
        source: "mac/setup-laravel.sh",
        file: "mac/setup-laravel.sh",
        tag: "no sudo",
        needs: "Homebrew, PHP 8.2+, Composer",
        writes: "A new project folder, its .env, Homebrew packages and a database",
        sudo: "No sudo",
        sudoFilter: "no",
        note: "Uses Homebrew to install PHP, Composer and the database only when they are missing, starts the database with brew services, creates it, then runs migrations and the starter kit steps.",
        flags: [],
      },
      windows: {
        source: "windows/setup-laravel.ps1",
        file: "windows/setup-laravel.ps1",
        tag: "admin for winget",
        needs: "PowerShell 5.1+, PHP 8.2+ or winget",
        writes: "A new project folder, its .env, winget packages and a database",
        sudo: "Admin for winget",
        sudoFilter: "yes",
        note: "Installs PHP and the database with winget only when they are missing, verifies the Composer installer signature, creates the project, writes .env and runs migrations. Open a new PowerShell window if a fresh winget install is not on PATH yet.",
        flags: [],
      },
    },
  },
  {
    slug: "freebuff-zsh",
    name: "Freebuff",
    brief: "Gemini key, the Freebuff CLI, one marked shell block.",
    summary:
      "Checks your Gemini key, installs the Freebuff CLI and adds one marked block to your shell profile. Removes the older block it used to write.",
    variants: {
      linux: {
        source: "linux/setup-freebuff-zsh.sh",
        file: "linux/setup-freebuff-zsh.sh",
        tag: "no sudo",
        needs: "zsh, npm, a Gemini key",
        writes: "~/.zshrc, one marked block, and the global freebuff npm package",
        sudo: "No sudo",
        sudoFilter: "no",
        note: "The key is written to ~/.zshrc between its own markers, so a later run replaces that block instead of appending another copy. The old ~/.bashrc block is removed.",
        flags: [],
      },
      mac: {
        source: "mac/setup-freebuff-zsh.sh",
        file: "mac/setup-freebuff-zsh.sh",
        tag: "no sudo",
        needs: "zsh, npm, a Gemini key",
        writes: "~/.zshrc, one marked block, and the global freebuff npm package",
        sudo: "No sudo",
        sudoFilter: "no",
        note: "Verifies the key against Google's endpoint before writing anything. The block is replaced on every run, and the older ~/.bashrc block is removed.",
        flags: [],
      },
      windows: {
        source: "windows/setup-freebuff.ps1",
        file: "windows/setup-freebuff.ps1",
        tag: "no admin",
        needs: "PowerShell 5.1+, npm, a Gemini key",
        writes: "$PROFILE, one marked block, and the global freebuff npm package",
        sudo: "No admin",
        sudoFilter: "no",
        note: "The key is written to $PROFILE between its own markers, so a later run replaces that block. It is sent once to Google's endpoint for verification and is not printed again.",
        flags: [],
      },
    },
  },
  {
    slug: "gitcli",
    name: "GitHub helper",
    brief: "First commit and push, with a .gitignore that keeps secrets out.",
    summary:
      "First push for a local project: checks git, writes a .gitignore, stages what is safe, commits and pushes to your repository.",
    variants: {
      linux: {
        source: "linux/gitcli.sh",
        file: "linux/gitcli.sh",
        tag: "sudo for deps",
        needs: "git, curl, figlet, lolcat",
        writes: ".gitignore, a commit, and the push to your remote",
        sudo: "sudo for packages",
        sudoFilter: "yes",
        note: "Run it from the project root. It installs figlet and lolcat when they are missing, then asks for a commit message if you did not pass one.",
        flags: [],
      },
      mac: {
        source: "mac/gitcli.sh",
        file: "mac/gitcli.sh",
        tag: "no sudo",
        needs: "git, curl (figlet and lolcat optional)",
        writes: ".gitignore, push.sh, a commit, and the push to your remote",
        sudo: "No sudo",
        sudoFilter: "no",
        note: "Run it from the project root. figlet and lolcat are offered through Homebrew but never required; the banner falls back to plain text. Run it again later to push or pull.",
        flags: [],
      },
      windows: {
        source: "windows/gitcli.ps1",
        file: "windows/gitcli.ps1",
        tag: "admin for winget",
        needs: "git, PowerShell 5.1+",
        writes: ".gitignore, push.ps1, a commit, and the push to your remote",
        sudo: "Admin for winget",
        sudoFilter: "yes",
        note: "Creates push.ps1 for later updates. Git is installed with winget only if it is missing and you agree. Run it from the project root in PowerShell.",
        flags: [],
      },
    },
  },
  {
    slug: "claude-code",
    name: "Claude Code on Ollama",
    brief: "A local Gemma model behind the Claude Code interface.",
    summary:
      "Installs Ollama, picks a Gemma model for your RAM, adds Node.js and Claude Code, then writes the local Anthropic endpoints to your shell config. Ends with a test prompt.",
    variants: {
      linux: {
        source: "linux/claude-code.sh",
        file: "linux/claude-code.sh",
        tag: "sudo",
        needs: "curl, sudo, Node.js if missing",
        writes:
          "Ollama, a Gemma model, Claude Code and six ANTHROPIC_ export lines in .zshrc or .bashrc",
        sudo: "sudo for Node.js",
        sudoFilter: "yes",
        note: "Reads your RAM to suggest a Gemma model, pulls it through Ollama, installs Claude Code when missing, writes six ANTHROPIC_ exports to your shell config, then offers a test prompt.",
        flags: [],
      },
      mac: {
        source: "mac/claude-code.sh",
        file: "mac/claude-code.sh",
        tag: "no sudo",
        needs: "Homebrew, curl, network",
        writes:
          "Ollama, a Gemma model, Claude Code and six ANTHROPIC_ export lines in ~/.zshrc",
        sudo: "No sudo",
        sudoFilter: "no",
        note: "Uses Homebrew for Ollama and Node, starts the Ollama service, picks a Gemma model from your Mac's RAM, then writes six ANTHROPIC_ exports in a marked block in ~/.zshrc.",
        flags: [],
      },
      windows: {
        source: "windows/claude-code.ps1",
        file: "windows/claude-code.ps1",
        tag: "admin for winget",
        needs: "PowerShell 5.1+, winget",
        writes:
          "Ollama, a Gemma model, Claude Code and six ANTHROPIC_ user environment variables",
        sudo: "Admin for winget",
        sudoFilter: "yes",
        note: "Installs Ollama and Node with winget when missing, starts the Ollama server, picks a Gemma model from the machine's RAM, then sets six ANTHROPIC_ variables for the current user. Open a new PowerShell window afterwards.",
        flags: [],
      },
    },
  },
];

export const findScript = (slug) => SCRIPTS.find((script) => script.slug === slug);
export const findOs = (id) => OSES.find((os) => os.id === id);

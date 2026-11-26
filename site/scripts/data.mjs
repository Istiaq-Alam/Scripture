// One source of truth for the script catalog: downloads, list rows and detail pages.
export const SCRIPTS = [
  {
    source: "Setup-skills.sh",
    file: "setup-skills.sh",
    slug: "setup-skills",
    name: "Setup skills",
    tag: "no sudo",
    summary:
      "Installs five design skills, a DESIGN.md and the rules file your agent reads at the start of every session. Prints a report at the end, including what it skipped.",
    needs: "git, Node 18+, npx",
    writes:
      ".claude/skills, .agents/skills, DESIGN.md, CLAUDE.md, AGENTS.md, .mcp.json, skill-instructions.md",
    sudo: "No sudo",
    note: "Run it from the project root you want to change. An existing DESIGN.md is kept as DESIGN.md.bak. Optional packs are offered in an arrow key menu and can be forced with a flag.",
    flags: [
      ["--brand <name>", "Pick a design immediately, for example linear or apple."],
      ["--list", "Print every available design and exit."],
      ["--skip-design", "Install the skills only, without a DESIGN.md."],
      ["--debug", "Show the full output of every command."],
      ["--security / --no-security", "Force the Claude Red security skills on or off."],
      ["--superpowers / --no-superpowers", "Force the Superpowers workflow skills on or off."],
      ["--unslop / --no-unslop", "Force the Unslop design skill on or off."],
    ],
  },
  {
    source: "setup-laravel.sh",
    file: "setup-laravel.sh",
    slug: "laravel",
    name: "Laravel",
    tag: "sudo",
    summary:
      "A guided Laravel install: choose PHP, choose a database, run migrations and finish with a working app in a new folder.",
    needs: "PHP 8.2+, Composer, a database",
    writes: "A new project folder, its .env, system packages and a database",
    sudo: "sudo for packages",
    note: "Creates the project with composer create-project, installs missing packages through apt, dnf, pacman or zypper, provisions the database, then runs migrations and the starter kit steps.",
    flags: [],
  },
  {
    source: "setup-freebuff-zsh.sh",
    file: "setup-freebuff-zsh.sh",
    slug: "freebuff-zsh",
    name: "Freebuff on zsh",
    tag: "no sudo",
    summary:
      "Checks your Gemini key, installs the Freebuff CLI and adds one marked block to .zshrc. Removes the older .bashrc block it used to write.",
    needs: "zsh, npm, a Gemini key",
    writes: "~/.zshrc, one marked block, and the global freebuff npm package",
    sudo: "No sudo",
    note: "The key is written to ~/.zshrc between its own markers, so a later run replaces that block instead of appending another copy.",
    flags: [],
  },
  {
    source: "gitcli.sh",
    file: "gitcli.sh",
    slug: "gitcli",
    name: "GitHub helper",
    tag: "sudo for deps",
    summary:
      "First push for a local project: checks git, writes a .gitignore, stages what is safe, commits and pushes to your repository.",
    needs: "git, curl, figlet, lolcat",
    writes: ".gitignore, a commit, and the push to your remote",
    sudo: "sudo for packages",
    note: "Run it from the project root. It installs figlet and lolcat when they are missing, then asks for a commit message if you did not pass one.",
    flags: [],
  },
  {
    source: "ClaudeCode.sh",
    file: "ClaudeCode.sh",
    slug: "claude-code",
    name: "Claude Code on Ollama",
    tag: "sudo",
    summary:
      "Installs Ollama, picks a Gemma model for your RAM, adds Node.js and Claude Code, then writes the local Anthropic endpoints to your shell config. Ends with a test prompt.",
    needs: "curl, sudo, Node.js if missing",
    writes:
      "Ollama, a Gemma model, Claude Code and six ANTHROPIC_ export lines in .zshrc or .bashrc",
    sudo: "sudo for Node.js",
    note: "Reads your RAM to suggest a Gemma model, pulls it through Ollama, installs Claude Code when missing, writes six ANTHROPIC_ exports to your shell config, then offers a test prompt.",
    flags: [],
  },
];

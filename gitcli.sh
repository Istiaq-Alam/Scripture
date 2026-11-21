#!/usr/bin/env bash
set -Eeuo pipefail

# GitHub first-time setup helper.
# Run this from the root of the project you want to publish.
#
# NOTE: This file must use Unix (LF) line endings. If you edit it on Windows
# and see "env: 'bash\r': No such file or directory", run:
#   sed -i 's/\r$//' giticli.sh

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'Warning: %s\n' "$*" >&2
}

# ------------------------------------------------------------------------------
# Dependency check and auto-install
# Requirements: bash, git, curl, figlet, lolcat, ANSI-Shadow.flf font
# ------------------------------------------------------------------------------

FONT_NAME="ANSI-Shadow"
FONT_FILE="${FONT_NAME}.flf"
FONT_URL="https://raw.githubusercontent.com/xero/figlet-fonts/master/ANSI%20Shadow.flf"
FONT_DIR=""
LOLCAT_BIN=""

# Make sure user-level install locations are searched.
export PATH="$PATH:/usr/games:/usr/local/games:$HOME/.local/bin:$HOME/.gem/bin"

# Find the directory that holds ANSI-Shadow.flf (empty output if not found).
find_font_dir() {
  local dirs=() d
  [[ -n "${FIGLET_FONT_PATH:-}" ]] && dirs+=("$FIGLET_FONT_PATH")
  if command -v figlet >/dev/null 2>&1; then
    d="$(figlet -I 2 2>/dev/null || true)"
    [[ -n "$d" ]] && dirs+=("$d")
  fi
  dirs+=(
    /usr/share/figlet
    /usr/share/figlet/fonts
    /usr/local/share/figlet
    /usr/share/figlet/fonts
    "$HOME/.figlet"
    "$(pwd)"
  )
  for d in "${dirs[@]}"; do
    if [[ -f "$d/$FONT_FILE" ]]; then
      printf '%s' "$d"
      return 0
    fi
  done
  return 1
}

find_lolcat() {
  if command -v lolcat >/dev/null 2>&1; then
    command -v lolcat
  elif [[ -x /usr/games/lolcat ]]; then
    printf '/usr/games/lolcat'
  fi
}

install_dependencies() {
  local missing=() pm="" sudo_cmd="" pkg

  command -v bash   >/dev/null 2>&1 || missing+=("bash")
  command -v git    >/dev/null 2>&1 || missing+=("git")
  command -v curl   >/dev/null 2>&1 || missing+=("curl")
  command -v figlet >/dev/null 2>&1 || missing+=("figlet")
  [[ -n "$(find_lolcat)" ]]         || missing+=("lolcat")

  local need_font=0
  if ! FONT_DIR="$(find_font_dir)"; then
    need_font=1
    FONT_DIR=""
  fi

  if [[ ${#missing[@]} -eq 0 && $need_font -eq 0 ]]; then
    LOLCAT_BIN="$(find_lolcat)"
    return 0
  fi

  printf '\n=== Installing required dependencies ===\n'
  if [[ ${#missing[@]} -gt 0 ]]; then
    printf '  Missing packages: %s\n' "${missing[*]}"
  fi
  if [[ $need_font -eq 1 ]]; then
    printf '  Missing font: %s\n' "$FONT_FILE"
  fi
  printf '\n'

  # Detect package manager and sudo requirement.
  if [[ ${#missing[@]} -gt 0 ]]; then
    for candidate in apt-get dnf yum pacman zypper apk; do
      if command -v "$candidate" >/dev/null 2>&1; then
        pm="$candidate"
        break
      fi
    done
    [[ -n "$pm" ]] || die "No supported package manager found (apt, dnf, yum, pacman, zypper, apk). Please install manually: ${missing[*]}"

    if [[ "$(id -u)" -ne 0 ]]; then
      command -v sudo >/dev/null 2>&1 || die "Root access is required to install packages and 'sudo' is not available. Install manually: ${missing[*]}"
      sudo_cmd="sudo"
    fi

    printf 'Using package manager: %s\n\n' "$pm"

    if [[ "$pm" == "apt-get" ]]; then
      $sudo_cmd apt-get update -qq || warn "apt-get update failed; continuing."
    fi

    # Install each package separately so one failure (e.g. lolcat missing from
    # a distro's repos) does not block the others.
    for pkg in "${missing[@]}"; do
      printf 'Installing %s...\n' "$pkg"
      case "$pm" in
        apt-get) $sudo_cmd apt-get install -y "$pkg" ;;
        dnf)     $sudo_cmd dnf install -y "$pkg" ;;
        yum)     $sudo_cmd yum install -y "$pkg" ;;
        pacman)  $sudo_cmd pacman -S --noconfirm --needed "$pkg" ;;
        zypper)  $sudo_cmd zypper --non-interactive install "$pkg" ;;
        apk)     $sudo_cmd apk add "$pkg" ;;
      esac || warn "Could not install '$pkg' with $pm."
    done
    printf '\n'
  fi

  # lolcat fallback: try RubyGems, then pip.
  if [[ -z "$(find_lolcat)" ]]; then
    printf 'Trying alternative lolcat install (gem / pip)...\n'
    if command -v gem >/dev/null 2>&1; then
      gem install --user-install lolcat >/dev/null 2>&1 || true
    fi
    if [[ -z "$(find_lolcat)" ]] && command -v pip3 >/dev/null 2>&1; then
      pip3 install --user lolcat >/dev/null 2>&1 \
        || pip3 install --user --break-system-packages lolcat >/dev/null 2>&1 \
        || true
    fi
  fi
  LOLCAT_BIN="$(find_lolcat)"
  [[ -n "$LOLCAT_BIN" ]] || warn "lolcat could not be installed. The banner will be shown without colors."

  # Download the figlet font if needed (into ~/.figlet, no sudo required).
  if [[ $need_font -eq 1 ]]; then
    command -v curl >/dev/null 2>&1 || die "curl is required to download the font but is not installed."
    printf 'Downloading %s...\n' "$FONT_FILE"
    mkdir -p "$HOME/.figlet"
    local tmp
    tmp="$(mktemp)"
    if curl -fsSL -o "$tmp" "$FONT_URL" && head -c 5 "$tmp" | grep -q '^flf2a'; then
      mv "$tmp" "$HOME/.figlet/$FONT_FILE"
      FONT_DIR="$HOME/.figlet"
      printf 'Font installed to: %s/%s\n\n' "$FONT_DIR" "$FONT_FILE"
    else
      rm -f "$tmp"
      warn "Could not download $FONT_FILE from $FONT_URL. The banner will be skipped."
    fi
  fi
}

show_banner() {
  command -v figlet >/dev/null 2>&1 || return 0
  [[ -n "$FONT_DIR" ]] || return 0
  local art
  art="$(figlet -d "$FONT_DIR" -f "$FONT_NAME" -c "Git*CLI" 2>/dev/null || true)"
  [[ -n "$art" ]] || return 0
  if [[ -n "$LOLCAT_BIN" ]]; then
    printf '%s\n' "$art" | "$LOLCAT_BIN" || printf '%s\n' "$art"
  else
    printf '%s\n' "$art"
  fi
}

# Run dependency check at startup
install_dependencies

# Verify git is available after potential install
command -v git >/dev/null 2>&1 || die "Git is not installed and could not be installed automatically."

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$PROJECT_ROOT"

# Once initialized, allow this same script to perform common Git operations.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf '\n \n'
  show_banner
  printf 'Project folder: %s\n\n' "$PROJECT_ROOT"
  printf '1) Push changes\n'
  printf '2) Pull latest changes\n'
  printf '3) Run initial setup / repair remote\n'
  read -r -p "Choose an option [1-3]: " ACTION
  case "$ACTION" in
    1)
      read -r -p "Commit message: " COMMIT_MESSAGE
      [[ -n "${COMMIT_MESSAGE//[[:space:]]/}" ]] || die "Commit message cannot be empty."
      git add -A
      if git diff --cached --quiet; then
        printf 'No new changes to commit. Attempting to push the current branch.\n'
      else
        git commit -m "$COMMIT_MESSAGE"
      fi
      BRANCH="$(git branch --show-current)"
      [[ -n "$BRANCH" ]] || die "Could not determine the current branch."
      git push -u origin "$BRANCH"
      printf '\nPush completed successfully.\n'
      exit 0
      ;;
    2)
      BRANCH="$(git branch --show-current)"
      [[ -n "$BRANCH" ]] || die "Could not determine the current branch."
      git remote get-url origin >/dev/null 2>&1 || die "No 'origin' remote is configured."
      printf 'Pulling latest changes for branch %s...\n' "$BRANCH"
      git pull --ff-only origin "$BRANCH"
      printf '\nPull completed successfully.\n'
      exit 0
      ;;
    3)
      printf 'Continuing with setup / repair.\n\n'
      ;;
    *)
      die "Invalid choice. Run the script again and choose 1, 2, or 3."
      ;;
  esac
fi

printf '\n=== Git project setup ===\n'
printf 'Project folder: %s\n\n' "$PROJECT_ROOT"

if [[ -e .git ]] && ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  die "A .git path exists but Git cannot use it. Check it before continuing."
fi

git init
git branch -M main

read -r -p "GitHub repository URL (HTTPS or SSH): " REPO_URL
[[ -n "${REPO_URL//[[:space:]]/}" ]] || die "Repository URL cannot be empty."

# Basic guard against accidental placeholder URLs.
if [[ "$REPO_URL" == *"YOUR_USERNAME"* || "$REPO_URL" == *"YOUR_REPOSITORY"* ]]; then
  die "Replace the example username/repository with your real GitHub repository URL."
fi

if git remote get-url origin >/dev/null 2>&1; then
  CURRENT_URL="$(git remote get-url origin)"
  printf 'Remote origin already exists: %s\n' "$CURRENT_URL"
  read -r -p "Replace origin with the URL you entered? [y/N]: " REPLACE_REMOTE
  if [[ "$REPLACE_REMOTE" =~ ^([yY]|[yY][eE][sS])$ ]]; then
    git remote set-url origin "$REPO_URL"
  else
    printf 'Keeping existing origin. The URL you entered was not applied.\n'
  fi
else
  git remote add origin "$REPO_URL"
fi

if ! git config user.name >/dev/null 2>&1; then
  read -r -p "Git author name: " GIT_NAME
  [[ -n "${GIT_NAME//[[:space:]]/}" ]] || die "Git author name cannot be empty."
  git config --global user.name "$GIT_NAME"
fi

if ! git config user.email >/dev/null 2>&1; then
  read -r -p "Git author email: " GIT_EMAIL
  [[ -n "${GIT_EMAIL//[[:space:]]/}" ]] || die "Git author email cannot be empty."
  git config --global user.email "$GIT_EMAIL"
fi

if [[ ! -e .gitignore ]]; then
  cat > .gitignore <<'GITIGNORE'
# Secrets and environment files
.env
.env.*
!.env.example
!.env.*.example

# Dependencies
node_modules/
vendor/

# Build output and caches
dist/
build/
.next/
.nuxt/
.cache/
coverage/

# Logs and temporary files
*.log
npm-debug.log*
yarn-debug.log*
pnpm-debug.log*
tmp/
temp/

# Operating system and editor files
.DS_Store
Thumbs.db
.idea/
.vscode/

# Python
__pycache__/
*.py[cod]
.venv/
venv/

# Private keys and certificates
*.pem
*.key

# Local database files (remove these rules if you intentionally version them)
*.sqlite
*.sqlite3
GITIGNORE
  printf 'Created .gitignore\n'
else
  printf 'Keeping existing .gitignore (not overwritten).\n'
fi

if [[ ! -e push.sh ]]; then
  cat > push.sh <<'PUSH_SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

command -v git >/dev/null 2>&1 || die "Git is not installed."
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Run this script from inside a Git repository."

# Usage:
#   ./push.sh "Commit message"  -> stage, commit, and push
#   ./push.sh pull              -> pull latest changes (fast-forward only)
#   ./push.sh push "Message"    -> explicit push action
ACTION="push"
if (($# > 0)) && [[ "$1" == "pull" ]]; then
  ACTION="pull"
  shift
elif (($# > 0)) && [[ "$1" == "push" ]]; then
  shift
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  die "No 'origin' remote is configured. Run giticli.sh first or add the remote."
fi

BRANCH="$(git branch --show-current)"
[[ -n "$BRANCH" ]] || die "Could not determine the current branch. Check out a branch first."

if [[ "$ACTION" == "pull" ]]; then
  git pull --ff-only origin "$BRANCH"
  printf '\nPull completed successfully.\n'
  exit 0
fi

# If no commit message was supplied, ask interactively.
if (($# > 0)); then
  COMMIT_MESSAGE="$*"
else
  read -r -p "Commit message: " COMMIT_MESSAGE
fi
[[ -n "${COMMIT_MESSAGE//[[:space:]]/}" ]] || die "Commit message cannot be empty."

git add -A

if git diff --cached --quiet; then
  printf 'No staged changes to commit. Checking whether the branch can be pushed...\n'
else
  git commit -m "$COMMIT_MESSAGE"
fi

git push -u origin "$BRANCH"
printf '\nPush completed successfully.\n'
PUSH_SCRIPT
  chmod +x push.sh
  printf 'Created push.sh and made it executable\n'
else
  printf 'Keeping existing push.sh (not overwritten).\n'
  if [[ ! -x push.sh ]]; then
    chmod +x push.sh
    printf 'Made existing push.sh executable\n'
  fi
fi

printf '\nReview files before uploading. In particular, make sure no passwords, API keys, tokens, or private files are included.\n'
git status --short

read -r -p "First commit message: " FIRST_COMMIT
[[ -n "${FIRST_COMMIT//[[:space:]]/}" ]] || die "Commit message cannot be empty."

git add -A

if git diff --cached --quiet; then
  printf 'No new files to commit. Checking for an existing commit...\n'
  git rev-parse --verify HEAD >/dev/null 2>&1 || die "There are no files to commit and no existing commit."
else
  git commit -m "$FIRST_COMMIT"
fi

printf '\nPushing branch main to origin...\n'
git push -u origin main

printf '\nSetup complete!\n'
printf 'Future updates: ./push.sh "Describe your changes"\n'

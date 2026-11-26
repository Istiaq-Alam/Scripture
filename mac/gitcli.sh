#!/usr/bin/env bash
# GitHub first-time setup helper for macOS.
# Run this from the root of the project you want to publish.
set -Eeuo pipefail

IS_TTY=0; [ -t 1 ] && IS_TTY=1
if [ "$IS_TTY" = "1" ]; then
  E=$'\033'
  GREEN="${E}[38;5;114m"; YELLOW="${E}[38;5;179m"; RED="${E}[38;5;203m"
  CYAN="${E}[38;5;111m"; ACCENT="${E}[38;5;111m"; MUTED="${E}[38;5;244m"
  BOLD="${E}[1m"; NC="${E}[0m"
else
  GREEN=""; YELLOW=""; RED=""; CYAN=""; ACCENT=""; MUTED=""; BOLD=""; NC=""
fi

die()  { printf '  %s[FAIL]%s %s\n' "$RED" "$NC" "$*" >&2; exit 1; }
warn() { printf '  %s[WARN]%s %s\n' "$YELLOW" "$NC" "$*" >&2; }

cols() {
  local c; c="$(tput cols 2>/dev/null || echo 80)"
  case "$c" in ''|*[!0-9]*) c=80 ;; esac
  [ "$c" -lt 60 ] && c=60; [ "$c" -gt 96 ] && c=96
  echo "$c"
}
ui_clear() { [ "$IS_TTY" = "1" ] && printf '%s[H%s[2J%s[3J' "$E" "$E" "$E"; }
ui_rule() { local c i; c=$(cols); printf '%s' "$MUTED"; i=0; while [ $i -lt "$c" ]; do printf '─'; i=$((i + 1)); done; printf '%s\n' "$NC"; }
ui_panel() {
  local color="$1" title="$2"; shift 2
  local c inner fill i line t
  c=$(cols); inner=$((c - 4)); t=" $title "
  fill=$((c - 3 - ${#t})); [ "$fill" -lt 0 ] && fill=0
  printf '\n%s╭─%s%s' "$color" "$t" "$NC"
  i=0; while [ $i -lt "$fill" ]; do printf '%s─' "$color"; i=$((i + 1)); done
  printf '%s╮%s\n' "$color" "$NC"
  for line in "$@"; do
    [ "${#line}" -gt "$inner" ] && line="${line:0:$inner}"
    printf '%s│%s %-*s %s│%s\n' "$color" "$NC" "$((inner - 2))" "$line" "$color" "$NC"
  done
  printf '%s╰' "$color"; i=0; while [ $i -lt $((c - 2)) ]; do printf '─'; i=$((i + 1)); done; printf '╯%s\n' "$NC"
}
ok()   { printf '  %s[OK]%s   %s\n' "$GREEN" "$NC" "$1"; }
info() { printf '  %s%s%s\n' "$MUTED" "$1" "$NC"; }
step() { ui_clear; printf '\n%s❯%s %s%s%s\n' "$ACCENT" "$NC" "$BOLD" "$1" "$NC"; ui_rule; echo; }
kv()   { printf '  %s%-14s%s %s\n' "$MUTED" "$1" "$NC" "$2"; }

INPUT_DEV=""
if ( exec </dev/tty ) 2>/dev/null; then INPUT_DEV="/dev/tty"
elif [ -t 0 ]; then INPUT_DEV="/dev/stdin"; fi

ask() { # prompt default
  local q="$1" d="${2:-}" a=""
  if [ -z "$INPUT_DEV" ]; then printf '%s' "${d:-$q}"; return 0; fi
  printf '  %s%s%s ' "$BOLD" "$q" "$NC"
  IFS= read -r a <"$INPUT_DEV" || a=""
  if [ -z "$a" ]; then a="$d"; fi
  printf '%s' "$a"
}
ask_secret() {
  local q="$1" a=""
  if [ -z "$INPUT_DEV" ]; then printf ''; return 0; fi
  printf '  %s%s%s ' "$BOLD" "$q" "$NC"
  IFS= read -rs a <"$INPUT_DEV" || a=""
  echo
  printf '%s' "$a"
}
confirm() { # question default
  local q="$1" d="${2:-n}" a=""
  [ -z "$INPUT_DEV" ] && { [ "$d" = "y" ]; return; }
  printf '  %s%s%s [%s/%s] ' "$BOLD" "$q" "$NC" "$([ "$d" = y ] && echo Y || echo y)" "$([ "$d" = y ] && echo n || echo N)"
  IFS= read -r a <"$INPUT_DEV" || a=""
  if [ -z "$a" ]; then a="$d"; fi
  case "$a" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

show_banner() {
  ui_clear
  if command -v figlet >/dev/null 2>&1; then
    figlet -f "ANSI Shadow" "GIT" 2>/dev/null || figlet "GIT" 2>/dev/null || true
  else
    printf '%sGIT%s\n' "$BOLD" "$NC"
  fi
  ui_rule
}

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------
step "Checking dependencies"
for cmd in git curl; do
  command -v "$cmd" >/dev/null 2>&1 || {
    if [ "$cmd" = git ]; then
      err "git is missing. Install the Command Line Tools:  xcode-select --install"
    else
      err "curl is missing. It ships with macOS; check your PATH."
    fi
    exit 1
  }
done
ok "git $(git --version 2>/dev/null | awk '{print $3}') | curl $(curl --version | head -1 | awk '{print $2}')"

if ! command -v figlet >/dev/null 2>&1 || ! command -v lolcat >/dev/null 2>&1; then
  info "figlet and lolcat are optional; the banner falls back to plain text."
  if command -v brew >/dev/null 2>&1 && confirm "Install figlet and lolcat with Homebrew?" n; then
    brew install figlet lolcat >/dev/null 2>&1 && ok "figlet and lolcat installed" || warn "brew install failed; continuing"
  fi
fi

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$PROJECT_ROOT"

# -----------------------------------------------------------------------------
# Existing repository: push, pull or repair
# -----------------------------------------------------------------------------
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  show_banner
  kv "Project" "$PROJECT_ROOT"
  echo
  printf '  1) Push changes\n  2) Pull latest changes\n  3) Run initial setup / repair remote\n\n'
  ACTION="$(ask "Choose an option [1-3]:" "3")"
  case "$ACTION" in
    1)
      COMMIT_MESSAGE="$(ask "Commit message:")"
      [ -n "${COMMIT_MESSAGE//[[:space:]]/}" ] || die "Commit message cannot be empty."
      git add -A
      if git diff --cached --quiet; then
        printf 'No new changes to commit. Attempting to push the current branch.\n'
      else
        git commit -m "$COMMIT_MESSAGE"
      fi
      BRANCH="$(git branch --show-current)"
      [ -n "$BRANCH" ] || die "Could not determine the current branch."
      git push -u origin "$BRANCH"
      ok "Push completed"
      exit 0
      ;;
    2)
      BRANCH="$(git branch --show-current)"
      [ -n "$BRANCH" ] || die "Could not determine the current branch."
      git remote get-url origin >/dev/null 2>&1 || die "No 'origin' remote is configured."
      info "Pulling origin/$BRANCH"
      git pull --ff-only origin "$BRANCH"
      ok "Pull completed"
      exit 0
      ;;
    3) info "Continuing with setup / repair." ;;
    *) die "Invalid choice. Run the script again and choose 1, 2 or 3." ;;
  esac
fi

# -----------------------------------------------------------------------------
# First-time setup
# -----------------------------------------------------------------------------
show_banner
kv "Project" "$PROJECT_ROOT"
echo

if [ -e .git ] && ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  die "A .git path exists but Git cannot use it. Check it before continuing."
fi

git init >/dev/null
git branch -M main 2>/dev/null || true
ok "Initialised the repository on branch main"

REPO_URL="$(ask "GitHub repository URL (HTTPS or SSH):")"
[ -n "${REPO_URL//[[:space:]]/}" ] || die "Repository URL cannot be empty."
case "$REPO_URL" in
  *YOUR_USERNAME*|*YOUR_REPOSITORY*) die "Replace the example username/repository with your real URL." ;;
esac

if git remote get-url origin >/dev/null 2>&1; then
  CURRENT_URL="$(git remote get-url origin)"
  warn "Remote origin already exists: $CURRENT_URL"
  if confirm "Replace origin with the URL you entered?" n; then
    git remote set-url origin "$REPO_URL"
    ok "origin replaced"
  else
    info "Keeping the existing origin."
  fi
else
  git remote add origin "$REPO_URL"
  ok "origin added"
fi

if ! git config user.name >/dev/null 2>&1; then
  GIT_NAME="$(ask "Git author name:")"
  [ -n "${GIT_NAME//[[:space:]]/}" ] || die "Git author name cannot be empty."
  git config --global user.name "$GIT_NAME"
fi
if ! git config user.email >/dev/null 2>&1; then
  GIT_EMAIL="$(ask "Git author email:")"
  [ -n "${GIT_EMAIL//[[:space:]]/}" ] || die "Git author email cannot be empty."
  git config --global user.email "$GIT_EMAIL"
fi

if [ ! -e .gitignore ]; then
  cat >.gitignore <<'GITIGNORE'
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
  ok "Created .gitignore"
else
  info "Keeping the existing .gitignore (not overwritten)."
fi

if [ ! -e push.sh ]; then
  cat >push.sh <<'PUSH_SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "Git is not installed."
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Run this from inside a Git repository."

# Usage:
#   ./push.sh "Commit message"  -> stage, commit, push
#   ./push.sh pull              -> pull latest changes (fast-forward only)
ACTION="push"
if (($# > 0)) && [[ "$1" == "pull" ]]; then ACTION="pull"; shift
elif (($# > 0)) && [[ "$1" == "push" ]]; then shift; fi

git remote get-url origin >/dev/null 2>&1 || die "No 'origin' remote. Run the setup script first."
BRANCH="$(git branch --show-current)"
[[ -n "$BRANCH" ]] || die "Could not determine the current branch."

if [[ "$ACTION" == "pull" ]]; then
  git pull --ff-only origin "$BRANCH"
  printf '\nPull completed successfully.\n'
  exit 0
fi

if (($# > 0)); then COMMIT_MESSAGE="$*"; else
  read -r -p "Commit message: " COMMIT_MESSAGE
fi
[[ -n "${COMMIT_MESSAGE//[[:space:]]/}" ]] || die "Commit message cannot be empty."

git add -A
if git diff --cached --quiet; then
  printf 'No staged changes. Checking whether the branch can be pushed...\n'
else
  git commit -m "$COMMIT_MESSAGE"
fi

git push -u origin "$BRANCH"
printf '\nPush completed successfully.\n'
PUSH_SCRIPT
  chmod +x push.sh
  ok "Created push.sh"
else
  info "Keeping the existing push.sh."
  [ -x push.sh ] || chmod +x push.sh
fi

echo
warn "Review the files below before uploading. No passwords, keys or tokens should appear."
git status --short

FIRST_COMMIT="$(ask "First commit message:" "Initial commit")"
[ -n "${FIRST_COMMIT//[[:space:]]/}" ] || die "Commit message cannot be empty."

git add -A
if git diff --cached --quiet; then
  info "No new files to commit."
  git rev-parse --verify HEAD >/dev/null 2>&1 || die "Nothing to commit and no existing commit."
else
  git commit -m "$FIRST_COMMIT"
fi

info "Pushing branch main to origin..."
git push -u origin main

echo
ui_panel "$GREEN" "DONE" \
  "Repository  $PROJECT_ROOT" \
  "Remote      $(git remote get-url origin 2>/dev/null || echo none)" \
  "Branch      main" \
  "" \
  "Next updates: ./push.sh \"Describe your changes\""
echo

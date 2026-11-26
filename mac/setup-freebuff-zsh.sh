#!/usr/bin/env zsh
# Freebuff CLI on macOS, configured with a Gemini API key.
# Verifies the key, installs the CLI and writes one marked block to ~/.zshrc.
set -uo pipefail

GEMINI_BASE_URL="https://generativelanguage.googleapis.com/v1beta/openai/"
ZSH_RC="$HOME/.zshrc"
OTHER_RC="$HOME/.bashrc"

IS_TTY=0; [ -t 1 ] && IS_TTY=1
if [ "$IS_TTY" = "1" ]; then
  E=$'\033'
  GREEN="${E}[38;5;114m"; YELLOW="${E}[38;5;179m"; RED="${E}[38;5;203m"
  CYAN="${E}[38;5;111m"; ACCENT="${E}[38;5;111m"; MUTED="${E}[38;5;244m"
  BOLD="${E}[1m"; NC="${E}[0m"
else
  GREEN=""; YELLOW=""; RED=""; CYAN=""; ACCENT=""; MUTED=""; BOLD=""; NC=""
fi

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
warn() { printf '  %s[WARN]%s %s\n' "$YELLOW" "$NC" "$1"; }
err()  { printf '  %s[FAIL]%s %s\n' "$RED" "$NC" "$1"; }
info() { printf '  %s%s%s\n' "$MUTED" "$1" "$NC"; }
step() { ui_clear; printf '\n%s❯%s %s%s%s\n' "$ACCENT" "$NC" "$BOLD" "$1" "$NC"; ui_rule; echo; }

INPUT_DEV=""
if ( exec </dev/tty ) 2>/dev/null; then INPUT_DEV="/dev/tty"
elif [ -t 0 ]; then INPUT_DEV="/dev/stdin"; fi

ui_clear
ui_panel "$ACCENT" "FREEBUFF CLI · macOS" \
  "Gemini key, the CLI, and one marked block in your zsh config." \
  "" \
  "Shell config: $ZSH_RC" \
  "Nothing is written until the key is verified."
echo

step "1/4 Gemini API key"
if [ -n "$INPUT_DEV" ]; then
  printf '  %sPaste your Google Gemini API key (AIza..., input hidden):%s ' "$BOLD" "$NC"
  IFS= read -rs GEMINI_KEY <"$INPUT_DEV" || GEMINI_KEY=""
  echo
else
  err "No terminal available to read the key."
  exit 1
fi

if [ -z "${GEMINI_KEY:-}" ]; then
  err "API key cannot be empty."
  exit 1
fi

step "2/4 Verifying the key"
printf '  %sChecking Google’s OpenAI-compatible endpoint...%s\n' "$MUTED" "$NC"
HTTP_STATUS="$(curl -s -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer $GEMINI_KEY" \
  "${GEMINI_BASE_URL}models" || echo "000")"
case "$HTTP_STATUS" in
  200) ok "API key verified" ;;
  401|403) err "The key was rejected (HTTP $HTTP_STATUS). Create a new key in Google AI Studio."; exit 1 ;;
  *) err "Verification failed (HTTP $HTTP_STATUS). Check your connection and the key."; exit 1 ;;
esac

step "3/4 Freebuff CLI"
if command -v freebuff >/dev/null 2>&1; then
  ok "freebuff already installed ($(freebuff --version 2>/dev/null || echo version unknown))"
else
  if ! command -v npm >/dev/null 2>&1; then
    err "npm is not installed. Install Node.js first: brew install node"
    exit 1
  fi
  info "Installing freebuff@latest globally..."
  if npm install -g freebuff@latest; then
    ok "freebuff installed"
  else
    err "npm install failed. Try: sudo npm install -g freebuff@latest"
    exit 1
  fi
fi

step "4/4 Shell configuration"
# Remove the block this script owns, wherever it was written before.
strip_block() {
  local file="$1"
  [ -f "$file" ] || return 0
  n=$(grep -n '# >>> freebuff-gemini-setup >>>' "$file" 2>/dev/null | head -1 | cut -d: -f1)
  [ -z "$n" ] && return 0
  e=$(grep -n '# <<< freebuff-gemini-setup <<<' "$file" 2>/dev/null | head -1 | cut -d: -f1)
  [ -z "$e" ] && return 0
  awk -v s="$n" -v en="$e" 'NR < s || NR > en' "$file" >"$file.tmp.$$" && mv "$file.tmp.$$" "$file"
}

strip_block "$OTHER_RC"
strip_block "$ZSH_RC"

if [ ! -f "$ZSH_RC" ]; then
  : >"$ZSH_RC"
  ok "Created $ZSH_RC"
fi

# Escape any double quotes so the export stays valid zsh.
SAFE_KEY="$(printf '%s' "$GEMINI_KEY" | sed 's/"/\\"/g')"
{
  echo ""
  echo "# >>> freebuff-gemini-setup >>>"
  echo "export GEMINI_API_KEY=\"$SAFE_KEY\""
  echo "# <<< freebuff-gemini-setup <<<"
} >>"$ZSH_RC"

ok "Saved GEMINI_API_KEY to $ZSH_RC (marked block, replaced on every run)"
if [ -f "$OTHER_RC" ] && grep -q '# >>> freebuff-gemini-setup >>>' "$OTHER_RC" 2>/dev/null; then
  warn "The old block in $OTHER_RC could not be removed."
fi

echo
ui_panel "$GREEN" "READY" \
  "Gemini key   verified" \
  "freebuff     installed" \
  "zsh block    $ZSH_RC" \
  "" \
  "Next:" \
  "  source ~/.zshrc && freebuff"
echo

#!/usr/bin/env bash
# Claude Code on a local Ollama model - macOS port.
# Installs Ollama, picks a Gemma model for this Mac, installs Claude Code and
# points the Anthropic endpoints at 127.0.0.1:11434.
set -uo pipefail

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

enter_prompt() {
  [ -z "$INPUT_DEV" ] && return 0
  printf '\n  %spress Enter to continue%s ' "$MUTED" "$NC"
  IFS= read -r _ <"$INPUT_DEV" || true
}

menu_select() {
  local title="$1" def="$2"; shift 2
  local count=$# sel="$def" key rest i
  if [ "$IS_TTY" != "1" ] || [ -z "$INPUT_DEV" ]; then
    echo "$title"
    i=1; for x in "$@"; do printf '  %d) %s\n' "$i" "$x"; i=$((i + 1)); done
    MENU_RESULT="$def"; return 0
  fi
  while :; do
    ui_clear
    printf '\n  %s%s%s\n\n' "$BOLD" "$title" "$NC"
    i=0
    while [ $i -lt "$count" ]; do
      if [ $i -eq "$sel" ]; then
        printf '  %s❯ %s%s\n' "$ACCENT" "${@:$((i + 1)):1}" "$NC"
      else
        printf '    %s\n' "${@:$((i + 1)):1}"
      fi
      i=$((i + 1))
    done
    printf '\n  %s↑ ↓ move   Enter select%s\n' "$MUTED" "$NC"
    IFS= read -rsn1 key <"$INPUT_DEV" || key=""
    case "$key" in
      $'\033')
        rest=""; IFS= read -rsn2 -t 1 rest <"$INPUT_DEV" || true
        case "$rest" in
          '[A') [ "$sel" -gt 0 ] && sel=$((sel - 1)) ;;
          '[B') [ "$sel" -lt $((count - 1)) ] && sel=$((sel + 1)) ;;
        esac
        ;;
      '') break ;;
      k|K) [ "$sel" -gt 0 ] && sel=$((sel - 1)) ;;
      j|J) [ "$sel" -lt $((count - 1)) ] && sel=$((sel + 1)) ;;
    esac
  done
  MENU_RESULT="$sel"
}

ui_clear
ui_panel "$ACCENT" "CLAUDE CODE · OLLAMA · macOS" \
  "A local model, a local endpoint, no hosted API." \
  "" \
  "Steps: Ollama, a Gemma model, Node.js, Claude Code, env."
echo

step "0/5 Checking network and Homebrew"
if ! curl -fsS -o /dev/null --max-time 8 https://ollama.com 2>/dev/null; then
  err "No internet connection detected (ollama.com unreachable)."
  exit 1
fi
ok "Internet reachable"

if command -v brew >/dev/null 2>&1; then
  ok "Homebrew found ($(brew --version | head -1))"
else
  warn "Homebrew is not installed. It is needed for Ollama and Node."
  info "Install it from https://brew.sh, then run this script again."
  exit 1
fi

step "1/5 Ollama"
if command -v ollama >/dev/null 2>&1; then
  ok "Ollama already installed ($(ollama --version 2>/dev/null | head -1))"
else
  info "Installing Ollama with Homebrew..."
  if brew install ollama; then ok "Ollama installed"; else err "brew install ollama failed"; exit 1; fi
fi

# Make sure the server answers; start it as a background service when needed.
if ! curl -fsS -o /dev/null --max-time 2 http://127.0.0.1:11434/api/tags 2>/dev/null; then
  info "Starting the Ollama server..."
  if brew services start ollama >/dev/null 2>&1; then
    ok "Ollama started with brew services"
  else
    nohup ollama serve >/tmp/ollama-serve.log 2>&1 &
    warn "Started 'ollama serve' in the background (log: /tmp/ollama-serve.log)"
  fi
  for _ in $(seq 1 30); do
    curl -fsS -o /dev/null --max-time 2 http://127.0.0.1:11434/api/tags 2>/dev/null && break
    sleep 1
  done
fi
if curl -fsS -o /dev/null --max-time 2 http://127.0.0.1:11434/api/tags 2>/dev/null; then
  ok "Ollama API is answering on 127.0.0.1:11434"
else
  err "Ollama did not start. Run 'ollama serve' in another terminal and retry."
  exit 1
fi

step "2/5 Choose a Gemma model"
RAM_BYTES="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
TOTAL_RAM=$((RAM_BYTES / 1073741824))
printf '  Detected RAM: %s%sGB%s\n\n' "$GREEN" "$TOTAL_RAM" "$NC"

if [ "$TOTAL_RAM" -le 8 ]; then SUGGESTED="gemma4:e2b"
elif [ "$TOTAL_RAM" -le 16 ]; then SUGGESTED="gemma4:e4b"
else SUGGESTED="gemma4:26b"; fi

info "Recommended for this Mac: $SUGGESTED"
menu_select "Choose a model" 1 \
  "gemma4:e2b  (~3GB)  → 8GB RAM" \
  "gemma4:e4b  (~7GB)  → 16GB RAM" \
  "gemma4:26b (~18GB) → 32GB RAM"
case "$MENU_RESULT" in
  0) MODEL="gemma4:e2b" ;;
  1) MODEL="gemma4:e4b" ;;
  2) MODEL="gemma4:26b" ;;
  *) MODEL="$SUGGESTED" ;;
esac
ok "Selected $MODEL"

if ollama list 2>/dev/null | grep -q "${MODEL%%:*}"; then
  ok "Model already present, skipping the download"
else
  info "Pulling $MODEL (this can take a while)..."
  if ollama pull "$MODEL"; then ok "Model downloaded"; else err "ollama pull failed"; exit 1; fi
fi
ollama list 2>/dev/null | sed 's/^/      /'

step "3/5 Node.js"
if command -v node >/dev/null 2>&1; then
  ok "Node.js already installed ($(node -v))"
else
  info "Installing Node.js with Homebrew..."
  if brew install node; then ok "Node.js installed ($(node -v))"; else err "brew install node failed"; exit 1; fi
fi
command -v npm >/dev/null 2>&1 || { err "npm is missing from PATH."; exit 1; }

step "4/5 Claude Code"
if command -v claude >/dev/null 2>&1; then
  ok "Claude Code already installed"
else
  info "Running the official installer..."
  if curl -fsSL https://claude.ai/install.sh | bash; then
    ok "Claude Code installed"
  else
    warn "Official installer failed, falling back to npm"
    if npm install -g @anthropic-ai/claude-code; then ok "Claude Code installed with npm"; else
      err "Claude Code install failed"; exit 1
    fi
  fi
fi
claude --version 2>/dev/null | sed 's/^/      /' || warn "Could not read the Claude Code version"

step "5/5 Environment"
ZSH_RC="$HOME/.zshrc"
BASH_RC="$HOME/.bashrc"

strip_block() {
  local file="$1" n e
  [ -f "$file" ] || return 0
  n=$(grep -n '# >>> claude-ollama-setup >>>' "$file" 2>/dev/null | head -1 | cut -d: -f1)
  [ -z "$n" ] && return 0
  e=$(grep -n '# <<< claude-ollama-setup <<<' "$file" 2>/dev/null | head -1 | cut -d: -f1)
  [ -z "$e" ] && return 0
  awk -v s="$n" -v en="$e" 'NR < s || NR > en' "$file" >"$file.tmp.$$" && mv "$file.tmp.$$" "$file"
}

strip_block "$ZSH_RC"
strip_block "$BASH_RC"
[ -f "$ZSH_RC" ] || : >"$ZSH_RC"

{
  echo ""
  echo "# >>> claude-ollama-setup >>>"
  echo "export ANTHROPIC_AUTH_TOKEN=ollama"
  echo "export ANTHROPIC_API_KEY=\"\""
  echo "export ANTHROPIC_BASE_URL=http://localhost:11434"
  echo "export ANTHROPIC_DEFAULT_HAIKU_MODEL=$MODEL"
  echo "export ANTHROPIC_DEFAULT_SONNET_MODEL=$MODEL"
  echo "export ANTHROPIC_DEFAULT_OPUS_MODEL=$MODEL"
  echo "# <<< claude-ollama-setup <<<"
} >>"$ZSH_RC"
ok "Wrote six ANTHROPIC_ exports to $ZSH_RC (marked block)"

echo
ui_panel "$GREEN" "READY" \
  "Ollama          running on 11434" \
  "Model           $MODEL" \
  "Claude Code     installed" \
  "Shell config    $ZSH_RC" \
  "" \
  "Open a new terminal, then run:  claude"
echo

USERNAME="$(whoami)"
if [ -n "$INPUT_DEV" ]; then
  printf '  %sTest the model with a short prompt now?%s [y/N] ' "$BOLD" "$NC"
  IFS= read -r RUN_TEST <"$INPUT_DEV" || RUN_TEST=""
else
  RUN_TEST="n"
fi
case "$RUN_TEST" in
  y|Y|yes|YES)
    info "Sending a test prompt to $MODEL..."
    ollama run "$MODEL" "Hello, I am $USERNAME. Greet me in one sentence." || warn "The test prompt failed."
    ;;
  *) info "Skipped the test prompt. Try it later with: ollama run $MODEL" ;;
esac

echo
printf '  %sStart Claude Code later with:%s\n' "$MUTED" "$NC"
printf '    source ~/.zshrc && claude --model %s\n' "$MODEL"
printf '    ollama launch claude --model %s   # when your Ollama version supports it\n\n' "$MODEL"

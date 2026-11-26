#!/usr/bin/env bash
# =============================================================================
# Setup-Skills - macOS
# Installs 5 frontend design skills + CLAUDE.md / AGENTS.md into the CURRENT
# project folder. Run it from your project root, in Terminal or iTerm.
#
#   ./setup-skills.sh                 # interactive menu: pick a design
#   ./setup-skills.sh --brand linear  # pick a design directly
#   ./setup-skills.sh --list          # list all designs and exit
#   ./setup-skills.sh --skip-design   # skills only, no DESIGN.md
#   ./setup-skills.sh --debug         # show full output of every command
#
# Optional extras (the script ASKS you; flags skip the question):
#   --security / --no-security         Claude-Red offensive security skills
#   --superpowers / --no-superpowers   obra/superpowers workflow skills
#   --unslop / --no-unslop             heydamir/unslop (fix AI-looking UI)
# =============================================================================

if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then exec bash "$0" "$@"; fi
  echo "ERROR: this script needs bash. Run:  bash $0"; exit 1
fi

set -uo pipefail
export GIT_TERMINAL_PROMPT=0
export CI=1 NO_COLOR=1 FORCE_COLOR=0

BRAND="${BRAND:-}"; SKIP_DESIGN=0; LIST_ONLY=0; DEBUG=0
WANT_SECURITY=""; WANT_SUPERPOWERS=""; WANT_UNSLOP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --brand|-b)    BRAND="${2:-}"; shift 2 ;;
    --list|-l)     LIST_ONLY=1; shift ;;
    --skip-design) SKIP_DESIGN=1; shift ;;
    --debug)       DEBUG=1; shift ;;
    --security)       WANT_SECURITY=1; shift ;;
    --no-security)    WANT_SECURITY=0; shift ;;
    --superpowers)    WANT_SUPERPOWERS=1; shift ;;
    --no-superpowers) WANT_SUPERPOWERS=0; shift ;;
    --unslop)         WANT_UNSLOP=1; shift ;;
    --no-unslop)      WANT_UNSLOP=0; shift ;;
    -h|--help)     sed -n '2,/^# =====/p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1 (use --help)"; exit 1 ;;
  esac
done

PROJECT_ROOT="$(pwd)"
TMP_DIR="$(mktemp -d)"
LOG_DIR="$PROJECT_ROOT/.design-setup-logs"
mkdir -p "$LOG_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

INSTALL_DONE=(); FAILED=()
INSTALL_TOTAL=0; INSTALL_N=0

# -----------------------------------------------------------------------------
# Terminal UI - same palette, panels and menus as the Linux script
# -----------------------------------------------------------------------------
IS_TTY=0; [ -t 1 ] && IS_TTY=1
INPUT_DEV=""
if ( exec </dev/tty ) 2>/dev/null; then INPUT_DEV="/dev/tty"
elif [ -t 0 ]; then INPUT_DEV="/dev/stdin"; fi

if [ "$IS_TTY" = "1" ]; then
  E=$'\033'
  GREEN="${E}[38;5;114m"; YELLOW="${E}[38;5;179m"; RED="${E}[38;5;203m"
  CYAN="${E}[38;5;111m"; ACCENT="${E}[38;5;111m"; MAGENTA="${E}[38;5;141m"
  MUTED="${E}[38;5;244m"; BOLD="${E}[1m"; DIM="${E}[2m"; NC="${E}[0m"
else
  GREEN=""; YELLOW=""; RED=""; CYAN=""; ACCENT=""; MAGENTA=""; MUTED=""; BOLD=""; DIM=""; NC=""
fi

cols() {
  local c
  c="$(tput cols 2>/dev/null || echo 80)"
  case "$c" in ''|*[!0-9]*) c=80 ;; esac
  [ "$c" -lt 60 ] && c=60
  [ "$c" -gt 96 ] && c=96
  echo "$c"
}

ui_clear() { [ "$IS_TTY" = "1" ] && printf '%s[H%s[2J%s[3J' "$E" "$E" "$E"; }

ui_rule() {
  local c i; c=$(cols)
  printf '%s' "$MUTED"
  i=0; while [ $i -lt "$c" ]; do printf '─'; i=$((i + 1)); done
  printf '%s\n' "$NC"
}

ui_panel() { # color title line...
  local color="$1" title="$2"; shift 2
  local c inner fill i line t
  c=$(cols); inner=$((c - 4))
  t=" $title "
  fill=$((c - 3 - ${#t})); [ "$fill" -lt 0 ] && fill=0
  printf '\n%s╭─%s%s' "$color" "$t" "$NC"
  i=0; while [ $i -lt "$fill" ]; do printf '%s─' "$color"; i=$((i + 1)); done
  printf '%s╮%s\n' "$color" "$NC"
  for line in "$@"; do
    [ "${#line}" -gt "$inner" ] && line="${line:0:$inner}"
    printf '%s│%s %-*s %s│%s\n' "$color" "$NC" "$((inner - 2))" "$line" "$color" "$NC"
  done
  printf '%s╰' "$color"
  i=0; while [ $i -lt $((c - 2)) ]; do printf '─'; i=$((i + 1)); done
  printf '╯%s\n' "$NC"
}

ui_kv() { printf '  %s%-14s%s %s\n' "$MUTED" "$1" "$NC" "$2"; }
ok()   { printf '  %s[OK]%s   %s\n' "$GREEN" "$NC" "$1"; }
warn() { printf '  %s[WARN]%s %s\n' "$YELLOW" "$NC" "$1"; }
err()  { printf '  %s[FAIL]%s %s\n' "$RED" "$NC" "$1"; }
info() { printf '  %s%s%s\n' "$MUTED" "$1" "$NC"; }
hint() { printf '  %s%s%s\n' "$CYAN" "$1" "$NC"; }

ui_step() { # n total title
  ui_clear
  printf '\n%s❯%s %sstep %s of %s%s · %s%s%s\n' "$ACCENT" "$NC" "$MUTED" "$1" "$2" "$NC" "$BOLD" "$3" "$NC"
  ui_rule
  echo
}

ui_cover() {
  ui_clear
  ui_panel "$ACCENT" "SETUP SKILLS · macOS" \
    "Design skills, a DESIGN.md and the rules your agent reads." \
    "" \
    "Project: $PROJECT_ROOT" \
    "Nothing is written until you confirm a choice."
  echo
}

ui_pause() {
  [ -z "$INPUT_DEV" ] && return 0
  printf '\n  %spress Enter to continue%s ' "$MUTED" "$NC"
  IFS= read -r _ <"$INPUT_DEV" || true
}

ui_confirm() { # question default(y/n)
  local q="$1" d="${2:-n}" a
  if [ -z "$INPUT_DEV" ]; then [ "$d" = "y" ]; return; fi
  printf '  %s%s%s [%s/%s] ' "$BOLD" "$q" "$NC" "$([ "$d" = y ] && echo Y || echo y)" "$([ "$d" = y ] && echo n || echo N)"
  IFS= read -r a <"$INPUT_DEV" || a=""
  [ -z "$a" ] && a="$d"
  case "$a" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

menu_select() { # title default-index items...
  local title="$1" def="$2"; shift 2
  local count=$# sel="$def" key rest i picked
  if [ "$IS_TTY" != "1" ] || [ -z "$INPUT_DEV" ]; then
    echo "$title"
    i=1; for picked in "$@"; do printf '  %d) %s\n' "$i" "$picked"; i=$((i + 1)); done
    printf 'Choose [1-%d] (default %d): ' "$count" "$((def + 1))"
    IFS= read -r picked </dev/stdin || picked=""
    case "$picked" in ''|*[!0-9]*) MENU_RESULT="$def" ;; *) MENU_RESULT=$((picked - 1)) ;; esac
    return 0
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
        rest=""
        IFS= read -rsn2 -t 1 rest <"$INPUT_DEV" || true
        case "$rest" in
          '[A') [ "$sel" -gt 0 ] && sel=$((sel - 1)) ;;
          '[B') [ "$sel" -lt $((count - 1)) ] && sel=$((sel + 1)) ;;
        esac
        ;;
      '') break ;;
      k|K) [ "$sel" -gt 0 ] && sel=$((sel - 1)) ;;
      j|J) [ "$sel" -lt $((count - 1)) ] && sel=$((sel + 1)) ;;
      q|Q) MENU_RESULT="$def"; return 0 ;;
    esac
  done
  MENU_RESULT="$sel"
}

run_task() { # label logfile command...
  local label="$1" log="$2"; shift 2
  : >"$log"
  "$@" >>"$log" 2>&1 &
  local pid=$! frame=0 frames='|/-\' rc=0
  if [ "$IS_TTY" = "1" ]; then
    while kill -0 "$pid" 2>/dev/null; do
      printf '\r  %s%s%s %s' "$ACCENT" "${frames:$frame:1}" "$NC" "$label"
      frame=$(( (frame + 1) % 4 ))
      sleep 0.15
    done
    printf '\r%*s\r' "$((${#label} + 6))" ''
  else
    echo "  ... $label"
  fi
  wait "$pid" || rc=$?
  if [ "$rc" -eq 0 ]; then
    ok "$label"
  elif [ "$DEBUG" = "1" ]; then
    err "$label"
    tail -n 25 "$log" | sed 's/^/      /'
  else
    err "$label (log: ${log#$PROJECT_ROOT/})"
  fi
  return "$rc"
}

command -v tput >/dev/null 2>&1 || true

# -----------------------------------------------------------------------------
# Prerequisites
# -----------------------------------------------------------------------------
[ "$LIST_ONLY" = "1" ] || ui_cover
ui_step 0 5 "Checking prerequisites"

for cmd in git node npx; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "'$cmd' is not installed (need git + Node.js 18+)."
    hint "Install Node with: brew install node   (or https://nodejs.org)"
    exit 1
  fi
done

NODE_MAJOR="$(node -v 2>/dev/null | sed 's/^v//; s/\..*//')"
if [ "${NODE_MAJOR:-0}" -lt 18 ]; then
  err "Node $(node -v) is too old. The skills CLI needs Node 18+."
  hint "brew install node"
  exit 1
fi
ok "bash ${BASH_VERSION%%(*} | git | node $(node -v)"
info "Project root: $PROJECT_ROOT"

if ! run_task "Reaching github.com" "$LOG_DIR/github-check.log" \
  git ls-remote --heads https://github.com/voltagent/awesome-design-md.git; then
  err "Cannot reach github.com. Check your internet, proxy or firewall."
  exit 1
fi

mkdir -p "$PROJECT_ROOT/.claude/skills" "$PROJECT_ROOT/.agents/skills"

# -----------------------------------------------------------------------------
# Skill helpers
# -----------------------------------------------------------------------------
skill_present() {
  [ -f "$PROJECT_ROOT/.claude/skills/$1/SKILL.md" ] || [ -f "$PROJECT_ROOT/.agents/skills/$1/SKILL.md" ]
}

fallback_install() { # owner/repo [only-folder]
  local repo="$1" only="${2:-}" dest="$TMP_DIR/fb-$(basename "$1")" f dir name target
  warn "Using git fallback for $repo"
  if ! run_task "Downloading $repo" "$LOG_DIR/fallback.log" \
    git clone --depth 1 "https://github.com/$repo.git" "$dest"; then
    return 1
  fi
  local found=0
  while IFS= read -r f; do
    dir="$(dirname "$f")"; name="$(basename "$dir")"
    [ -n "$only" ] && [ "$name" != "$only" ] && continue
    for target in ".claude/skills" ".agents/skills"; do
      mkdir -p "$PROJECT_ROOT/$target/$name"
      cp -R "$dir"/. "$PROJECT_ROOT/$target/$name/"
    done
    ok "Copied skill '$name'"
    found=1
  done < <(find "$dest" -name SKILL.md -not -path "*/node_modules/*" -not -path "*/.git/*")
  [ "$found" -eq 1 ] || { err "No SKILL.md found in $repo"; return 1; }
}

install_skill() { # label expected repo only npx-args...
  local label="$1" expect="$2" repo="$3" only="$4"; shift 4
  INSTALL_N=$((INSTALL_N + 1))
  ui_step "$INSTALL_N" 5 "Installing: $label"
  local log="$LOG_DIR/npx-$(echo "$label" | tr -c 'A-Za-z0-9' '_').log"
  run_task "npx skills add ($label)" "$log" npx --yes skills add "$@" -a claude-code -y || true

  local all_ok=1 e
  local IFS=','
  for e in $expect; do skill_present "$e" || all_ok=0; done
  unset IFS
  if [ "$all_ok" = "1" ]; then
    ok "$label installed (verified: $expect)"
    INSTALL_DONE+=("$label")
  else
    warn "$label NOT found on disk after 'npx skills add' - trying git fallback"
    if fallback_install "$repo" "$only"; then
      INSTALL_DONE+=("$label")
    else
      err "$label failed. Logs: $LOG_DIR"
      FAILED+=("$label")
    fi
  fi
}

# -----------------------------------------------------------------------------
# 1. Design system
# -----------------------------------------------------------------------------
NAMES=(); PATHS=()
print_design_grid() {
  local n=0 i
  for i in "${!NAMES[@]}"; do
    n=$((n + 1))
    printf '  %s%3d%s) %-24s' "$CYAN" "$n" "$NC" "${NAMES[$i]}"
    [ $((n % 3)) -eq 0 ] && echo
  done
  [ $((n % 3)) -ne 0 ] && echo
}

if [ "$SKIP_DESIGN" = "1" ]; then
  warn "Skipping DESIGN.md (--skip-design)"
else
  ui_step 1 5 "Design system"
  if ! run_task "Downloading the design library" "$LOG_DIR/design-md.log" \
    git clone --depth 1 https://github.com/voltagent/awesome-design-md.git "$TMP_DIR/design-md"; then
    err "Could not download the design list. Get one manually: https://getdesign.md/"
    FAILED+=("DESIGN.md")
  else
    while IFS= read -r f; do
      NAMES+=("$(basename "$(dirname "$f")")")
      PATHS+=("$f")
    done < <(find "$TMP_DIR/design-md" -iname "DESIGN.md" -not -path "*/.git/*" | sort)

    if [ "${#NAMES[@]}" -eq 0 ]; then
      err "No DESIGN.md files found in the library. Use https://getdesign.md/"
      FAILED+=("DESIGN.md")
    elif [ "$LIST_ONLY" = "1" ]; then
      ui_clear
      info "Found ${#NAMES[@]} design systems"
      echo
      print_design_grid
      printf '%s\n' "${NAMES[@]}" >"$PROJECT_ROOT/design-list.txt"
      ok "Full list also saved to design-list.txt"
      exit 0
    else
      info "Found ${#NAMES[@]} design systems"
      SELECTED=-1
      if [ -n "$BRAND" ]; then
        i=0
        for name in "${NAMES[@]}"; do
          case "$name" in *"$BRAND"*) SELECTED="$i" ;; esac
          i=$((i + 1))
        done
        [ "$SELECTED" -lt 0 ] && warn "Brand '$BRAND' not found."
      fi
      if [ "$SELECTED" -lt 0 ]; then
        menu_select "Choose a design system" 0 "${NAMES[@]}"
        SELECTED="$MENU_RESULT"
      fi
      if [ -f "$PROJECT_ROOT/DESIGN.md" ]; then
        cp "$PROJECT_ROOT/DESIGN.md" "$PROJECT_ROOT/DESIGN.md.bak"
        warn "Old DESIGN.md saved as DESIGN.md.bak"
      fi
      cp "${PATHS[$SELECTED]}" "$PROJECT_ROOT/DESIGN.md"
      ok "DESIGN.md for '${NAMES[$SELECTED]}' copied to the project root"
    fi
  fi
fi

# -----------------------------------------------------------------------------
# 2-5. Skills
# -----------------------------------------------------------------------------
INSTALL_TOTAL=4
install_skill "Impeccable" "impeccable" "pbakaus/impeccable" "impeccable" pbakaus/impeccable
install_skill "Taste Skill" "design-taste-frontend" "Leonxlnx/taste-skill" "" Leonxlnx/taste-skill
install_skill "Vercel Web Design Guidelines" "web-design-guidelines" "vercel-labs/agent-skills" "web-design-guidelines" \
  https://github.com/vercel-labs/agent-skills --skill web-design-guidelines
install_skill "LP Design Skill" "landing-page-design" "elayadesign/ai-design-skills" "landing-page-design" \
  elayadesign/ai-design-skills --skill landing-page-design
INSTALL_N=0; INSTALL_TOTAL=0

# -----------------------------------------------------------------------------
# Optional packs
# -----------------------------------------------------------------------------
ui_step 4 5 "Optional packs"
ui_panel "$YELLOW" "WARNING: offensive security pack" \
  "About 50-80 red-team skills." \
  "Use them ONLY on systems you own or are authorized to test."
if ui_confirm "Install the Claude-Red security skills?" "${WANT_SECURITY:-n}"; then
  install_skill "Claude-Red security skills" "offensive-advanced-redteam" "SnailSploit/Claude-Red" "" \
    SnailSploit/Claude-Red --skill '*'
else
  ok "Skipped security skills"
fi

if ui_confirm "Install the Superpowers workflow skills?" "${WANT_SUPERPOWERS:-n}"; then
  install_skill "Superpowers skills" "using-superpowers,brainstorming,test-driven-development" "obra/superpowers" "" \
    obra/superpowers --skill '*'
else
  ok "Skipped Superpowers"
fi

if ui_confirm "Install the Unslop skill?" "${WANT_UNSLOP:-n}"; then
  install_skill "Unslop skill" "unslop" "heydamir/unslop" "unslop" heydamir/unslop --skill unslop
else
  ok "Skipped Unslop"
fi

# -----------------------------------------------------------------------------
# Mirror, Playwright MCP
# -----------------------------------------------------------------------------
ui_step 4 5 "Wiring up other agents"
mkdir -p "$PROJECT_ROOT/.agents/skills"
for d in "$PROJECT_ROOT"/.claude/skills/*/; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  if [ ! -f "$PROJECT_ROOT/.agents/skills/$name/SKILL.md" ]; then
    mkdir -p "$PROJECT_ROOT/.agents/skills/$name"
    cp -R "$d". "$PROJECT_ROOT/.agents/skills/$name/" && ok "Mirrored $name"
  fi
done

if [ ! -f "$PROJECT_ROOT/.mcp.json" ]; then
  cat >"$PROJECT_ROOT/.mcp.json" <<'EOF'
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["@playwright/mcp@latest"]
    }
  }
}
EOF
  ok "Created .mcp.json with Playwright MCP"
elif grep -q '"playwright"' "$PROJECT_ROOT/.mcp.json"; then
  ok ".mcp.json already has playwright"
else
  warn ".mcp.json exists - add the playwright server manually"
fi

if command -v claude >/dev/null 2>&1; then
  run_task "Registering Playwright MCP with Claude Code" "$LOG_DIR/claude-mcp.log" \
    claude mcp add playwright npx '@playwright/mcp@latest' || \
    warn "'claude mcp add' failed (maybe already added) - .mcp.json is in place."
fi

run_task "Installing Chromium for Playwright (this can take a few minutes)" \
  "$LOG_DIR/playwright-chromium.log" npx --yes playwright install chromium || \
  warn "Chromium install failed. Run manually: npx playwright install chromium"

# -----------------------------------------------------------------------------
# CLAUDE.md, AGENTS.md, skill-instructions.md
# -----------------------------------------------------------------------------
ui_step 5 5 "Writing agent rules"

RULES_FILE="$TMP_DIR/rules.md"
cat >"$RULES_FILE" <<'EOF'
# Frontend Design Engineering Rules (Score 98/100 Pipeline)

1. DESIGN SYSTEM GROUNDING (Awesome DESIGN.md):
   - Always read ./DESIGN.md before creating or modifying any UI component.
   - Strictly enforce the exact hex colors, typography scale, spacing tokens, border radius, and shadow tokens defined in ./DESIGN.md.

2. ANTI-SLOP GOVERNANCE (Impeccable & Taste-Skill):
   - Never use generic purple-to-blue gradient text headlines.
   - Never place emoji icon tiles above feature headings; use clean SVG icons instead.
   - Run /impeccable audit and /impeccable polish across COMPONENTS, TYPOGRAPHY, and BACKGROUND layers.
   - Respect calibrated Taste parameters: BOLD (Design Variance), MOTION (Motion Intensity), and DENSITY (Visual Density).

3. UX & ACCESSIBILITY AUDIT (Vercel Web Design Guidelines):
   - Every interactive button or close icon must have a minimum hit target of 24x24px (44x44px on mobile touch targets).
   - Never disable browser zoom (user-scalable=no or maximum-scale=1 is strictly forbidden).
   - Every async form submission or action button must display an explicit <Spinner /> loading state while pending.

4. CLOSED-LOOP BROWSER QA (Microsoft Playwright MCP):
   - After building or updating any page, open the live localhost URL using Playwright MCP.
   - Click interactive buttons, take a real browser screenshot (take_screenshot), verify that no close (X) button or CTA overflows its card or overlaps text, and fix all visual bugs before completing the task.
EOF
MARKER="# Frontend Design Engineering Rules (Score 98/100 Pipeline)"
for f in CLAUDE.md AGENTS.md; do
  if [ -f "$PROJECT_ROOT/$f" ] && grep -qF "$MARKER" "$PROJECT_ROOT/$f"; then
    ok "$f already has the rules"
  elif [ -f "$PROJECT_ROOT/$f" ]; then
    { echo; cat "$RULES_FILE"; } >>"$PROJECT_ROOT/$f"; ok "Appended rules to $f"
  else
    cp "$RULES_FILE" "$PROJECT_ROOT/$f"; ok "Created $f"
  fi
done

skill_path() {
  if [ -f "$PROJECT_ROOT/.claude/skills/$1/SKILL.md" ]; then echo ".claude/skills/$1/SKILL.md"
  else echo ".agents/skills/$1/SKILL.md"; fi
}

{
  echo "# skill-instructions.md"
  echo
  echo "> Generated by Setup-Skills on $(date +%Y-%m-%d) on macOS. Re-run the script to refresh this file."
  echo
  cat <<'INSTR'
**AI AGENT: read this whole file at the start of every session in this project, then follow it for ALL work. It stays in force until the user says otherwise.**

## 0. Your operating rules (MANDATORY)

1. Read this file first. Then read `./CLAUDE.md` or `./AGENTS.md` and `./DESIGN.md` (if they exist).
2. Before every task, decide which skills below apply. Open each applicable `SKILL.md` and follow it. Start your reply by naming the skills you are using.
3. Never skip a skill to save time. Never invent skill rules you have not read.
4. If instructions conflict, use this priority: the user's explicit request > `DESIGN.md` (colors, fonts, spacing) > skill instructions > your own defaults. Tell the user when you overrule a skill because of their request.
5. A UI task is NOT finished until it passes the checklist in section 3.
6. If a skill file is missing or unreadable, say so, then continue with best effort.

## 1. Installed skills (open the SKILL.md before using a skill)
INSTR

  for pair in "impeccable:Impeccable" "design-taste-frontend:Taste Skill" \
    "web-design-guidelines:Vercel Web Design Guidelines" "landing-page-design:LP Design Skill" \
    "unslop:Unslop"; do
    name="${pair%%:*}"; label="${pair#*:}"
    if skill_present "$name"; then
      echo "### $label - \`$(skill_path "$name")\`"
      echo "- Open the SKILL.md before using it, then follow its procedure."
      echo
    fi
  done

  if skill_present using-superpowers; then
    echo "### Superpowers workflow skills"
    echo "- Start with \`using-superpowers\`, then use the skill that matches the situation."
    echo "- Habit: plan before code, write tests first, debug systematically, verify before saying done."
    echo
  fi

  cat <<'INSTR'
## 2. Workflow for every UI task

1. **Ground** - read `DESIGN.md`. Use its exact hex colors, type scale, spacing, radius and shadows. Never invent new tokens.
2. **Plan** - state which skills you will use and what you will build (keep it short).
3. **Build** - follow the Taste Skill so the result does not look generic.
4. **Audit and polish** - run Impeccable on COMPONENTS, TYPOGRAPHY and BACKGROUND layers.
5. **Review** - run the Vercel Web Design Guidelines on the code.
6. **Browser QA** - open the live localhost page with Playwright, click the interactive elements, take a real screenshot, and fix every visual bug.
7. **Report** - tell the user what you built, which skills you used, and what you verified.

## 3. Definition of done (check every line before you finish)

- [ ] Colors, fonts and spacing match `DESIGN.md`
- [ ] No purple-to-blue gradient headlines; SVG icons, not emoji tiles above headings
- [ ] Buttons and close icons have at least a 24x24px hit area (44x44px on mobile)
- [ ] Browser zoom is not disabled (`user-scalable=no` / `maximum-scale=1` are forbidden)
- [ ] Every async action shows a loading state (`<Spinner />`) while pending
- [ ] Impeccable audit and polish done; Vercel guidelines review done
- [ ] Screenshot taken in a real browser; no overflow or overlapping text or buttons

## 4. Hard rules

- Always read `./DESIGN.md` before creating or changing any UI component.
- Never use emoji icon tiles above feature headings; use clean SVG icons.
- Never disable browser zoom.
- Never say "done" before section 3 is satisfied.

## 5. Browser QA tools

- Preferred: Playwright MCP (configured in `.mcp.json`). Use its navigate, click and `take_screenshot` tools.
- If MCP is not available, run `npx playwright screenshot http://localhost:3000 shot.png` and inspect the image.
- If the browser is missing, run `npx playwright install chromium`.

## 6. For the human: how to use this file

- Start your agent in this project folder and say: **"Read skill-instructions.md and follow it for everything in this project."**
- To change the design, run `./setup-skills.sh --brand <name>` (the old `DESIGN.md` is kept as `DESIGN.md.bak`), then ask the agent to re-read `DESIGN.md`.
INSTR
} >"$PROJECT_ROOT/skill-instructions.md"
ok "Created skill-instructions.md"

for f in CLAUDE.md AGENTS.md; do
  if ! grep -qF "skill-instructions.md" "$PROJECT_ROOT/$f" 2>/dev/null; then
    { echo; echo "## Skill instructions (MANDATORY)"; echo "At the start of every session, read ./skill-instructions.md and follow it for all work in this project."; } >>"$PROJECT_ROOT/$f"
    ok "Added skill-instructions.md pointer to $f"
  fi
done

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
ui_clear
SUM_ROWS=(); f_ok() { [ -f "$PROJECT_ROOT/$1" ] && echo 1 || echo 0; }; sk() { skill_present "$1" && echo 1 || echo 0; }
srow() { if [ "$1" = "1" ]; then SUM_ROWS+=("[OK]  $2"); else SUM_ROWS+=("[--]  $2 (${3:-not installed})"); fi; }

SUM_ROWS+=("Folder: $PROJECT_ROOT" "")
srow "$(f_ok DESIGN.md)" "DESIGN.md (design system)"
srow "$(f_ok CLAUDE.md)" "CLAUDE.md (agent rules)"
srow "$(f_ok AGENTS.md)" "AGENTS.md (agent rules)"
srow "$(f_ok .mcp.json)" "Playwright MCP (.mcp.json)"
srow "$(f_ok skill-instructions.md)" "skill-instructions.md"
srow "$(sk impeccable)" "Skill: Impeccable"
srow "$(sk design-taste-frontend)" "Skill: Taste Skill"
srow "$(sk web-design-guidelines)" "Skill: Vercel Web Design Guidelines"
srow "$(sk landing-page-design)" "Skill: LP Design (landing page)"
srow "$(sk offensive-advanced-redteam)" "Optional: Claude-Red security skills"
srow "$(sk using-superpowers)" "Optional: Superpowers skills"
srow "$(sk unslop)" "Optional: Unslop skill"
SUM_ROWS+=("" "Total skill folders: $(ls -1 "$PROJECT_ROOT/.claude/skills" 2>/dev/null | wc -l | tr -d ' ')")

SUM_COLOR="$GREEN"; [ "${#FAILED[@]}" -gt 0 ] && SUM_COLOR="$RED"
ui_panel "$SUM_COLOR" "INSTALL REPORT" "${SUM_ROWS[@]}"
echo

if [ "${#FAILED[@]}" -gt 0 ]; then
  err "Some steps failed: ${FAILED[*]}"
  info "Logs are in: $LOG_DIR   (re-run with --debug for live output)"
  exit 1
fi
rm -rf "$LOG_DIR" 2>/dev/null
ui_panel "$CYAN" "ALL DONE - NEXT STEPS" \
  "1. Start your AI agent in this folder" \
  "2. Tell it: Read skill-instructions.md and follow it" \
  "3. Claude Code: try  /impeccable audit"
hint "Guide saved to DESIGN-SKILLS-GUIDE.md"

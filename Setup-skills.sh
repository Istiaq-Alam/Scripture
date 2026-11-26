#!/usr/bin/env bash
# =============================================================================
# Setup-Skills  (setup-design-skills.sh)
# Installs 5 frontend design skills + CLAUDE.md / AGENTS.md into the CURRENT
# project folder. Run it from your project root, in a normal terminal.
#
#   ./setup-design-skills.sh                 # interactive menu: pick a design
#   ./setup-design-skills.sh --brand linear  # pick a design directly
#   ./setup-design-skills.sh --list          # list all designs and exit
#   ./setup-design-skills.sh --skip-design   # skills only, no DESIGN.md
#   ./setup-design-skills.sh --debug         # show full output of every command
#
# Optional extras (the script ASKS you; flags skip the question):
#   --security / --no-security         Claude-Red offensive security skills
#   --superpowers / --no-superpowers   obra/superpowers workflow skills
#   --unslop / --no-unslop             heydamir/unslop (fix AI-looking UI)
# =============================================================================

# --- must run under bash (not sh/dash) ---
if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then exec bash "$0" "$@"; fi
  echo "ERROR: this script needs bash. Run:  bash $0"; exit 1
fi
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  echo "ERROR: bash 4+ required (you have $BASH_VERSION)."; exit 1
fi

set -uo pipefail
export GIT_TERMINAL_PROMPT=0          # never hang waiting for a git password
export CI=1 NO_COLOR=1 FORCE_COLOR=0   # no spinners / color noise from npx tools

BRAND="${BRAND:-}"; SKIP_DESIGN=0; LIST_ONLY=0; DEBUG=0; WANT_SECURITY=""; WANT_SUPERPOWERS=""; WANT_UNSLOP=""
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

# ------------------------------------------------------------------------------
# Terminal detection
# ------------------------------------------------------------------------------
# IS_TTY: stdout is a real terminal (screen can be cleared / animated).
# INPUT_DEV: where prompts read from (tty if possible, else stdin when piped).
IS_TTY=0
[ -t 1 ] && IS_TTY=1

detect_input() {
  INPUT_DEV=""
  if ( exec </dev/tty ) 2>/dev/null; then INPUT_DEV="/dev/tty"
  elif [ -t 0 ]; then INPUT_DEV="/dev/stdin"; fi
}
detect_input

# ------------------------------------------------------------------------------
# Colors
# ------------------------------------------------------------------------------
if [ "$IS_TTY" = "1" ]; then
  GREEN=$'\033[38;5;114m'
  YELLOW=$'\033[38;5;179m'
  RED=$'\033[38;5;203m'
  CYAN=$'\033[38;5;111m'
  ACCENT=$'\033[38;5;111m'
  MAGENTA=$'\033[38;5;141m'
  VIOLET=$'\033[38;5;99m'
  MUTED=$'\033[38;5;244m'
  BORDER=$'\033[38;5;238m'
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  NC=$'\033[0m'
else
  GREEN=''; YELLOW=''; RED=''; CYAN=''; ACCENT=''; MAGENTA=''; VIOLET=''
  MUTED=''; BORDER=''; BOLD=''; DIM=''; NC=''
fi

# Gradient rows for banners (violet -> cyan).
LOGO_TINTS=( 99 105 111 117 111 105 99 )
UI_FRAME_W=""
INSTALL_N=0
INSTALL_TOTAL=0
INSTALL_DONE=()
FAILED=()

cleanup() {
  ui_cursor_show 2>/dev/null || true
  rm -rf "$TMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

# ------------------------------------------------------------------------------
# UI layer - terminal helpers
# ------------------------------------------------------------------------------
# Real terminal size as "rows cols". These helpers run inside $( ), so stdout is
# a pipe and [ -t 1 ] is useless there.
ui_size() {
    local s=""
    s="$( { stty size </dev/tty; } 2>/dev/null || true )"
    case "$s" in
        [0-9]*' '[0-9]*) printf '%s' "$s" ;;
        *) printf '' ;;
    esac
}
ui_width() {
    local s="" w=""
    s="$(ui_size)"
    w="${s#* }"
    case "$w" in ''|*[!0-9]*) w="" ;; esac
    [ "${w:-0}" -gt 0 ] || w="${COLUMNS:-80}"
    case "$w" in ''|*[!0-9]*) w=80 ;; esac
    [ "$w" -gt 100 ] && w=100
    [ "$w" -lt 60 ] && w=60
    printf '%s' "$w"
}
ui_rows() {
    local s="" r=""
    s="$(ui_size)"
    r="${s%% *}"
    case "$r" in ''|*[!0-9]*) r="" ;; esac
    [ "${r:-0}" -gt 0 ] || r="${LINES:-24}"
    case "$r" in ''|*[!0-9]*) r=24 ;; esac
    [ "$r" -lt 10 ] && r=10
    printf '%s' "$r"
}

# Display columns of a string: ANSI escapes stripped, multibyte glyphs counted
# as one cell (${#str} counts bytes and mis-centers block art).
ui_swidth() {
    local s n=""
    s="$(printf '%s' "$1" | sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g')"
    n="$(printf '%s' "$s" | wc -L 2>/dev/null | tr -d ' ')"
    case "$n" in ''|*[!0-9]*) n="$(printf '%s' "$s" | wc -m 2>/dev/null | tr -d ' ')" ;; esac
    printf '%s' "${n:-0}"
}

ui_clear() { if [ "$IS_TTY" = "1" ]; then printf '\033[H\033[2J\033[3J\033[H'; fi; }
ui_cursor_hide() { if [ "$IS_TTY" = "1" ]; then printf '\033[?25l'; fi; }
ui_cursor_show() { if [ "$IS_TTY" = "1" ]; then printf '\033[?25h'; fi; }
ui_sleep() { if [ "$IS_TTY" = "1" ]; then sleep "$1"; fi; }
ui_tint() { if [ "$IS_TTY" = "1" ]; then printf '\033[38;5;%sm' "$1"; fi; }

ui_dashes() { printf '─%.0s' $(seq 1 "$1" 2>/dev/null); }

ui_rule_n() { printf '%b%s%b\n' "$BORDER" "$(ui_dashes "$1")" "$NC"; }
ui_rule() { ui_rule_n "$(ui_width)"; }

ui_center() { # text [color]
    local w pad
    w="$(ui_width)"
    pad=$(( (w - $(ui_swidth "$1")) / 2 ))
    [ "$pad" -lt 0 ] && pad=0
    printf '%*s%b%s%b\n' "$pad" "" "${2:-$NC}" "$1" "$NC"
}

ok()   { printf '  %b✔%b %s\n' "$GREEN" "$NC" "$*"; }
warn() { printf '  %b⚠%b %s\n' "$YELLOW" "$NC" "$*"; }
err()  { printf '  %b✖%b %s\n' "$RED" "$NC" "$*"; }
info() { printf '  %b›%b %s\n' "$ACCENT" "$NC" "$*"; }
hint() { printf '  %b%s%b\n' "$MUTED" "$*" "$NC"; }

# Rounded panel with a colored border; long lines are wrapped to the panel.
ui_panel_c() { # border-color title lines...
    local c="$1" title="$2"; shift 2
    local w inner span left right line seg pad
    w="$(ui_width)"; inner=$((w - 4)); [ "$inner" -lt 40 ] && inner=40

    if [ -n "$title" ]; then
        span=$(( w - 4 - $(ui_swidth "$title") ))
        [ "$span" -lt 2 ] && span=2
        left=$(( span / 2 )); right=$(( span - left ))
        printf '%b╭%s %b%s%b %b%s%b╮%b\n' "$c" "$(ui_dashes "$left")" "$BOLD" "$title" "$NC" "$c" "$(ui_dashes "$right")" "$NC"
    else
        printf '%b╭%s╮%b\n' "$c" "$(ui_dashes $((w - 2)))" "$NC"
    fi

    for line in "$@"; do
        if [ -z "$line" ]; then
            printf '%b│%b%*s%b│%b\n' "$c" "$NC" $((w - 2)) "" "$NC" "$c"
            continue
        fi
        while IFS= read -r seg; do
            pad=$(( inner - $(ui_swidth "$seg") ))
            [ "$pad" -lt 0 ] && pad=0
            printf '%b│%b %s%*s %b│%b\n' "$c" "$NC" "$seg" "$pad" "" "$NC" "$c"
        done < <(printf '%s\n' "$line" | fold -s -w "$inner")
    done

    printf '%b╰%s╯%b\n' "$c" "$(ui_dashes $((w - 2)))" "$NC"
}
ui_panel() { ui_panel_c "$BORDER" "$@"; }
ui_note_panel() { local c="$1" title="$2"; shift 2; ui_panel_c "$c" "$title" "$@"; }

# Centered block art with a per-row gradient; rows can animate in one by one.
ui_banner_art() { # art-key [animate 0|1]
    local key="$1" animate="${2:-0}" line pad max=0 i=0 n frame
    local -a rows=()
    while IFS= read -r line; do
        line="${line%"${line##*[! ]}"}"        # trim trailing spaces
        [ -z "${line// /}" ] && continue        # skip blank spacer lines
        rows+=("$line")
    done < <(figlet_art "$key")
    [ ${#rows[@]} -eq 0 ] && return 0

    for line in "${rows[@]}"; do
        n="$(ui_swidth "$line")"
        [ "$n" -gt "$max" ] && max="$n"
    done
    frame="$(ui_width)"
    [ "$max" -gt "$frame" ] && frame="$max"
    UI_FRAME_W="$frame"

    for line in "${rows[@]}"; do
        pad=$(( (frame - $(ui_swidth "$line")) / 2 )); [ "$pad" -lt 0 ] && pad=0
        printf '%*s%s%s%b\n' "$pad" "" "$(ui_tint "${LOGO_TINTS[$((i % ${#LOGO_TINTS[@]}))]}")" "$line" "$NC"
        [ "$animate" = "1" ] && ui_sleep 0.035
        i=$((i + 1))
    done
}

# Section screen: clears the terminal, shows the section banner, a rule, the
# section title and (during installs) a progress line plus finished ticks.
heading() { # art-key title
    local key="$1" title="$2" line i w pad len label
    ui_clear
    echo ""
    if [ -n "$key" ]; then
        ui_banner_art "$key"
    else
        UI_FRAME_W=""
    fi
    w="${UI_FRAME_W:-$(ui_width)}"
    ui_rule_n "$w"
    ui_center "$title" "$BOLD"

    if [ "$INSTALL_TOTAL" -gt 0 ] && [ "$INSTALL_N" -gt 0 ]; then
        label="INSTALL ${INSTALL_N} OF ${INSTALL_TOTAL}"
        len=$(( (2 * INSTALL_TOTAL - 1) + 2 + ${#label} ))
        pad=$(( (w - len) / 2 )); [ "$pad" -lt 0 ] && pad=0
        printf '%*s' "$pad" ""
        for ((i = 1; i <= INSTALL_TOTAL; i++)); do
            if [ "$i" -lt "$INSTALL_N" ]; then
                printf '%b●%b' "$MUTED" "$NC"
            elif [ "$i" -eq "$INSTALL_N" ]; then
                printf '%b●%b' "$ACCENT" "$NC"
            else
                printf '%b○%b' "$MUTED" "$NC"
            fi
            [ "$i" -lt "$INSTALL_TOTAL" ] && printf ' '
            ui_sleep 0.03
        done
        printf '  %b%s%b\n' "$MUTED" "$label" "$NC"
    fi

    if [ ${#INSTALL_DONE[@]} -gt 0 ]; then
        echo ""
        for line in "${INSTALL_DONE[@]}"; do ok "$line"; done
    fi
    echo ""
}

# Inline sub-section divider (does not clear the screen).
step() {
    local title="$1" w
    w="$(ui_width)"
    echo ""
    printf '  %b%s%b\n' "$BOLD$CYAN" "$title" "$NC"
    printf '  %b%s%b\n' "$BORDER" "$(ui_dashes $((w - 4)))" "$NC"
    echo ""
}

# Pulsing "press enter" prompt; any key continues.
ui_wait_enter() {
    local text="${1:-Press enter to begin}" key="" i=0 rc=0
    local -a frames=( 244 245 249 252 249 245 )
    if [ "$IS_TTY" != "1" ] || [ -z "${INPUT_DEV:-}" ]; then
        printf '  %b%s%b\n' "$MUTED" "$text" "$NC"
        return 0
    fi
    ui_cursor_hide
    while :; do
        printf '\r\033[2K  \033[38;5;%sm%s\033[0m  %b↵%b ' "${frames[$((i % 6))]}" "$text" "$ACCENT" "$NC"
        IFS= read -rsn1 -t 0.12 key <"$INPUT_DEV"; rc=$?
        # rc > 128 means the timeout expired (keep pulsing); anything else is a
        # key press or EOF - either way, stop waiting instead of spinning.
        if [ "$rc" -eq 0 ] || [ "$rc" -le 128 ]; then
            ui_cursor_show
            printf '\r\033[2K'
            return 0
        fi
        i=$((i + 1))
    done
}

# Scrollable, filterable arrow-key menu. Sets MENU_RESULT to the chosen index
# in the original list, or -1 when the user skips with esc.
menu_pick() { # prompt default-index item...
    local prompt="$1" def="$2"; shift 2
    local -a all=( "$@" )
    local -a view=()
    local n=${#all[@]} sel top=0 q="" key rest i idx label lo hi
    local item_rows footer ans

    [ "$n" -eq 0 ] && { MENU_RESULT=-1; return 1; }

    # No usable terminal: numbered list + plain read.
    if [ "$IS_TTY" != "1" ] || [ -z "${INPUT_DEV:-}" ]; then
        printf '%b?%b %s\n' "$ACCENT" "$NC" "$prompt"
        for ((i = 0; i < n; i++)); do printf '  %2d) %s\n' $((i + 1)) "${all[$i]}"; done
        printf '  %b❯%b ' "$ACCENT" "$NC"
        ans=""
        IFS= read -r ans || ans=""
        MENU_RESULT="$def"
        case "$ans" in
            ''|*[!0-9]*) : ;;
            *) [ "$ans" -ge 1 ] && [ "$ans" -le "$n" ] && MENU_RESULT=$((ans - 1)) ;;
        esac
        [ "$MENU_RESULT" -lt 0 ] && MENU_RESULT=0
        [ "$MENU_RESULT" -ge "$n" ] && MENU_RESULT=$((n - 1))
        return 0
    fi

    menu_refilter() {
        view=()
        local j
        for j in "${!all[@]}"; do
            if [ -z "$q" ] || [[ "${all[$j],,}" == *"${q,,}"* ]]; then view+=("$j"); fi
        done
        if [ "${#view[@]}" -eq 0 ]; then
            sel=0; top=0
        else
            [ "$sel" -ge "${#view[@]}" ] && sel=$(( ${#view[@]} - 1 ))
            [ "$sel" -lt 0 ] && sel=0
        fi
    }

    q=""; sel="$def"; [ "$sel" -lt 0 ] && sel=0
    menu_refilter

    item_rows="$n"
    [ "$item_rows" -gt 12 ] && item_rows=12
    [ "$item_rows" -gt $(( $(ui_rows) - 8 )) ] && item_rows=$(( $(ui_rows) - 8 ))
    [ "$item_rows" -lt 3 ] && item_rows=3
    footer=$((item_rows + 1))

    ui_cursor_hide
    printf '%b?\033[0m %b%s%b\n' "$ACCENT" "$BOLD" "$prompt" "$NC"
    printf '  %btype to filter · ↑/↓ move · enter select · esc skip%b\n' "$MUTED" "$NC"

    while :; do
        for ((i = 0; i < item_rows; i++)); do
            idx=$((top + i))
            if [ "$idx" -lt "${#view[@]}" ]; then
                label="${all[${view[$idx]}]}"
                if [ "$idx" -eq "$sel" ]; then
                    printf '\033[2K\033[48;5;238m\033[38;5;252m ❯ %s\033[0m\n' "$label"
                else
                    printf '\033[2K   %s\n' "$label"
                fi
            else
                printf '\033[2K\n'
            fi
        done
        if [ "${#view[@]}" -eq 0 ]; then
            printf '\033[2K  %bnothing matches "%s" · backspace clears%b\n' "$MUTED" "$q" "$NC"
        else
            lo=$((top + 1)); hi=$((top + item_rows))
            [ "$hi" -gt "${#view[@]}" ] && hi=${#view[@]}
            printf '\033[2K  %b%d-%d of %d%s%b\n' "$MUTED" "$lo" "$hi" "${#view[@]}" "${q:+ · filter: $q}" "$NC"
        fi

        key=""
        IFS= read -rsn1 key <"$INPUT_DEV" || key=""
        case "$key" in
            $'\r'|$'\n'|'')
                if [ "${#view[@]}" -gt 0 ]; then break; fi ;;
            $'\e')
                rest=""
                IFS= read -rsn2 -t 0.02 rest <"$INPUT_DEV" || rest=""
                case "$rest" in
                    '[A') [ "${#view[@]}" -gt 0 ] && sel=$((sel - 1)) ;;
                    '[B') [ "${#view[@]}" -gt 0 ] && sel=$((sel + 1)) ;;
                    *)
                        ui_cursor_show
                        printf '\033[%dA\033[J' "$footer"
                        MENU_RESULT=-1
                        printf '  %b−%b %s %b· skipped%b\n' "$MUTED" "$NC" "$prompt" "$MUTED" "$NC"
                        return 0 ;;
                esac ;;
            $'\177'|$'\b')
                q="${q%?}"; menu_refilter; sel=0; top=0 ;;
            *)
                q+="$key"; menu_refilter; sel=0; top=0 ;;
        esac

        if [ "${#view[@]}" -gt 0 ]; then
            [ "$sel" -lt 0 ] && sel=$(( ${#view[@]} - 1 ))
            [ "$sel" -ge "${#view[@]}" ] && sel=0
            [ "$sel" -lt "$top" ] && top="$sel"
            [ "$sel" -ge $((top + item_rows)) ] && top=$((sel - item_rows + 1))
            [ "$top" -lt 0 ] && top=0
        fi
        printf '\033[%dA\033[J' "$footer"
    done

    MENU_RESULT="${view[$sel]}"
    ui_cursor_show
    printf '\033[%dA\033[J' "$footer"
    printf '  %b✔%b %s %b·%b %s\n' "$GREEN" "$NC" "$prompt" "$MUTED" "$NC" "${all[$MENU_RESULT]}"
    return 0
}

# yes/no question. $1 = question, $2 = preset (1 = yes, 0 = no, empty = ask).
# Default answer is NO.
ui_confirm() {
    local q="$1" preset="${2:-}"
    [ "$preset" = "1" ] && return 0
    [ "$preset" = "0" ] && return 1
    detect_input
    if [ -z "$INPUT_DEV" ]; then
        warn "No interactive terminal - skipping this optional step (use its --flag to force)."
        return 1
    fi
    menu_pick "$q" 1 "Yes" "No"
    # "Yes" is index 0, "No" is index 1 (the default).
    [ "$MENU_RESULT" = "0" ]
}

# ------------------------------------------------------------------------------
# Command runner: animated spinner, output to a log, tail on failure
# ------------------------------------------------------------------------------
TASK_LABEL=""
run_logged() { # logname timeout-seconds command...
    local name="$1" secs="$2"; shift 2
    mkdir -p "$LOG_DIR"
    local log="$LOG_DIR/$name.log" rc label="${TASK_LABEL:-$*}"
    local -a tcmd=()
    local -a frames=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )
    command -v timeout >/dev/null 2>&1 && tcmd=(timeout "$secs")

    if [ "$DEBUG" = "1" ]; then
        printf '  %b›%b %s\n' "$ACCENT" "$NC" "$label"
        "${tcmd[@]}" "$@" </dev/null 2>&1 | tee "$log"; rc=${PIPESTATUS[0]}
    elif [ "$IS_TTY" = "1" ]; then
        "${tcmd[@]}" "$@" </dev/null >"$log" 2>&1 &
        local pid=$! i=0
        ui_cursor_hide
        while kill -0 "$pid" 2>/dev/null; do
            printf '\r\033[2K  %b%s%b %s' "$ACCENT" "${frames[$((i % 10))]}" "$NC" "$label"
            i=$((i + 1))
            sleep 0.08
        done
        wait "$pid"; rc=$?
        ui_cursor_show
        printf '\r\033[2K'
        if [ "$rc" -eq 0 ]; then printf '  %b✔%b %s\n' "$GREEN" "$NC" "$label"; fi
    else
        printf '  %b›%b %s\n' "$ACCENT" "$NC" "$label"
        "${tcmd[@]}" "$@" </dev/null >"$log" 2>&1; rc=$?
    fi

    if [ "$rc" -ne 0 ]; then
        [ "$rc" -eq 124 ] && err "Timed out after ${secs}s: $*"
        err "Command failed (exit $rc): $*"
        echo "---- last lines of $log ----"; tail -n 12 "$log"; echo "----------------------------"
    fi
    TASK_LABEL=""
    return "$rc"
}
run_task() { # label logname timeout command...
    local label="$1"; shift
    TASK_LABEL="$label"
    run_logged "$@"
}

# ------------------------------------------------------------------------------
# figlet-style ASCII headings (pre-rendered, no figlet install needed)
# ------------------------------------------------------------------------------
figlet_art() {
  case "$1" in
    INSTRUCTIONS)
cat <<'ART_EOF'
 ___ _   _ ____ _____ ____  _   _  ____ _____ ___ ___  _   _ ____
|_ _| \ | / ___|_   _|  _ \| | | |/ ___|_   _|_ _/ _ \| \ | / ___|
 | ||  \| \___ \ | | | |_) | | | | |     | |  | | | | |  \| \___ \
 | || |\  |___) || | |  _ <| |_| | |___  | |  | | |_| | |\  |___) |
|___|_| \_|____/ |_| |_| \_\\___/ \____| |_| |___\___/|_| \_|____|

ART_EOF
    ;;
    LPDESIGN)
cat <<'ART_EOF'
 _     ____    ____            _               ____  _    _ _ _
| |   |  _ \  |  _ \  ___  ___(_) __ _ _ __   / ___|| | _(_) | |
| |   | |_) | | | | |/ _ \/ __| |/ _` | '_ \  \___ \| |/ / | | |
| |___|  __/  | |_| |  __/\__ \ | (_| | | | |  ___) |   <| | | |
|_____|_|     |____/ \___||___/_|\__, |_| |_| |____/|_|\_\_|_|_|
                                 |___/
ART_EOF
    ;;
    UNSLOP)
cat <<'ART_EOF'
 _   _ _   _ ____  _     ___  ____
| | | | \ | / ___|| |   / _ \|  _ \
| | | |  \| \___ \| |  | | | | |_) |
| |_| | |\  |___) | |__| |_| |  __/
 \___/|_| \_|____/|_____\___/|_|

ART_EOF
    ;;
    SETUP)
cat <<'ART_EOF'
 ____       _                    ____  _    _ _ _
/ ___|  ___| |_ _   _ _ __      / ___|| | _(_) | |___
\___ \ / _ \ __| | | | '_ \ ____\___ \| |/ / | | / __|
 ___) |  __/ |_| |_| | |_) |_____|__) |   <| | | \__ \
|____/ \___|\__|\__,_| .__/     |____/|_|\_\_|_|_|___/
                     |_|
ART_EOF
    ;;
    DESIGN)
cat <<'ART_EOF'
 ____  _____ ____ ___ ____ _   _   ______   ______ _____ _____ __  __
|  _ \| ____/ ___|_ _/ ___| \ | | / ___\ \ / / ___|_   _| ____|  \/  |
| | | |  _| \___ \| | |  _|  \| | \___ \\ V /\___ \ | | |  _| | |\/| |
| |_| | |___ ___) | | |_| | |\  |  ___) || |  ___) || | | |___| |  | |
|____/|_____|____/___\____|_| \_| |____/ |_| |____/ |_| |_____|_|  |_|

ART_EOF
    ;;
    IMPECCABLE)
cat <<'ART_EOF'
 ___ __  __ ____  _____ ____ ____    _    ____  _     _____
|_ _|  \/  |  _ \| ____/ ___/ ___|  / \  | __ )| |   | ____|
 | || |\/| | |_) |  _|| |  | |     / _ \ |  _ \| |   |  _|
 | || |  | |  __/| |__| |__| |___ / ___ \| |_) | |___| |___
|___|_|  |_|_|   |_____\____\____/_/   \_\____/|_____|_____|

ART_EOF
    ;;
    TASTE)
cat <<'ART_EOF'
 _____  _    ____ _____ _____   ____  _  _____ _     _
|_   _|/ \  / ___|_   _| ____| / ___|| |/ /_ _| |   | |
  | | / _ \ \___ \ | | |  _|   \___ \| ' / | || |   | |
  | |/ ___ \ ___) || | | |___   ___) | . \ | || |___| |___
  |_/_/   \_\____/ |_| |_____| |____/|_|\_\___|_____|_____|

ART_EOF
    ;;
    VERCEL)
cat <<'ART_EOF'
__     _______ ____   ____ _____ _
\ \   / / ____|  _ \ / ___| ____| |
 \ \ / /|  _| | |_) | |   |  _| | |
  \ V / | |___|  _ <| |___| |___| |___
   \_/  |_____|_| \_\\____|_____|_____|

ART_EOF
    ;;
    PLAYWRIGHT)
cat <<'ART_EOF'
 ____  _        _ __   ____        ______  ___ ____ _   _ _____
|  _ \| |      / \\ \ / /\ \      / /  _ \|_ _/ ___| | | |_   _|
| |_) | |     / _ \\ V /  \ \ /\ / /| |_) || | |  _| |_| | | |
|  __/| |___ / ___ \| |    \ V  V / |  _ < | | |_| |  _  | | |
|_|   |_____/_/   \_\_|     \_/\_/  |_| \_\___\____|_| |_| |_|

ART_EOF
    ;;
    SECURITY)
cat <<'ART_EOF'
 ____  _____ ____ _   _ ____  ___ _______   __
/ ___|| ____/ ___| | | |  _ \|_ _|_   _\ \ / /
\___ \|  _|| |   | | | | |_) || |  | |  \ V /
 ___) | |__| |___| |_| |  _ < | |  | |   | |
|____/|_____\____|\___/|_| \_\___| |_|   |_|

ART_EOF
    ;;
    SUPERPOWERS)
cat <<'ART_EOF'
 ____  _   _ ____  _____ ____  ____   _____        _______ ____  ____
/ ___|| | | |  _ \| ____|  _ \|  _ \ / _ \ \      / / ____|  _ \/ ___|
\___ \| | | | |_) |  _| | |_) | |_) | | | \ \ /\ / /|  _| | |_) \___ \
 ___) | |_| |  __/| |___|  _ <|  __/| |_| |\ V  V / | |___|  _ < ___) |
|____/ \___/|_|   |_____|_| \_\_|    \___/  \_/\_/  |_____|_| \_\____/

ART_EOF
    ;;
    USAGE)
cat <<'ART_EOF'
 _   _  _____        __  _____ ___    _   _ ____  _____
| | | |/ _ \ \      / / |_   _/ _ \  | | | / ___|| ____|
| |_| | | | \ \ /\ / /    | || | | | | | | \___ \|  _|
|  _  | |_| |\ V  V /     | || |_| | | |_| |___) | |___
|_| |_|\___/  \_/\_/      |_| \___/   \___/|____/|_____|

ART_EOF
    ;;
  esac
}

key_for() {
  case "$1" in
    *LP\ Design*) echo LPDESIGN ;; *Unslop*) echo UNSLOP ;; *Impeccable*) echo IMPECCABLE ;; *Taste*) echo TASTE ;; *Vercel*) echo VERCEL ;;
    *Claude-Red*|*security*) echo SECURITY ;; *Superpowers*) echo SUPERPOWERS ;; *) echo "" ;;
  esac
}

# ------------------------------------------------------------------------------
# Cover screen
# ------------------------------------------------------------------------------
ui_cover() {
  local rows
  rows="$(ui_rows)"
  ui_clear
  echo ""
  ui_banner_art SETUP 1
  ui_center "design + engineering skills installer" "$MUTED"
  echo ""
  if [ "$rows" -lt 24 ]; then
    ui_center "5 skills · DESIGN.md · Playwright MCP" "$MUTED"
  else
    ui_panel "WHAT THIS DOES" \
      "Installs 5 frontend design skills into .claude/skills, mirrors them" \
      "into .agents/skills, writes DESIGN.md, CLAUDE.md / AGENTS.md and a" \
      "skill-instructions.md file your AI agent reads at session start." \
      "" \
      "Optional packs: Claude-Red security, Superpowers, Unslop."
    echo ""
    ui_center "Project: ${PROJECT_ROOT}" "$MUTED"
  fi
  echo ""
  detect_input
  ui_wait_enter "Press enter to begin"
  echo ""
}

# ------------------------------------------------------------------------------
# skill helpers (unchanged behaviour)
# ------------------------------------------------------------------------------
skill_present() {   # $1 = skill folder name -> true if it has a SKILL.md somewhere in the project
  [ -f "$PROJECT_ROOT/.claude/skills/$1/SKILL.md" ] || [ -f "$PROJECT_ROOT/.agents/skills/$1/SKILL.md" ]
}

# git fallback: clone repo, copy every folder containing SKILL.md
# usage: fallback_install <owner/repo> [only-folder-name]
fallback_install() {
  local repo="$1" only="${2:-}" dest="$TMP_DIR/fb-$(basename "$1")"
  warn "Using git fallback for $repo"
  run_task "Downloading $repo" "fallback-$(basename "$repo")" 120 git clone --depth 1 "https://github.com/$repo.git" "$dest" || return 1
  local found=0 f dir name target
  while IFS= read -r f; do
    dir="$(dirname "$f")"; name="$(basename "$dir")"
    [ -n "$only" ] && [ "$name" != "$only" ] && continue
    for target in ".claude/skills" ".agents/skills"; do
      mkdir -p "$PROJECT_ROOT/$target/$name"
      cp -r "$dir"/. "$PROJECT_ROOT/$target/$name/"
    done
    ok "Copied skill '$name'"
    found=1
  done < <(find "$dest" -name SKILL.md -not -path "*/node_modules/*" -not -path "*/.git/*")
  [ "$found" -eq 1 ] || { err "No SKILL.md found in $repo${only:+ (looking for '$only')}"; return 1; }
}

# usage: install_skill <label> <expected-folder-name(s) comma-sep> <fallback-repo> <fallback-only> <npx source args...>
install_skill() {
  local label="$1" expect="$2" repo="$3" only="$4"; shift 4
  heading "$(key_for "$label")" "Installing: $label"
  run_task "Running npx skills add" "npx-$(echo "$label" | tr -c 'A-Za-z0-9' '_')" 240 npx --yes skills add "$@" -a claude-code -y
  local all_ok=1 e
  IFS=',' read -ra EXP <<< "$expect"
  for e in "${EXP[@]}"; do skill_present "$e" || all_ok=0; done
  if [ "$all_ok" -eq 1 ]; then
    ok "$label installed (verified: $expect)"
    INSTALL_DONE+=("$label")
  else
    warn "$label NOT found on disk after 'npx skills add' - trying git fallback"
    if fallback_install "$repo" "$only"; then
      ok "$label installed via fallback"
      INSTALL_DONE+=("$label")
    else
      err "$label FAILED. Log: $LOG_DIR/ - or install manually from its GitHub page."
      FAILED+=("$label")
    fi
  fi
}

# ------------------------------------------------------------------------------
# 0. Cover + prerequisites
# ------------------------------------------------------------------------------
[ "$LIST_ONLY" = "1" ] || ui_cover

heading "" "Checking prerequisites"
hint "git, Node.js 18+ and access to github.com"
echo ""

for cmd in git node npx; do
  command -v "$cmd" >/dev/null 2>&1 || { err "'$cmd' is not installed (need git + Node.js 18+)."; exit 1; }
done
NODE_MAJOR="$(node -v | sed 's/^v//; s/\..*//')"
if [ "${NODE_MAJOR:-0}" -lt 18 ]; then
  err "Node $(node -v) is too old. The skills CLI needs Node 18+. Update Node and re-run."; exit 1
fi
ok "bash $BASH_VERSION | git | node $(node -v)"
info "Project root: $PROJECT_ROOT"

# quick internet check (GitHub)
if ! run_task "Reaching github.com" "github-check" 60 \
  git ls-remote --heads https://github.com/voltagent/awesome-design-md.git; then
  err "Cannot reach github.com. Check your internet / proxy / firewall (git ls-remote failed)."
  exit 1
fi
ok "GitHub reachable"

[ "$LIST_ONLY" = "1" ] || mkdir -p "$PROJECT_ROOT/.claude/skills" "$PROJECT_ROOT/.agents/skills"

# ------------------------------------------------------------------------------
# 1. Design System
# ------------------------------------------------------------------------------
heading DESIGN "1/5 Design System - choose your design"

print_design_grid() {
  local n=0 i
  for i in "${!NAMES[@]}"; do
    n=$((n + 1))
    printf '  %b%3d%b) %-24s' "$CYAN" "$n" "$NC" "${NAMES[$i]}"
    [ $((n % 3)) -eq 0 ] && echo
  done
  [ $((n % 3)) -ne 0 ] && echo
}

if [ "$SKIP_DESIGN" = "1" ]; then
  warn "Skipping DESIGN.md (--skip-design)"
else
  if ! run_task "Downloading the design library" "clone-design-md" 120 \
    git clone --depth 1 https://github.com/voltagent/awesome-design-md.git "$TMP_DIR/design-md"; then
    err "Could not download the design list. Get a DESIGN.md manually: https://getdesign.md/"
    FAILED+=("DESIGN.md")
  else
    NAMES=(); PATHS=()
    while IFS= read -r f; do
      NAMES+=("$(basename "$(dirname "$f")")"); PATHS+=("$f")
    done < <(find "$TMP_DIR/design-md" -iname "DESIGN.md" -not -path "*/.git/*" | sort)

    if [ "${#NAMES[@]}" -eq 0 ]; then
      err "Repo downloaded but no DESIGN.md files found (layout changed?). Use https://getdesign.md/"
      FAILED+=("DESIGN.md")
    elif [ "$LIST_ONLY" = "1" ]; then
      ui_rule
      info "Found ${#NAMES[@]} design systems"
      echo ""
      print_design_grid
      echo ""
      printf '%s\n' "${NAMES[@]}" > "$PROJECT_ROOT/design-list.txt"
      ok "Full list also saved to design-list.txt"
      exit 0
    else
      info "Found ${#NAMES[@]} design systems"

      SELECTED=-1
      resolve() {   # $1 = text/number -> sets SELECTED (exact, number, then unique partial)
        local q="$1" i hits=()
        SELECTED=-1
        if [[ "$q" =~ ^[0-9]+$ ]] && [ "$q" -ge 1 ] && [ "$q" -le "${#NAMES[@]}" ]; then SELECTED=$((q-1)); return; fi
        for i in "${!NAMES[@]}"; do [ "${NAMES[$i],,}" == "${q,,}" ] && { SELECTED="$i"; return; }; done
        for i in "${!NAMES[@]}"; do [[ "${NAMES[$i],,}" == *"${q,,}"* ]] && hits+=("$i"); done
        if [ "${#hits[@]}" -eq 1 ]; then SELECTED="${hits[0]}"
        elif [ "${#hits[@]}" -gt 1 ]; then
          warn "'$q' matches several: $(for h in "${hits[@]}"; do printf '%s ' "${NAMES[$h]}"; done)"
        fi
      }

      if [ -n "$BRAND" ]; then
        resolve "$BRAND"; [ "$SELECTED" -lt 0 ] && warn "Brand '$BRAND' not found / ambiguous."
      fi

      if [ "$SELECTED" -lt 0 ]; then
        detect_input
        if [ -n "$INPUT_DEV" ]; then
          menu_pick "Choose a design system" 0 "${NAMES[@]}"
          SELECTED="$MENU_RESULT"
        else
          warn "No interactive terminal available, so I can't show the picker."
          echo ""
          print_design_grid
          echo ""
          warn "Pick one above and run:  ./setup-design-skills.sh --brand <name>"
        fi
      fi

      if [ "$SELECTED" -ge 0 ]; then
        [ -f "$PROJECT_ROOT/DESIGN.md" ] && { cp "$PROJECT_ROOT/DESIGN.md" "$PROJECT_ROOT/DESIGN.md.bak"; warn "Old DESIGN.md saved as DESIGN.md.bak"; }
        cp "${PATHS[$SELECTED]}" "$PROJECT_ROOT/DESIGN.md"
        ok "DESIGN.md for '${NAMES[$SELECTED]}' copied to project root"
      else
        warn "No DESIGN.md chosen. Re-run with --brand <name> any time."
      fi
    fi
  fi
fi

# ------------------------------------------------------------------------------
# 2-5. Skills
# ------------------------------------------------------------------------------
INSTALL_TOTAL=4
INSTALL_N=1; install_skill "2/5 Impeccable"  "impeccable" "pbakaus/impeccable" "impeccable" pbakaus/impeccable
INSTALL_N=2; install_skill "3/5 Taste Skill" "design-taste-frontend" "Leonxlnx/taste-skill" "" Leonxlnx/taste-skill
INSTALL_N=3; install_skill "4/5 Vercel Web Design Guidelines" "web-design-guidelines" "vercel-labs/agent-skills" "web-design-guidelines" \
  https://github.com/vercel-labs/agent-skills --skill web-design-guidelines
INSTALL_N=4; install_skill "LP Design Skill - Landing page design skill" "landing-page-design" "elayadesign/ai-design-skills" "landing-page-design" \
  elayadesign/ai-design-skills --skill landing-page-design
INSTALL_TOTAL=0
INSTALL_N=0

# ------------------------------------------------------------------------------
# OPTIONAL A: Claude-Red security skills
# ------------------------------------------------------------------------------
heading SECURITY "Optional: security skills (SnailSploit/Claude-Red)"
ui_note_panel "$YELLOW" "WARNING: offensive security / red-team skill pack" \
  "~50-80 skills: pentesting, exploitation, EDR evasion..." \
  "Use ONLY on systems you own or are authorized to test." \
  "Skills run with your agent's full permissions and add" \
  "to the skill list it loads. Install only if needed."
echo ""
if ui_confirm "Install the Claude-Red security skills?" "$WANT_SECURITY"; then
  install_skill "Claude-Red security skills" "offensive-advanced-redteam" "SnailSploit/Claude-Red" "" \
    SnailSploit/Claude-Red --skill '*'
else
  ok "Skipped security skills"
fi

# ------------------------------------------------------------------------------
# OPTIONAL B: Superpowers
# ------------------------------------------------------------------------------
heading SUPERPOWERS "Optional: Superpowers workflow skills (obra/superpowers)"
ui_note_panel "$MAGENTA" "Superpowers (obra/superpowers)" \
  "15 engineering-workflow skills: brainstorming," \
  "writing-plans, test-driven-development," \
  "systematic-debugging, code review, git worktrees..."
echo ""
if ui_confirm "Install the Superpowers skills?" "$WANT_SUPERPOWERS"; then
  install_skill "Superpowers skills" "using-superpowers,brainstorming,test-driven-development" "obra/superpowers" "" \
    obra/superpowers --skill '*'
  command -v claude >/dev/null 2>&1 && \
    hint "Tip: inside Claude Code you can also install the full plugin (adds hooks):  /plugin install superpowers@claude-plugins-official"
else
  ok "Skipped Superpowers"
fi

# ------------------------------------------------------------------------------
# OPTIONAL C: Unslop
# ------------------------------------------------------------------------------
heading UNSLOP "Optional: Unslop skill (heydamir/unslop)"
ui_note_panel "$GREEN" "Unslop (heydamir/unslop)" \
  "Turns vibecoded, AI-looking UI into a designed interface:" \
  "finds the slop (purple gradients, glows, emoji labels)," \
  "sets a direction, fixes it pass by pass. Use: /unslop"
echo ""
if ui_confirm "Install the Unslop skill?" "$WANT_UNSLOP"; then
  install_skill "Unslop skill" "unslop" "heydamir/unslop" "unslop" \
    heydamir/unslop --skill unslop
else
  ok "Skipped Unslop"
fi

# ------------------------------------------------------------------------------
# Mirror skills into .agents/skills (used by many other coding agents)
# ------------------------------------------------------------------------------
step "Mirroring skills to .agents/skills for other agents"
mkdir -p "$PROJECT_ROOT/.agents/skills"
for d in "$PROJECT_ROOT"/.claude/skills/*/; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  if [ ! -f "$PROJECT_ROOT/.agents/skills/$name/SKILL.md" ]; then
    mkdir -p "$PROJECT_ROOT/.agents/skills/$name"
    cp -rL "$d". "$PROJECT_ROOT/.agents/skills/$name/" && ok "Mirrored $name"
  fi
done

# ------------------------------------------------------------------------------
# 5. Playwright MCP
# ------------------------------------------------------------------------------
heading PLAYWRIGHT "5/5 Playwright MCP"
if [ ! -f "$PROJECT_ROOT/.mcp.json" ]; then
  cat > "$PROJECT_ROOT/.mcp.json" <<'EOF'
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
  warn ".mcp.json exists - add manually: \"playwright\": { \"command\": \"npx\", \"args\": [\"@playwright/mcp@latest\"] }"
fi

if command -v claude >/dev/null 2>&1; then
  run_task "Registering Playwright MCP with Claude Code" "claude-mcp-add" 60 \
      claude mcp add playwright npx '@playwright/mcp@latest' \
    && ok "Registered Playwright MCP with Claude Code" \
    || warn "'claude mcp add' failed (maybe already added) - .mcp.json is in place."
fi

echo ""
run_task "Installing Chromium for Playwright (this can take a few minutes)" "playwright-chromium" 600 \
    npx --yes playwright install chromium \
  && ok "Chromium installed" \
  || warn "Chromium install failed. Run manually: npx playwright install chromium"

# ------------------------------------------------------------------------------
# 6. CLAUDE.md / AGENTS.md
# ------------------------------------------------------------------------------
step "Writing Frontend Architect rules"
MARKER="# Frontend Design Engineering Rules (Score 98/100 Pipeline)"
RULES_FILE="$TMP_DIR/rules.md"
cat > "$RULES_FILE" <<'EOF'
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
for f in CLAUDE.md AGENTS.md; do
  if [ -f "$PROJECT_ROOT/$f" ] && grep -qF "$MARKER" "$PROJECT_ROOT/$f"; then ok "$f already has the rules"
  elif [ -f "$PROJECT_ROOT/$f" ]; then { echo; cat "$RULES_FILE"; } >> "$PROJECT_ROOT/$f"; ok "Appended rules to $f"
  else cp "$RULES_FILE" "$PROJECT_ROOT/$f"; ok "Created $f"; fi
done

# ------------------------------------------------------------------------------
# 7. skill-instructions.md (the file you tell your AI agent to read)
# ------------------------------------------------------------------------------
heading INSTRUCTIONS "Generating skill-instructions.md"
INSTR_FILE="$PROJECT_ROOT/skill-instructions.md"

skill_path() {   # relative path of a skill's SKILL.md (prefers .claude, else .agents)
  if [ -f "$PROJECT_ROOT/.claude/skills/$1/SKILL.md" ]; then echo ".claude/skills/$1/SKILL.md"
  else echo ".agents/skills/$1/SKILL.md"; fi
}
skill_desc() {   # short description from the SKILL.md front matter (cut at a word boundary)
  local f d
  f="$PROJECT_ROOT/$(skill_path "$1")"
  d="$(awk '/^---[ \t]*$/{c++; next} c==1 && /^description:/{sub(/^description:[ \t]*/,""); gsub(/^"|"$/,""); gsub(/\047/,""); print; exit}' "$f" 2>/dev/null)"
  case "$d" in ""|">"|"|"|">-"|"|-") d="see its SKILL.md" ;; esac
  if [ "${#d}" -gt 95 ]; then d="${d:0:95}"; d="${d% *}..."; fi
  echo "$d"
}

{
echo "# skill-instructions.md"
echo
echo "> Generated by Setup-Skills on $(date +%Y-%m-%d). Re-run the script to refresh this file."
echo
cat <<'INSTR_EOF'
**AI AGENT: read this whole file at the start of every session in this project, then follow it for ALL work. It stays in force until the user says otherwise.**

## 0. Your operating rules (MANDATORY)

1. Read this file first. Then read `./CLAUDE.md` or `./AGENTS.md` and `./DESIGN.md` (if they exist).
2. Before every task, decide which skills below apply. Open each applicable `SKILL.md` and follow it. Start your reply by naming the skills you are using.
3. Never skip a skill to save time. Never invent skill rules you have not read.
4. If instructions conflict, use this priority: the user's explicit request > `DESIGN.md` (colors, fonts, spacing) > skill instructions > your own defaults. Tell the user when you overrule a skill because of their request.
5. A UI task is NOT finished until it passes the checklist in section 3.
6. If a skill file is missing or unreadable, say so, then continue with best effort.

INSTR_EOF

echo "## 1. Installed skills (open the SKILL.md before using a skill)"
echo
if skill_present impeccable; then
  echo "### Impeccable - \`$(skill_path impeccable)\`"
  echo "- Use for: critiquing, auditing, polishing, simplifying or improving any frontend UI."
  echo "- Commands: \`/impeccable audit\`, then \`/impeccable polish\`. If you have no slash commands, open the SKILL.md and apply its audit and polish procedure yourself."
  echo
fi
if skill_present design-taste-frontend; then
  echo "### Taste Skill - \`$(skill_path design-taste-frontend)\`"
  echo "- Use for: building or redesigning pages so they do not look generic or AI-made."
  echo "- Respect the Taste dials: BOLD (design variance), MOTION (motion intensity), DENSITY (visual density). Ask the user for values if they are not set."
  echo
fi
if skill_present web-design-guidelines; then
  echo "### Vercel Web Design Guidelines - \`$(skill_path web-design-guidelines)\`"
  echo "- Use for: reviewing UI code for accessibility, UX and interaction quality. Run it before you call any UI task done."
  echo
fi
if skill_present landing-page-design; then
  echo "### LP Design Skill (AI-Design Skills: landing-page-design) - \`$(skill_path landing-page-design)\`"
  echo "- Use for: ANY landing page, marketing site, web UI, page section, component or prototype, even if the user does not mention design or conversion."
  echo "- You MUST open this SKILL.md and follow it BEFORE choosing page sections, headlines, CTAs, fonts, font sizes, spacing, border radii, background colors, icons or transitions."
  echo "- Work through Part A first (intake questions, page structure, layout, conversion copy, SEO), then Part B (the strict visual system: typography, spacing, radius, backgrounds, hero layout, icons, motion)."
  echo "- Rule: one offer, one audience, one primary action per landing page."
  echo "- If \`DESIGN.md\` exists, its brand colors and fonts win; still follow this skill for structure, copy and every other visual rule."
  echo
fi
if skill_present unslop; then
  echo "### Unslop - \`$(skill_path unslop)\`"
  echo "- Use for: cleaning up vibecoded, AI-looking UI (purple gradients, glows, gradient text, emoji labels, \"New\" badges, glossy blobs, pulsing elements, uneven spacing) and redesigning a screen so it stops looking AI-generated."
  echo "- Run it when the user says unslop, polish, clean up, or when a finished screen still shows those tells. Claude Code: \`/unslop\`. Codex: \`\$unslop\`. Other agents: open the SKILL.md and follow its passes."
  echo "- It works in order: find the slop, set a direction from the product, then fix spacing, color, icons, copy, type, layout, details, visuals and motion."
  echo "- Live-site snapshots use Playwright (already set up). Story videos also need ffmpeg on the PATH (optional)."
  echo "- If \`DESIGN.md\` exists, keep its brand colors and fonts while unslopping."
  echo
fi
if skill_present using-superpowers; then
  echo "### Superpowers workflow skills"
  echo "- Start with \`using-superpowers\`, then use the skill that matches the situation:"
  for n in using-superpowers brainstorming writing-plans executing-plans test-driven-development systematic-debugging requesting-code-review receiving-code-review verification-before-completion subagent-driven-development dispatching-parallel-agents using-git-worktrees finishing-a-development-branch; do
    skill_present "$n" && echo "  - \`$n\` - $(skill_desc "$n") (\`$(skill_path "$n")\`)"
  done
  echo "- Habit: plan before code (brainstorming, writing-plans), write tests first, debug systematically, verify before saying done."
  echo
fi
if skill_present offensive-advanced-redteam; then
  SEC_COUNT="$(ls -d "$PROJECT_ROOT"/.claude/skills/offensive-* 2>/dev/null | wc -l | tr -d ' ')"
  echo "### Security skills (\`offensive-*\`, $SEC_COUNT installed) - SAFETY RULES"
  echo "- These are offensive-security skills. Use them ONLY for systems the user owns or is explicitly authorized to test (own lab, CTF, scoped engagement)."
  echo "- Before using any \`offensive-*\` skill, ask the user to confirm the target and that they have authorization. If they do not confirm, do not proceed."
  echo "- Never run them against third-party or unknown systems. Never use them for anything unrelated to authorized security work."
  echo
fi

cat <<'INSTR_EOF'
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
- If MCP is not available, run `npx playwright screenshot http://localhost:3000 shot.png` and inspect the image. If the browser is missing, run `npx playwright install chromium`.

## 6. For the human: how to use this file

- Start your agent in this project folder and say: **"Read skill-instructions.md and follow it for everything in this project."**
- Then give normal tasks, for example: "Build a pricing page", "Audit and polish the dashboard", "Review this component for accessibility".
- To change the design, run `./setup-design-skills.sh --brand <name>` (the old `DESIGN.md` is kept as `DESIGN.md.bak`), then ask the agent to re-read `DESIGN.md`.
- If the agent seems to forget the rules, repeat the sentence above.
INSTR_EOF
} > "$INSTR_FILE"
ok "Created skill-instructions.md"

# make the agent rules files point to it, so agents that read CLAUDE.md / AGENTS.md find it automatically
for f in CLAUDE.md AGENTS.md; do
  if ! grep -qF "skill-instructions.md" "$PROJECT_ROOT/$f" 2>/dev/null; then
    { echo; echo "## Skill instructions (MANDATORY)"; echo "At the start of every session, read ./skill-instructions.md and follow it for all work in this project."; } >> "$PROJECT_ROOT/$f"
    ok "Added skill-instructions.md pointer to $f"
  fi
done

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
heading "" "SUMMARY"
SUM_COLOR="$GREEN"; [ "${#FAILED[@]}" -gt 0 ] && SUM_COLOR="$RED"
SUMMARY_ROWS=()
srow() {   # $1 = 1/0, $2 = label, $3 = text when missing (default: MISSING)
  if [ "$1" = "1" ]; then SUMMARY_ROWS+=("[OK]  $2"); else SUMMARY_ROWS+=("[--]  $2 (${3:-MISSING})"); fi
}
f_ok() { [ -f "$PROJECT_ROOT/$1" ] && echo 1 || echo 0; }
sk()   { skill_present "$1" && echo 1 || echo 0; }

SUMMARY_ROWS+=("Folder: ${PROJECT_ROOT}")
SUMMARY_ROWS+=("")
srow "$(f_ok DESIGN.md)"  "DESIGN.md (design system)" "not installed"
srow "$(f_ok CLAUDE.md)"  "CLAUDE.md (agent rules)"
srow "$(f_ok AGENTS.md)"  "AGENTS.md (agent rules)"
srow "$(f_ok .mcp.json)"  "Playwright MCP (.mcp.json)"
srow "$(f_ok skill-instructions.md)" "skill-instructions.md (tell your agent to read it)"
srow "$(sk impeccable)"             "Skill: Impeccable"
srow "$(sk design-taste-frontend)"  "Skill: Taste Skill"
srow "$(sk web-design-guidelines)"  "Skill: Vercel Web Design Guidelines"
srow "$(sk landing-page-design)"  "Skill: LP Design (landing page)"
srow "$(sk offensive-advanced-redteam)" "Optional: Claude-Red security skills" "not installed"
srow "$(sk using-superpowers)"          "Optional: Superpowers skills" "not installed"
srow "$(sk unslop)"                     "Optional: Unslop skill" "not installed"
SUMMARY_ROWS+=("")
SUMMARY_ROWS+=("Total skill folders: $(ls -1 .claude/skills 2>/dev/null | wc -l | tr -d ' ')")
ui_panel_c "$SUM_COLOR" "INSTALL REPORT" "${SUMMARY_ROWS[@]}"

if [ "${#FAILED[@]}" -gt 0 ]; then
  echo; err "Some steps failed: ${FAILED[*]}"
  info "Logs are in: $LOG_DIR   (re-run with --debug to see everything live)"
  exit 1
fi
rm -rf "$LOG_DIR" 2>/dev/null
echo
ui_note_panel "$CYAN" "ALL DONE - NEXT STEPS" \
  "1. Start your AI agent in this folder" \
  "2. Tell it: Read skill-instructions.md and follow it" \
  "3. Claude Code: try  /impeccable audit" \
  "   Other agents: Use the Impeccable skill to audit this page"

# =============================================================================
# HOW TO USE YOUR SKILLS (printed on screen + saved to DESIGN-SKILLS-GUIDE.md)
# =============================================================================
GUIDE_FILE="$PROJECT_ROOT/DESIGN-SKILLS-GUIDE.md"
cat > "$GUIDE_FILE" <<'GUIDE_EOF'
# HOW TO USE YOUR SKILLS

## Quick start
- Tell your AI agent:  "Read skill-instructions.md and follow it for everything in this project."
- That file lists your skills and the exact workflow the agent must follow.

## 1. What is now in your project folder
- DESIGN.md          = the design system (colors, fonts, spacing) your UI must follow
- skill-instructions.md = the file you tell your agent to read: skills + mandatory workflow
- CLAUDE.md          = frontend rules your AI agent reads at the start of a session
- AGENTS.md          = the same rules, for agents that use AGENTS.md
- .claude/skills/    = the installed skills (Claude Code and compatible agents)
- .agents/skills/    = a copy of the same skills for other agents
- .mcp.json          = Playwright MCP: lets the agent open a real browser and take screenshots

## 2. Daily workflow (works with any AI coding agent)
1. Open a terminal in THIS project folder (the one that contains DESIGN.md).
2. Start your agent there: claude, freebuff, codex, gemini, cursor-agent, etc.
3. Check that it sees your setup. Ask:
   "What frontend rules, DESIGN.md and skills do you have in this project?"
4. Give it a UI task. Example:
   "Read DESIGN.md and CLAUDE.md. Build a pricing page following the rules."
5. Ask it to verify visually:
   "Open the localhost page with Playwright, take a screenshot and fix any visual bugs."
6. Run the audit skills, review the result, then commit.

## 3. Tips for each kind of agent
- Claude Code: reads CLAUDE.md and .claude/skills automatically. Skills start from your
  request, or call one by name, e.g.  /impeccable audit  (type / to see the list).
  The first time, approve the Playwright server from .mcp.json (check with /mcp).
- Freebuff / Codebuff and other agents: auto-loading of skills and MCP can differ.
  If the agent does not know your rules, start with this first prompt:
  "Read CLAUDE.md, DESIGN.md and the SKILL.md files inside .agents/skills before any UI work."
  Slash commands like /impeccable only work in agents that support skills; otherwise say:
  "Follow the Impeccable skill and audit this page."
- Cursor / Codex and others: most read AGENTS.md. Gemini CLI reads GEMINI.md by default,
  so run:  cp AGENTS.md GEMINI.md   (check your agent's docs for the exact file name).
- Agent without MCP support: take screenshots yourself and let the agent look at the file:
  npx playwright screenshot http://localhost:3000 shot.png

## 4. Example prompts
- Design system:  "Use DESIGN.md strictly: exact hex colors, type scale, spacing, radius, shadows."
- Impeccable:     "/impeccable audit"  then  "/impeccable polish"  on components, typography, background.
- Taste Skill:    "Use the Taste skill. Bold = high, Motion = medium, Density = low. Redesign the hero."
- Vercel rules:   "Review this page with the Web Design Guidelines skill: accessibility, hit targets, zoom, loading states."
- Playwright QA:  "Open http://localhost:3000, click every button, screenshot, fix overflow or overlap."
- Full pipeline:  "Build the dashboard from DESIGN.md, polish it, audit it, then QA it in the browser."

## 5. Change the design later
- Run  ./setup-design-skills.sh --list  to see all designs, then
  ./setup-design-skills.sh --brand stripe  to switch. Your old DESIGN.md is kept as DESIGN.md.bak.
- Preview designs first at https://getdesign.md/

## 6. If something does not work
- Agent ignores the rules: restart the agent session and say "Read CLAUDE.md and DESIGN.md first."
- Skill not found: run  ls .claude/skills  then say
  "Read .claude/skills/<skill-name>/SKILL.md and follow it for this task."
- Screenshot fails (no browser): run  npx playwright install chromium
- Something failed during setup: re-run the script (it is safe to repeat) or add --debug.
GUIDE_EOF

# add the optional packs that were actually installed
{
  if skill_present using-superpowers; then
    echo
    echo "## 7. Superpowers skills (installed)"
    echo "- They start from your request. Try: \"Use brainstorming to plan this feature\","
    echo "  \"Write the plan first\", \"Use test-driven-development\", \"Use systematic-debugging on this bug\"."
    echo "- Best habit: ask for a plan before code, then ask it to verify before it says done."
  fi
  if skill_present offensive-advanced-redteam; then
    echo
    echo "## 8. Security skills (installed)"
    echo "- Use ONLY on systems you own or are authorized to test (your lab, CTF, scoped engagement)."
    echo "- Name the skill and the authorized target in your prompt. Skills are in .claude/skills/offensive-*"
    echo "- Remove them when not needed: delete the offensive-* folders from .claude/skills and .agents/skills."
  fi
} >> "$GUIDE_FILE"

step "How to use your skills in an AI coding agent"
while IFS= read -r line; do
  case "$line" in
    "# "*)  ;;                                            # file title (already shown as heading)
    "## "*) echo "${BOLD}${CYAN}${line#\#\# }${NC}" ;;
    "")     echo ;;
    *)      echo "  $line" ;;
  esac
done < "$GUIDE_FILE"
echo
ok "Guide saved to DESIGN-SKILLS-GUIDE.md (open it any time)"
echo

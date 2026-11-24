#!/usr/bin/env bash

# ==============================================================================
# Ultimate Interactive Laravel Project Setup & Configuration Script
#
# - Picks a PHP runtime that can actually run the latest Laravel (12 or 13)
# - Provisions MySQL/MariaDB, PostgreSQL, SQLite or SQL Server
# - Installs missing PHP drivers, creates the database and verifies the login
# - Writes .env, runs the first migrations and builds the front-end assets
# ==============================================================================

set -e

# ------------------------------------------------------------------------------
# Colors & global state
# ------------------------------------------------------------------------------
GREEN='\033[38;5;114m'
YELLOW='\033[38;5;179m'
RED='\033[38;5;203m'
LARAVEL_RED='\033[38;5;203m'
CYAN='\033[38;5;111m'
ACCENT='\033[38;5;111m'
MUTED='\033[38;5;244m'
BORDER='\033[38;5;238m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

CURRENT_DIR="$(pwd)"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    SUDO="sudo"
fi

APT_UPDATED=0
PHP_BIN="php"
PHP_MINOR=""
COMPOSER_BIN="$(command -v composer || true)"
PHP_CANDIDATES=()
MYSQL_ENGINE="none"
SERVE_MODE="artisan"

# ------------------------------------------------------------------------------
# Helpers: PHP runtimes
# ------------------------------------------------------------------------------
php_full_version() {
    "$1" -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION.".".PHP_RELEASE_VERSION;' 2>/dev/null
}

php_short_version() {
    "$1" -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null
}

php_version_ge() { # $1 = current, $2 = minimum ("8.3")
    [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

have_php_ext() { # $1 = extension, $2 = optional php binary
    local bin="${2:-$PHP_BIN}"
    "$bin" -m 2>/dev/null | grep -qix "$1"
}

switch_to_system_php() {
    PHP_BIN="$SYSTEM_PHP_BIN"
    PHP_MINOR="$(php_short_version "$PHP_BIN")"
    TARGET_PHP="$(php_full_version "$PHP_BIN")"
    SERVE_MODE="artisan"
}

run_composer() {
    if [ -n "$COMPOSER_BIN" ]; then
        "$PHP_BIN" "$COMPOSER_BIN" "$@"
    else
        composer "$@"
    fi
}

apt_update_once() {
    [ "$APT_UPDATED" = "1" ] && return 0
    if command -v apt-get >/dev/null 2>&1; then
        $SUDO apt-get update -qq || true
        APT_UPDATED=1
    fi
}

apt_php_package() {
    case "$1" in
        pdo_mysql|mysqli) echo "php${PHP_MINOR}-mysql" ;;
        pdo_pgsql) echo "php${PHP_MINOR}-pgsql" ;;
        pdo_sqlite|sqlite3) echo "php${PHP_MINOR}-sqlite3" ;;
        mbstring) echo "php${PHP_MINOR}-mbstring" ;;
        curl) echo "php${PHP_MINOR}-curl" ;;
        zip) echo "php${PHP_MINOR}-zip" ;;
        dom|xml|xmlreader|xmlwriter|simplexml|xsl) echo "php${PHP_MINOR}-xml" ;;
        intl) echo "php${PHP_MINOR}-intl" ;;
        bcmath) echo "php${PHP_MINOR}-bcmath" ;;
        *) echo "" ;;
    esac
}

# ------------------------------------------------------------------------------
# Helpers: install missing requirements (only after the user confirms)
# ------------------------------------------------------------------------------
detect_pkg_manager() {
    local pm
    for pm in apt-get dnf pacman zypper; do
        if command -v "$pm" >/dev/null 2>&1; then printf '%s' "$pm"; return 0; fi
    done
    printf ''
}

pkg_name_for() { # logical name, package manager
    local name="$1" pm="$2"
    case "$name" in
        php-cli)
            case "$pm" in
                pacman) echo "php" ;;
                zypper) echo "php8-cli" ;;
                *) echo "php-cli" ;;
            esac
            ;;
        *) echo "$name" ;;
    esac
}

pkg_for_php_ext() { # extension, package manager, php minor version
    local ext="$1" pm="$2" minor="$3"
    case "$pm" in
        apt-get) PHP_MINOR="$minor"; apt_php_package "$ext" ;;
        pacman)
            case "$ext" in
                pdo_mysql) echo "php" ;;
                pdo_pgsql) echo "php-pgsql" ;;
                pdo_sqlite) echo "php-sqlite" ;;
            esac
            ;;
        *)
            case "$ext" in
                pdo_mysql) echo "php-mysql" ;;
                pdo_pgsql) echo "php-pgsql" ;;
                pdo_sqlite) echo "php-sqlite3" ;;
            esac
            ;;
    esac
}

install_packages() { # native package names...
    local pm
    [ "$#" -gt 0 ] || return 0
    pm="$(detect_pkg_manager)"
    case "$pm" in
        apt-get) apt_update_once; $SUDO apt-get install -y "$@" ;;
        dnf)     $SUDO dnf install -y "$@" ;;
        pacman)  $SUDO pacman -Sy --noconfirm --needed "$@" ;;
        zypper)  $SUDO zypper --non-interactive install "$@" ;;
        *)       return 1 ;;
    esac
}

# Signature-checked Composer installer (same source the official docs use).
install_composer() {
    EXPECTED_SIG="$(php -r "copy('https://composer.github.io/installer.sig', 'php://stdout');" 2>/dev/null | tr -d '[:space:]' || true)"
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    ACTUAL_SIG="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

    if [ -n "$EXPECTED_SIG" ] && [ "$EXPECTED_SIG" != "$ACTUAL_SIG" ]; then
        rm -f composer-setup.php
        return 1
    fi

    $SUDO php composer-setup.php --install-dir=/usr/local/bin --filename=composer
    rm -f composer-setup.php
}

ensure_php_ext() {
    local ext="$1" pkg

    if have_php_ext "$ext"; then
        echo -e "  ${GREEN}[OK]${NC} PHP extension ${BOLD}${ext}${NC} is available."
        return 0
    fi

    case "$PHP_BIN" in
        /opt/lampp/*)
            echo -e "  ${RED}[MISSING]${NC} ${ext} is not enabled in the XAMPP PHP (${PHP_BIN})."
            echo -e "  Enable it in ${BOLD}/opt/lampp/etc/php.ini${NC} or use Native mode."
            return 1
            ;;
    esac

    pkg="$(apt_php_package "$ext")"
    if [ -n "$pkg" ] && command -v apt-get >/dev/null 2>&1; then
        echo -e "  ${YELLOW}[WARN]${NC} PHP extension ${ext} is missing (package ${pkg})."
        if ! ui_confirm "Download and install ${pkg} now?" "y"; then
            echo -e "  ${RED}[SKIP]${NC} ${ext} was not installed."
            return 1
        fi
        apt_update_once
        $SUDO apt-get install -y "$pkg" >/dev/null 2>&1 || true
        if have_php_ext "$ext"; then
            echo -e "  ${GREEN}[OK]${NC} ${ext} installed."
            return 0
        fi
    fi

    echo -e "  ${RED}[ERROR]${NC} Could not provide PHP extension ${ext} for PHP ${PHP_MINOR}."
    return 1
}

# Ensure the selected database's PDO driver exists. XAMPP's bundled PHP cannot
# load distro packages, so fall back to system PHP (and `artisan serve`) there.
require_php_ext_for_db() {
    local ext="$1"
    if have_php_ext "$ext"; then
        echo -e "  ${GREEN}[OK]${NC} PHP extension ${BOLD}${ext}${NC} is available."
        return 0
    fi

    if [ "$PHP_BIN" != "$SYSTEM_PHP_BIN" ]; then
        echo -e "  ${YELLOW}[WARN]${NC} ${ext} is not enabled in XAMPP PHP; switching to ${SYSTEM_PHP_BIN}."
        switch_to_system_php
    fi

    ensure_php_ext "$ext"
}

# ------------------------------------------------------------------------------
# Helpers: .env writing (no sed escaping problems)
# ------------------------------------------------------------------------------
env_quote() {
    local v="$1"
    if [[ "$v" =~ ^[A-Za-z0-9_./:@+,=-]*$ ]]; then
        printf '%s' "$v"
    elif [[ "$v" != *"'"* && "$v" != *'\'* ]]; then
        # Single quotes keep $, backticks and quotes literal for phpdotenv.
        printf "'%s'" "$v"
    else
        v=${v//\\/\\\\}
        v=${v//\"/\\\"}
        printf '"%s"' "$v"
    fi
}

set_env() {
    local file="$1" key="$2" value="$3"
    SET_ENV_FILE="$file" SET_ENV_KEY="$key" SET_ENV_VALUE="$value" "$PHP_BIN" -r '
        $file = getenv("SET_ENV_FILE");
        $key  = getenv("SET_ENV_KEY");
        $val  = getenv("SET_ENV_VALUE");
        $lines = is_file($file) ? file($file, FILE_IGNORE_NEW_LINES) : [];
        $pattern = "/^\s*#?\s*" . preg_quote($key, "/") . "=/";
        $done = false;
        foreach ($lines as $i => $line) {
            if (preg_match($pattern, $line)) {
                $lines[$i] = $key . "=" . $val;
                $done = true;
                break;
            }
        }
        if (!$done) { $lines[] = $key . "=" . $val; }
        file_put_contents($file, implode(PHP_EOL, $lines) . PHP_EOL);
    '
}

# ------------------------------------------------------------------------------
# Helpers: database probing
# ------------------------------------------------------------------------------
db_ping() {
    DB_TEST_CONN="$1" DB_TEST_HOST="$2" DB_TEST_PORT="$3" \
    DB_TEST_NAME="$4" DB_TEST_USER="$5" DB_TEST_PASS="$6" \
    "$PHP_BIN" -r '
        $conn = getenv("DB_TEST_CONN");
        $host = getenv("DB_TEST_HOST");
        $port = getenv("DB_TEST_PORT");
        $name = getenv("DB_TEST_NAME");
        $dsn = match ($conn) {
            "sqlite" => "sqlite:" . $name,
            "pgsql"  => "pgsql:host={$host};port={$port};dbname={$name}",
            "sqlsrv" => "sqlsrv:Server={$host},{$port};Database={$name}",
            default  => "mysql:host={$host};port={$port};dbname={$name}",
        };
        $user = getenv("DB_TEST_USER");
        $pass = getenv("DB_TEST_PASS");
        try {
            $options = [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION];
            if (in_array($conn, ["mysql", "sqlite", "sqlsrv"], true)) {
                $options[PDO::ATTR_TIMEOUT] = 5;
            }
            $pdo = new PDO($dsn, $user !== "" ? $user : null, $pass !== "" ? $pass : null, $options);
            $pdo->query("SELECT 1");
            echo "ok";
        } catch (Throwable $e) {
            echo "fail: " . $e->getMessage();
            exit(1);
        }
    ' 2>&1
}

driver_state() {
    if have_php_ext "$1"; then
        printf 'driver ready'
    else
        printf 'driver missing'
    fi
}

mysql_server_label() {
    if pgrep -x mysqld >/dev/null 2>&1 || pgrep -x mariadbd >/dev/null 2>&1; then
        echo "server running"
    elif pgrep -f "lampp.*mysqld" >/dev/null 2>&1; then
        echo "XAMPP server running"
    elif command -v mysqld >/dev/null 2>&1 || command -v mariadbd >/dev/null 2>&1 || [ -x /opt/lampp/bin/mysqld ]; then
        echo "installed, not running"
    else
        echo "not installed"
    fi
}

pgsql_server_label() {
    if command -v pg_isready >/dev/null 2>&1 && pg_isready -q -h 127.0.0.1 -p 5432 >/dev/null 2>&1; then
        echo "server reachable"
    elif systemctl is-active --quiet postgresql 2>/dev/null; then
        echo "service running"
    elif command -v psql >/dev/null 2>&1; then
        echo "installed, not running"
    else
        echo "not installed"
    fi
}

as_postgres() {
    if [ -n "$SUDO" ]; then
        sudo -u postgres "$@"
    else
        runuser -u postgres -- "$@"
    fi
}

# ------------------------------------------------------------------------------
# UI layer (opencode-inspired terminal interface)
# ------------------------------------------------------------------------------
# IS_TTY: stdout is a real terminal (screen can be cleared/animated).
# IS_INTERACTIVE: stdin is also a terminal (arrow keys can be read).
IS_TTY=0
IS_INTERACTIVE=0
if [ -t 1 ]; then
    IS_TTY=1
fi
if [ "$IS_TTY" = "1" ] && [ -t 0 ]; then
    IS_INTERACTIVE=1
fi

# Real terminal size as "rows cols". These helpers run inside $( ), so stdout is a
# pipe and [ -t 1 ] is useless there - ask the controlling terminal directly.
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

ui_term_width() { # real terminal width (not clamped to the panel width)
    local s="" w=""
    s="$(ui_size)"
    w="${s#* }"
    case "$w" in ''|*[!0-9]*) w="" ;; esac
    [ "${w:-0}" -gt 0 ] || w="${COLUMNS:-80}"
    case "$w" in ''|*[!0-9]*) w=80 ;; esac
    [ "$w" -lt 20 ] && w=20
    printf '%s' "$w"
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
ui_rows() { # usable terminal height, defaults to 24
    local s="" r=""
    s="$(ui_size)"
    r="${s%% *}"
    case "$r" in ''|*[!0-9]*) r="" ;; esac
    [ "${r:-0}" -gt 0 ] || r="${LINES:-24}"
    case "$r" in ''|*[!0-9]*) r=24 ;; esac
    [ "$r" -lt 10 ] && r=10
    printf '%s' "$r"
}
ui_cursor_hide() { if [ "$IS_TTY" = "1" ]; then printf '\033[?25l'; fi; }
ui_cursor_show() { if [ "$IS_TTY" = "1" ]; then printf '\033[?25h'; fi; }
trap ui_cursor_show EXIT

ui_dashes() { printf '─%.0s' $(seq 1 "$1" 2>/dev/null); }

ui_rule_n() { printf '%b%s%b\n' "$BORDER" "$(ui_dashes "$1")" "$NC"; }
ui_rule() { ui_rule_n "$(ui_width)"; }

# Centered line: text [color]
ui_center() {
    local w pad
    w="$(ui_width)"
    pad=$(( (w - ${#1}) / 2 ))
    [ "$pad" -lt 0 ] && pad=0
    printf '%*s%b%s%b\n' "$pad" "" "${2:-$NC}" "$1" "$NC"
}

ui_section() {
    echo ""
    ui_center "$1" "$BOLD"
    ui_rule
}

ui_kv() {
    printf '  %b%-16s%b %s\n' "$MUTED" "$1" "$NC" "$2"
}

# Draws a rounded panel; text is wrapped to the terminal width.
ui_panel() {
    local title="$1"; shift
    local w inner span left right line seg pad
    w="$(ui_width)"; inner=$((w - 4)); [ "$inner" -lt 40 ] && inner=40

    if [ -n "$title" ]; then
        span=$(( w - 4 - ${#title} ))
        [ "$span" -lt 2 ] && span=2
        left=$(( span / 2 )); right=$(( span - left ))
        printf '%b╭%s %b%s%b %b%s%b╮%b\n' "$BORDER" "$(ui_dashes "$left")" "$BOLD" "$title" "$NC" "$BORDER" "$(ui_dashes "$right")" "$NC"
    else
        printf '%b╭%s╮%b\n' "$BORDER" "$(ui_dashes $((w - 2)))" "$NC"
    fi

    for line in "$@"; do
        if [ -z "$line" ]; then
            printf '%b│%b%*s%b│%b\n' "$BORDER" "$NC" $((w - 2)) "" "$NC" "$BORDER"
            continue
        fi
        while IFS= read -r seg; do
            pad=$((inner - ${#seg}))
            [ "$pad" -lt 0 ] && pad=0
            printf '%b│%b %s%*s %b│%b\n' "$BORDER" "$NC" "$seg" "$pad" "" "$NC" "$BORDER"
        done < <(printf '%s\n' "$line" | fold -s -w "$inner")
    done

    printf '%b╰%s╯%b\n' "$BORDER" "$(ui_dashes $((w - 2)))" "$NC"
}

ui_logo() {
    local text="$1" w line pad
    w="$(ui_width)"
    if ! command -v figlet >/dev/null 2>&1; then
        printf '%b%s%b\n' "$ACCENT" "$text" "$NC"
        return 0
    fi
    figlet -w 120 -f standard "$text" | while IFS= read -r line; do
        pad=$(( (w - ${#line}) / 2 ))
        [ "$pad" -lt 0 ] && pad=0
        printf '%*s%s\n' "$pad" "" "$line"
    done | { if command -v lolcat >/dev/null 2>&1; then lolcat; else cat; fi; }
}

# Laravel logo mark + wordmark, side by side and centered.
ui_laravel_header() {
    local w pad mw ww mrows wrows rows r wi idx tmp line n
    local -a mark=(
        "  ▄███▄           "
        " ███████    ▄███▄ "
        " ███████   ███████"
        " ███████   ███████"
        " ███████▄▄  ▀███▀ "
        " ██████████▄ ███  "
        "  ▀████████████   "
        "     ▀████████    "
        "       ▀████▀     "
    )
    local -a mark_tint=( 209 203 203 202 202 202 208 208 209 )
    local -a word_tint=( 209 208 203 202 196 )
    local -a word=()
    w="$(ui_width)"

    if command -v figlet >/dev/null 2>&1; then
        while IFS= read -r line; do word+=("$line"); done < <(figlet -w 200 -f ANSI-Shadow "LARAVEL" 2>/dev/null)
    fi
    while [ ${#word[@]} -gt 0 ]; do
        idx=$(( ${#word[@]} - 1 ))
        tmp="${word[$idx]// /}"
        if [ -z "$tmp" ]; then unset "word[$idx]"; else break; fi
    done
    [ ${#word[@]} -eq 0 ] && word=("LARAVEL")

    mw=0; for line in "${mark[@]}"; do n="$(ui_swidth "$line")"; [ "$n" -gt "$mw" ] && mw=$n; done
    ww=0; for line in "${word[@]}"; do n="$(ui_swidth "$line")"; [ "$n" -gt "$ww" ] && ww=$n; done

    # The shadow wordmark is ~57 columns wide; drop the block mark when the
    # two no longer fit side by side (narrow terminals).
    if [ $(( mw + 4 + ww )) -gt "$w" ]; then
        mark=()
        mw=0
    fi

    mrows=${#mark[@]}; wrows=${#word[@]}
    rows=$mrows; [ "$wrows" -gt "$rows" ] && rows=$wrows
    if [ "$mrows" -gt 0 ]; then
        pad=$(( (w - (mw + 4 + ww)) / 2 ))
    else
        pad=$(( (w - ww) / 2 ))
    fi
    [ "$pad" -lt 0 ] && pad=0

    for ((r = 0; r < rows; r++)); do
        printf '%*s' "$pad" ""
        if [ "$mrows" -gt 0 ]; then
            if [ "$r" -lt "$mrows" ]; then
                printf '%b%s%b' "$(printf '\033[38;5;%sm' "${mark_tint[$r]}")" "${mark[$r]}" "$NC"
                printf '%*s' $(( mw - $(ui_swidth "${mark[$r]}") + 4 )) ""
            else
                printf '%*s' $(( mw + 4 )) ""
            fi
        fi
        wi=$(( r - (rows - wrows) / 2 ))
        if [ "$wi" -ge 0 ] && [ "$wi" -lt "$wrows" ]; then
            printf '%b%s%b' "$(printf '\033[38;5;%sm' "${word_tint[$((wi % 5))]}")" "${word[$wi]}" "$NC"
        fi
        printf '\n'
    done
}

ui_menu_row() { # selected label desc width
    local sel="$1" label="$2" desc="$3" w="$4" text pad
    if [ "$sel" = "1" ]; then
        text="❯ ${label}"
        [ -n "$desc" ] && text="${text}  ${desc}"
        pad=$(( w + 1 - ${#text} ))
        [ "$pad" -lt 0 ] && pad=0
        printf '\033[2K\033[48;5;237m\033[38;5;252m %s%*s\033[0m\n' "$text" "$pad" ""
    else
        printf '\033[2K   %s' "$label"
        [ -n "$desc" ] && printf '  %b%s%b' "$MUTED" "$desc" "$NC"
        printf '\n'
    fi
}

# Arrow-key single select. Options are "label|description" strings.
# Sets MENU_RESULT to the 1-based index. Falls back to numbers without a TTY.
menu_select() {
    local prompt="$1" def="$2"; shift 2
    local -a labels=() descs=()
    local item i n sel key rest w desc avail ans
    for item in "$@"; do
        labels+=("${item%%|*}")
        if [[ "$item" == *"|"* ]]; then descs+=("${item#*|}"); else descs+=(""); fi
    done
    n=${#labels[@]}
    [ "$n" -eq 0 ] && return 1
    sel=$((def - 1))
    [ "$sel" -lt 0 ] && sel=0
    [ "$sel" -ge "$n" ] && sel=$((n - 1))
    w="$(ui_width)"

    if [ "$IS_INTERACTIVE" != "1" ]; then
        printf '? %s\n' "$prompt"
        for ((i = 0; i < n; i++)); do
            printf '  %d) %s' $((i + 1)) "${labels[$i]}"
            [ -n "${descs[$i]}" ] && printf ' - %s' "${descs[$i]}"
            printf '\n'
        done
        read -r -p "Select [default: $((sel + 1))]: " ans || ans=""
        case "$ans" in
            ''|*[!0-9]*) : ;;
            *) [ "$ans" -ge 1 ] && [ "$ans" -le "$n" ] && sel=$((ans - 1)) ;;
        esac
        MENU_RESULT=$((sel + 1))
        return 0
    fi

    printf '%b?%b %b%s%b\n' "$ACCENT" "$NC" "$BOLD" "$prompt" "$NC"
    printf '  %b↑/↓ move · enter select · q quit%b\n' "$MUTED" "$NC"
    ui_cursor_hide
    for ((i = 0; i < n; i++)); do
        desc="${descs[$i]}"
        avail=$((w - 10 - ${#labels[$i]}))
        [ "$avail" -lt 8 ] && avail=8
        [ ${#desc} -gt "$avail" ] && desc="${desc:0:avail}"
        if [ "$i" = "$sel" ]; then ui_menu_row 1 "${labels[$i]}" "$desc" "$w"; else ui_menu_row 0 "${labels[$i]}" "$desc" "$w"; fi
    done

    while :; do
        key=""
        IFS= read -rsn1 key || key=""
        case "$key" in
            $'\e') IFS= read -rsn2 -t 0.02 rest || rest=""; key="${key}${rest}" ;;
        esac
        case "$key" in
            $'\e[A'|k|K) sel=$(( (sel - 1 + n) % n )) ;;
            $'\e[B'|j|J) sel=$(( (sel + 1) % n )) ;;
            ''|$'\r'|$'\n') break ;;
            q|Q) ui_cursor_show; echo ""; printf '  %bCancelled.%b\n' "$MUTED" "$NC"; exit 0 ;;
            [1-9]) if [ "$key" -le "$n" ]; then sel=$((key - 1)); break; fi ;;
            *) continue ;;
        esac
        printf '\033[%dA' "$n"
        for ((i = 0; i < n; i++)); do
            desc="${descs[$i]}"
            avail=$((w - 10 - ${#labels[$i]}))
            [ "$avail" -lt 8 ] && avail=8
            [ ${#desc} -gt "$avail" ] && desc="${desc:0:avail}"
            if [ "$i" = "$sel" ]; then ui_menu_row 1 "${labels[$i]}" "$desc" "$w"; else ui_menu_row 0 "${labels[$i]}" "$desc" "$w"; fi
        done
    done
    ui_cursor_show
    printf '\033[%dA\033[J' $((n + 2))
    printf '  %b✔%b %s %b· %s%b\n' "$GREEN" "$NC" "$prompt" "$MUTED" "${labels[$sel]}" "$NC"
    MENU_RESULT=$((sel + 1))
}

ask_input() { # prompt default -> ASK_RESULT
    local prompt="$1" def="$2" ans=""
    printf '%b?%b %s\n' "$ACCENT" "$NC" "$prompt"
    [ -n "$def" ] && printf '  %bdefault: %s%b\n' "$MUTED" "$def" "$NC"
    printf '  %b❯%b ' "$ACCENT" "$NC"
    IFS= read -r ans || ans=""
    if [ "$IS_INTERACTIVE" != "1" ]; then echo ""; fi
    if [ -z "$ans" ]; then ans="$def"; fi
    ASK_RESULT="$ans"
}

ask_secret() { # prompt -> SECRET_RESULT
    printf '%b?%b %s\n  %b❯%b ' "$ACCENT" "$NC" "$1" "$ACCENT" "$NC"
    IFS= read -rs SECRET_RESULT || SECRET_RESULT=""
    printf '\n'
}

ui_confirm() { # prompt default(y|n) -> exit status
    local def_idx=2
    [ "$2" = "y" ] && def_idx=1
    menu_select "$1" "$def_idx" "Yes" "No"
    [ "$MENU_RESULT" = "1" ]
}

# Runs a command behind a live spinner; output is replayed only on failure.
ui_spin() { # message command...
    local msg="$1"; shift
    local log rc i=0 pid
    local -a frames=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )
    if [ "$IS_TTY" != "1" ]; then
        printf '  %b›%b %s\n' "$ACCENT" "$NC" "$msg"
        "$@"
        return $?
    fi
    log="$(mktemp 2>/dev/null || echo "/tmp/laravel-setup.$$.log")"
    "$@" >"$log" 2>&1 &
    pid=$!
    ui_cursor_hide
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r  %b%s%b %s ' "$ACCENT" "${frames[$((i % 10))]}" "$NC" "$msg"
        i=$((i + 1))
        sleep 0.08
    done
    if wait "$pid"; then rc=0; else rc=$?; fi
    ui_cursor_show
    printf '\r\033[2K'
    if [ "$rc" -eq 0 ]; then
        printf '  %b✔%b %s\n' "$GREEN" "$NC" "$msg"
        rm -f "$log"
    else
        printf '  %b✖%b %s\n' "$RED" "$NC" "$msg"
        tail -n 25 "$log" 2>/dev/null | sed 's/^/    /'
        printf '  %bfull log: %s%b\n' "$MUTED" "$log" "$NC"
    fi
    return "$rc"
}

ui_pause() { # [message]
    [ "$IS_INTERACTIVE" = "1" ] || return 0
    printf '\n  %b%s%b ' "$MUTED" "${1:-Press enter to continue}" "$NC"
    IFS= read -rsn1 _ || true
    printf '\n'
}

# Step-title banner: figlet standard for every step heading. The cover keeps
# ANSI-Shadow for the LARAVEL wordmark. Narrower faces only kick in when a long
# heading would otherwise overflow the terminal.
ui_banner() { # text
    local text="$1" w termw line pad i=0 n need font
    local -a rows=() fonts=( standard small mini )

    if ! command -v figlet >/dev/null 2>&1; then
        ui_center "$text" "$ACCENT"
        return 0
    fi
    w="$(ui_width)"
    termw="$(ui_term_width)"
    UI_FRAME_W="$w"

    for font in "${fonts[@]}"; do
        rows=()
        while IFS= read -r line; do rows+=("$line"); done < <(figlet -w 400 -f "$font" "$text" 2>/dev/null)
        while [ ${#rows[@]} -gt 0 ]; do
            line="${rows[${#rows[@]}-1]}"
            [ -z "${line// /}" ] || break
            unset 'rows[${#rows[@]}-1]'
        done
        [ ${#rows[@]} -eq 0 ] && continue
        need=0
        for line in "${rows[@]}"; do
            n="$(ui_swidth "$line")"
            [ "$n" -gt "$need" ] && need=$n
        done
        # Keep standard even when it is wider than the panel frame, as long as
        # the real terminal can show it.
        if [ "$need" -le "$w" ]; then
            break
        elif [ "$need" -le "$termw" ]; then
            w="$need"
            break
        fi
        rows=()
    done

    if [ ${#rows[@]} -eq 0 ]; then
        ui_center "$text" "$ACCENT"
        return 0
    fi

    # A banner wider than the panel frame stays left-aligned so the rule and
    # progress line can follow its width instead of overflowing off-screen.
    UI_FRAME_W="$w"
    for line in "${rows[@]}"; do
        pad=$(( (w - $(ui_swidth "$line")) / 2 )); [ "$pad" -lt 0 ] && pad=0
        if [ $((i % 2)) -eq 0 ]; then
            printf '%*s\033[38;5;209m%s\033[0m\n' "$pad" "" "$line"
        else
            printf '%*s\033[38;5;202m%s\033[0m\n' "$pad" "" "$line"
        fi
        i=$((i + 1))
    done
}

# Step header: cleared screen with the step title as a centered banner and a
# compact progress line. The title only appears here, not in the step body.
ui_step() { # current total title
    local n="$1" total="$2" title="$3" i w pad label len
    ui_clear
    w="$(ui_width)"
    label="STEP ${n} OF ${total}"

    echo ""
    ui_banner "${title^^}"
    w="${UI_FRAME_W:-$w}"
    ui_rule_n "$w"

    len=$(( (2 * total - 1) + 2 + ${#label} ))
    pad=$(( (w - len) / 2 )); [ "$pad" -lt 0 ] && pad=0
    printf '%*s' "$pad" ""
    for ((i = 1; i <= total; i++)); do
        if [ "$i" -le "$n" ]; then
            printf '%b●%b' "$ACCENT" "$NC"
        else
            printf '%b○%b' "$MUTED" "$NC"
        fi
        [ "$i" -lt "$total" ] && printf ' '
        if [ "$IS_TTY" = "1" ]; then sleep 0.03; fi
    done
    printf '  %b%s%b\n' "$MUTED" "$label" "$NC"
    echo ""
}

# ------------------------------------------------------------------------------
# Cover screen
# ------------------------------------------------------------------------------
COVER_ROWS="$(ui_rows)"
ui_clear
ui_laravel_header
ui_center "project setup wizard" "$MUTED"
if [ "$COVER_ROWS" -lt 24 ]; then
    # Short window: keep the cover above the fold instead of scrolling it.
    ui_center "MySQL · PostgreSQL · SQLite · SQL Server" "$MUTED"
    ui_center "↑/↓ move · enter select · q quit" "$MUTED"
else
    echo ""
    ui_panel "UNIVERSAL SETUP" \
        "Laravel 12 / 13 - PHP 8.2+" \
        "MySQL, MariaDB, PostgreSQL, SQLite or SQL Server" \
        "Installs the driver, provisions the database, verifies the login."
    echo ""
    ui_center "↑/↓ move   enter select   q quit" "$MUTED"
    ui_center "Working directory: ${CURRENT_DIR}" "$MUTED"
fi
echo ""
printf '%*s%bPress enter to begin%b ' $(( ($(ui_width) - 20) / 2 )) "" "$MUTED" "$NC"
if [ "$IS_INTERACTIVE" = "1" ]; then IFS= read -rsn1 _ || true; fi
echo ""

# ------------------------------------------------------------------------------
# STEP 1: Environment & Dependency Checks
# ------------------------------------------------------------------------------
ui_step 1 6 "Requirements"

PM="$(detect_pkg_manager)"
MISSING_NAMES=()
MISSING_PKGS=()
ALL_PKGS=()
NEED_COMPOSER=0

add_requirement() { # logical name
    local pkg
    MISSING_NAMES+=("$1")
    pkg="$(pkg_name_for "$1" "$PM")"
    [ -z "$pkg" ] && return 0
    MISSING_PKGS+=("$pkg")
    ALL_PKGS+=("$pkg")
    return 0
}

# PHP CLI (the runtime everything else depends on)
if command -v php >/dev/null 2>&1; then
    SYSTEM_PHP_BIN="$(command -v php)"
    echo -e "${GREEN}[OK]${NC} PHP CLI ${BOLD}$(php_full_version "$SYSTEM_PHP_BIN")${NC} (${SYSTEM_PHP_BIN})"
else
    SYSTEM_PHP_BIN=""
    echo -e "${YELLOW}[..]${NC} PHP CLI not found"
    add_requirement php-cli
fi

# Display + tooling used by the wizard
for tool in figlet lolcat git unzip curl; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo -e "${GREEN}[OK]${NC} ${tool}"
        ALL_PKGS+=("$(pkg_name_for "$tool" "$PM")")
    else
        echo -e "${YELLOW}[..]${NC} ${tool} will be installed"
        add_requirement "$tool"
    fi
done

# Composer
if [ -n "$COMPOSER_BIN" ]; then
    echo -e "${GREEN}[OK]${NC} Composer"
else
    echo -e "${YELLOW}[..]${NC} Composer will be installed"
    NEED_COMPOSER=1
fi

# PHP database drivers the wizard can provision
SYS_PHP_MINOR=""
if [ -n "$SYSTEM_PHP_BIN" ]; then
    SYS_PHP_MINOR="$(php_short_version "$SYSTEM_PHP_BIN")"
    for ext in pdo_mysql pdo_pgsql pdo_sqlite; do
        if have_php_ext "$ext" "$SYSTEM_PHP_BIN"; then
            echo -e "${GREEN}[OK]${NC} ${ext}"
            ext_pkg="$(pkg_for_php_ext "$ext" "$PM" "$SYS_PHP_MINOR")"
            [ -n "$ext_pkg" ] && ALL_PKGS+=("$ext_pkg")
        else
            echo -e "${YELLOW}[..]${NC} ${ext} will be installed"
            ext_pkg="$(pkg_for_php_ext "$ext" "$PM" "$SYS_PHP_MINOR")"
            if [ -n "$ext_pkg" ]; then
                MISSING_NAMES+=("$ext")
                MISSING_PKGS+=("$ext_pkg")
                ALL_PKGS+=("$ext_pkg")
            fi
        fi
    done
fi

# ------------------------------------------------------------------------------
# One confirmation: download/update everything from here, before any other step
# ------------------------------------------------------------------------------
if [ ${#MISSING_NAMES[@]} -gt 0 ] || [ "$NEED_COMPOSER" = "1" ]; then
    echo ""

    if [ "$NEED_COMPOSER" = "1" ]; then
        MISSING_NAMES+=("composer")
    fi

    ui_panel "MISSING REQUIREMENTS" \
        "${MISSING_NAMES[*]}" \
        "" \
        "Everything is downloaded and updated here, then the remaining" \
        "steps run without installing anything else."

    if ui_confirm "Download, install and update them now?" "y"; then
        mapfile -t INSTALL_PKGS < <(printf '%s\n' "${ALL_PKGS[@]}" "${MISSING_PKGS[@]}" | awk 'NF && !seen[$0]++')
        if [ ${#INSTALL_PKGS[@]} -gt 0 ]; then
            ui_spin "Installing and updating system packages" install_packages "${INSTALL_PKGS[@]}" || true
        fi
        if [ "$NEED_COMPOSER" = "1" ]; then
            ui_spin "Installing Composer" install_composer || true
            COMPOSER_BIN="$(command -v composer || true)"
        elif [ -n "$COMPOSER_BIN" ] && [ -n "$SYSTEM_PHP_BIN" ]; then
            # Keep an existing Composer on its latest release.
            ( "$SYSTEM_PHP_BIN" "$COMPOSER_BIN" self-update --no-interaction >/dev/null 2>&1 || true )
        fi
    else
        echo -e "  ${YELLOW}[WARN]${NC} Continuing without installing the missing requirements."
        echo -e "  ${MUTED}Some visuals or database drivers may fall back or be unavailable.${NC}"
    fi
fi

# ------------------------------------------------------------------------------
# Verification: one tick per requirement after the download step
# ------------------------------------------------------------------------------
echo ""
printf '  %b%s%b\n' "$BOLD" "Verified requirements" "$NC"

check_ok() { printf '  %b✔%b %s\n' "$GREEN" "$NC" "$1"; }
check_no() { printf '  %b✖%b %s\n' "$RED" "$NC" "$1"; }

if command -v php >/dev/null 2>&1; then
    SYSTEM_PHP_BIN="$(command -v php)"
    check_ok "PHP CLI $(php_full_version "$SYSTEM_PHP_BIN") - $(command -v php)"
else
    check_no "PHP CLI is still missing - install PHP 8.2+ and run the script again"
    exit 1
fi

for tool in figlet lolcat git unzip curl; do
    if command -v "$tool" >/dev/null 2>&1; then check_ok "$tool"; else check_no "$tool"; fi
done

COMPOSER_BIN="$(command -v composer || true)"
if [ -n "$COMPOSER_BIN" ]; then
    COMPOSER_VER="$("$SYSTEM_PHP_BIN" "$COMPOSER_BIN" --version --no-ansi 2>/dev/null | head -n1 | sed 's/^Composer version //' || true)"
    check_ok "Composer ${COMPOSER_VER:-installed}"
else
    check_no "Composer is still missing - install it and run the script again"
    exit 1
fi

for ext in pdo_mysql pdo_pgsql pdo_sqlite; do
    if have_php_ext "$ext" "$SYSTEM_PHP_BIN"; then
        check_ok "${ext}"
    else
        check_no "${ext} (that database option will ask before installing its driver)"
    fi
done

# ------------------------------------------------------------------------------
# STEP 2: Environment & PHP Runtime Selection
# ------------------------------------------------------------------------------
ui_pause "Requirements checked. Press enter to configure the environment"
ui_step 2 6 "Environments"

menu_select "How do you want to run and host the project?" 2 \
    "XAMPP Stack|XAMPP MySQL; Apache when its PHP can run Laravel" \
    "Native CLI|System PHP and native database engines via artisan serve"
ENV_CHOICE="$MENU_RESULT"

if [ "$ENV_CHOICE" = "1" ]; then
    ENV_MODE="xampp"
    if [ ! -x "/opt/lampp/lampp" ]; then
        echo -e "${RED}[ERROR] XAMPP is not found at /opt/lampp.${NC}"
        echo -e "Please install XAMPP first or select Option 2 for Native mode."
        exit 1
    fi

    if [ -x "/opt/lampp/bin/php" ]; then
        XAMPP_PHP_VERSION="$(php_short_version /opt/lampp/bin/php)"
        PHP_CANDIDATES+=("/opt/lampp/bin/php|${XAMPP_PHP_VERSION}")
    fi
else
    ENV_MODE="native"
fi

PHP_CANDIDATES+=("${SYSTEM_PHP_BIN}|$(php_short_version "$SYSTEM_PHP_BIN")")

# Pick the highest available PHP runtime
BEST_PHP_BIN=""
BEST_PHP_VERSION=""
for ENTRY in "${PHP_CANDIDATES[@]}"; do
    ENTRY_BIN="${ENTRY%%|*}"
    ENTRY_VER="${ENTRY##*|}"
    [ -n "$ENTRY_VER" ] || continue
    if [ -z "$BEST_PHP_VERSION" ] || [ "$(printf '%s\n%s\n' "$BEST_PHP_VERSION" "$ENTRY_VER" | sort -V | tail -n1)" = "$ENTRY_VER" ]; then
        BEST_PHP_BIN="$ENTRY_BIN"
        BEST_PHP_VERSION="$ENTRY_VER"
    fi
done

if ! php_version_ge "$BEST_PHP_VERSION" "8.2"; then
    echo -e "${RED}[ERROR] PHP ${BEST_PHP_VERSION} is the newest PHP available, but Laravel 12 needs at least 8.2.${NC}"
    echo -e "Install PHP 8.3 or 8.4 and run this script again."
    exit 1
fi

if php_version_ge "$BEST_PHP_VERSION" "8.3"; then
    LARAVEL_VERSION="13"
else
    LARAVEL_VERSION="12"
fi
LARAVEL_PKG="laravel/laravel:^${LARAVEL_VERSION}.0"

# XAMPP mode: prefer XAMPP's PHP when it can run the Laravel version we picked,
# otherwise fall back to the newest usable PHP and serve with 'artisan serve'.
PHP_BIN="$BEST_PHP_BIN"
if [ "$ENV_MODE" = "xampp" ]; then
    SERVE_MODE="artisan"
    if [ -x "/opt/lampp/bin/php" ]; then
        if { [ "$LARAVEL_VERSION" = "13" ] && php_version_ge "$XAMPP_PHP_VERSION" "8.3"; } || \
           { [ "$LARAVEL_VERSION" = "12" ] && php_version_ge "$XAMPP_PHP_VERSION" "8.2"; }; then
            PHP_BIN="/opt/lampp/bin/php"
            SERVE_MODE="apache"
            echo -e "${GREEN}[OK]${NC} XAMPP PHP ${XAMPP_PHP_VERSION} can run Laravel ${LARAVEL_VERSION}; serving through XAMPP Apache."
        else
            if [ "$LARAVEL_VERSION" = "13" ]; then
                echo -e "${YELLOW}[WARN] XAMPP PHP ${XAMPP_PHP_VERSION} is too old for Laravel 13 (needs 8.3+).${NC}"
                echo -e "       Using ${BOLD}${PHP_BIN}${NC} (PHP ${BEST_PHP_VERSION}) for Composer and Artisan."
                echo -e "       XAMPP Apache runs PHP ${XAMPP_PHP_VERSION}, so the app is served with 'php artisan serve'."
                echo -e "       Upgrade XAMPP's PHP (or use Native mode) if you want Apache to serve it."
            else
                echo -e "${YELLOW}[WARN] Using ${PHP_BIN} (PHP ${BEST_PHP_VERSION}) instead of XAMPP PHP.${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}[WARN] XAMPP PHP not found at /opt/lampp/bin/php; using ${PHP_BIN}.${NC}"
    fi
fi

PHP_MINOR="$(php_short_version "$PHP_BIN")"
TARGET_PHP="$(php_full_version "$PHP_BIN")"

echo -e "${GREEN}[OK]${NC} Laravel target : ${BOLD}${LARAVEL_VERSION}.x${NC} (${LARAVEL_PKG})"
echo -e "${GREEN}[OK]${NC} PHP runtime   : ${BOLD}${TARGET_PHP}${NC} (${PHP_BIN})"

# ------------------------------------------------------------------------------
# STEP 3: Project & Database Settings
# ------------------------------------------------------------------------------
ui_step 3 6 "Project and database"

while :; do
    ask_input "Project / webapp name (e.g. test-app)" ""
    RAW_PROJECT_NAME="$ASK_RESULT"
    PROJECT_FOLDER=$(printf '%s' "$RAW_PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
    if [ -z "$PROJECT_FOLDER" ]; then
        echo -e "${RED}  Project name must contain at least one letter or number.${NC}"
        continue
    fi
    break
done

DEFAULT_DB_NAME=$(printf '%s' "$PROJECT_FOLDER" | tr '-' '_')

if [ -d "${CURRENT_DIR}/${PROJECT_FOLDER}" ]; then
    echo -e "${RED}[ERROR] Folder '${CURRENT_DIR}/${PROJECT_FOLDER}' already exists!${NC}"
    exit 1
fi

menu_select "Which database engine should Laravel use?" 1 \
    "MySQL / MariaDB|$(driver_state pdo_mysql) - $(mysql_server_label)" \
    "PostgreSQL|$(driver_state pdo_pgsql) - $(pgsql_server_label)" \
    "SQLite|$(driver_state pdo_sqlite) - file based, no server needed" \
    "SQL Server|$(driver_state pdo_sqlsrv) - external server on port 1433"
DB_CHOICE="$MENU_RESULT"
case "$DB_CHOICE" in
    1) DB_CONN="mysql" ;;
    2) DB_CONN="pgsql" ;;
    3) DB_CONN="sqlite" ;;
    4) DB_CONN="sqlsrv" ;;
esac

if [ "$DB_CONN" = "sqlite" ]; then
    DB_NAME="$DEFAULT_DB_NAME"
    echo -e "${YELLOW}[INFO] SQLite selected, no server or credentials are needed.${NC}"
elif [ "$DB_CONN" = "mysql" ]; then
    if [ "$ENV_MODE" = "xampp" ]; then
        DEFAULT_MYSQL_ENGINE="2"
    else
        DEFAULT_MYSQL_ENGINE="1"
    fi

    menu_select "Which MySQL engine should be used?" "$DEFAULT_MYSQL_ENGINE" \
        "Native MySQL/MariaDB|Uses the system MySQL/MariaDB service" \
        "XAMPP MySQL|Uses the MySQL engine bundled with XAMPP"
    MYSQL_ENGINE_CHOICE="$MENU_RESULT"

    if [ "$MYSQL_ENGINE_CHOICE" = "2" ]; then
        MYSQL_ENGINE="xampp_mysql"
        if [ ! -x "/opt/lampp/lampp" ]; then
            echo -e "${RED}[ERROR] XAMPP is not found at /opt/lampp.${NC}"
            echo -e "Please install XAMPP or select Option 1 for Native MySQL/MariaDB."
            exit 1
        fi
    else
        MYSQL_ENGINE="native_mysql"
    fi

    ask_input "MySQL database name" "$DEFAULT_DB_NAME"; DB_NAME="$ASK_RESULT"
    ask_input "MySQL host" "127.0.0.1";                  DB_HOST="$ASK_RESULT"
    ask_input "MySQL port" "3306";                       DB_PORT="$ASK_RESULT"
    ask_input "MySQL username" "root";                   DB_USER="$ASK_RESULT"

    while :; do
        ask_secret "MySQL password (blank for XAMPP's empty default)"
        DB_PASS="$SECRET_RESULT"
        case "$DB_PASS" in
            *"'"*|*\\*)
                echo -e "${RED}A password containing a single quote or backslash is not supported here.${NC}"
                ;;
            *) break ;;
        esac
    done
elif [ "$DB_CONN" = "pgsql" ]; then
    ask_input "PostgreSQL database name" "$DEFAULT_DB_NAME"; DB_NAME="$ASK_RESULT"
    ask_input "PostgreSQL host" "127.0.0.1";                  DB_HOST="$ASK_RESULT"
    ask_input "PostgreSQL port" "5432";                       DB_PORT="$ASK_RESULT"
    ask_input "PostgreSQL username" "$DEFAULT_DB_NAME";       DB_USER="$ASK_RESULT"

    while :; do
        ask_secret "PostgreSQL password (required for TCP logins)"
        DB_PASS="$SECRET_RESULT"
        if [ -z "$DB_PASS" ]; then
            echo -e "${RED}PostgreSQL needs a password for 127.0.0.1 connections.${NC}"
            continue
        fi
        case "$DB_PASS" in
            *"'"*|*\\*)
                echo -e "${RED}A password containing a single quote or backslash is not supported here.${NC}"
                ;;
            *) break ;;
        esac
    done
elif [ "$DB_CONN" = "sqlsrv" ]; then
    ask_input "SQL Server database name" "$DEFAULT_DB_NAME"; DB_NAME="$ASK_RESULT"
    ask_input "SQL Server host" "127.0.0.1";                 DB_HOST="$ASK_RESULT"
    ask_input "SQL Server port" "1433";                      DB_PORT="$ASK_RESULT"
    ask_input "SQL Server username" "sa";                    DB_USER="$ASK_RESULT"

    while :; do
        ask_secret "SQL Server password"
        DB_PASS="$SECRET_RESULT"
        if [ -z "$DB_PASS" ]; then
            echo -e "${RED}SQL Server needs a password for this login.${NC}"
            continue
        fi
        break
    done
fi

ui_section "Configuration"
ui_kv "Project" "$RAW_PROJECT_NAME"
ui_kv "Folder" "${CURRENT_DIR}/${PROJECT_FOLDER}"
ui_kv "Architecture" "${ENV_MODE^^}"
ui_kv "PHP runtime" "${PHP_BIN} (PHP ${TARGET_PHP})"
ui_kv "Laravel" "$LARAVEL_PKG"
ui_kv "Database" "$DB_CONN"
if [ "$DB_CONN" = "mysql" ]; then
        if [ "$MYSQL_ENGINE" = "xampp_mysql" ]; then ui_kv "MySQL engine" "XAMPP MySQL (/opt/lampp)"; else ui_kv "MySQL engine" "Native MySQL/MariaDB"; fi
        ui_kv "Host:port" "${DB_HOST}:${DB_PORT}"
        ui_kv "Database name" "$DB_NAME"
        ui_kv "Database user" "$DB_USER"
    elif [ "$DB_CONN" = "pgsql" ] || [ "$DB_CONN" = "sqlsrv" ]; then
        ui_kv "Host:port" "${DB_HOST}:${DB_PORT}"
        ui_kv "Database name" "$DB_NAME"
        ui_kv "Database user" "$DB_USER"
    else
        ui_kv "Database file" "${CURRENT_DIR}/${PROJECT_FOLDER}/database/database.sqlite"
    fi
echo ""
ui_rule
echo ""

if ! ui_confirm "Generate the project with these settings?" "y"; then
    echo -e "${RED}Aborted by user.${NC}"
    exit 0
fi

# ------------------------------------------------------------------------------
# STEP 4: Install, Provision & Verify the Database
# ------------------------------------------------------------------------------
ui_step 4 6 "Database setup"

echo -e "${CYAN}Preparing the ${DB_CONN} database...${NC}"

mysql_query() {
    local bin="$1" sql="$2"
    if [ -n "$DB_PASS" ]; then
        MYSQL_PWD="$DB_PASS" "$bin" -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -e "$sql"
    else
        "$bin" -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -e "$sql"
    fi
}

wait_for_mysql() {
    local bin="$1" i
    for i in $(seq 1 30); do
        if [ -n "$DB_PASS" ]; then
            MYSQL_PWD="$DB_PASS" "$bin" -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -e "SELECT 1" >/dev/null 2>&1 && return 0
        else
            "$bin" -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -e "SELECT 1" >/dev/null 2>&1 && return 0
        fi
        sleep 1
    done
    return 1
}

ensure_sqlsrv_driver() {
    if have_php_ext pdo_sqlsrv; then
        echo -e "  ${GREEN}[OK]${NC} PHP extension ${BOLD}pdo_sqlsrv${NC} is available."
        return 0
    fi

    echo -e "  ${YELLOW}[WARN]${NC} PHP extension pdo_sqlsrv is missing."

    case "$PHP_BIN" in
        /opt/lampp/*)
            if [ "$PHP_BIN" != "$SYSTEM_PHP_BIN" ]; then
                echo -e "  ${YELLOW}[WARN]${NC} XAMPP PHP cannot load system-built SQL Server drivers."
                echo -e "  Switching to ${SYSTEM_PHP_BIN} and serving with 'artisan serve'."
                switch_to_system_php
            else
                echo -e "  ${RED}[ERROR]${NC} The XAMPP PHP cannot load system-built SQL Server drivers."
                echo -e "  Use Native mode, or enable pdo_sqlsrv manually in /opt/lampp/etc/php.ini."
                return 1
            fi
            ;;
    esac

    local ms_odbc_ready="0"
    if command -v odbcinst >/dev/null 2>&1 && odbcinst -q -d 2>/dev/null | grep -qi "SQL Server"; then
        ms_odbc_ready="1"
    fi

    if [ "$ms_odbc_ready" = "0" ] && command -v apt-get >/dev/null 2>&1; then
        apt_update_once
        if apt-cache show msodbcsql18 >/dev/null 2>&1 || apt-cache show msodbcsql17 >/dev/null 2>&1; then
            if ui_confirm "Download and install the Microsoft ODBC driver now?" "y"; then
                if apt-cache show msodbcsql18 >/dev/null 2>&1; then
                    echo -e "  ${YELLOW}[INFO]${NC} Installing Microsoft ODBC Driver 18..."
                    ( $SUDO ACCEPT_EULA=Y apt-get install -y msodbcsql18 unixodbc-dev >/dev/null 2>&1 ) || true
                else
                    echo -e "  ${YELLOW}[INFO]${NC} Installing Microsoft ODBC Driver 17..."
                    ( $SUDO ACCEPT_EULA=Y apt-get install -y msodbcsql17 unixodbc-dev >/dev/null 2>&1 ) || true
                fi
            else
                echo -e "  ${RED}[SKIP]${NC} Skipped the ODBC driver install."
            fi
        fi
        if odbcinst -q -d 2>/dev/null | grep -qi "SQL Server"; then
            ms_odbc_ready="1"
        fi
    fi

    if [ "$ms_odbc_ready" = "0" ]; then
        echo -e "  ${RED}[ERROR]${NC} Microsoft ODBC Driver for SQL Server is not installed."
        echo -e "  Install it, then re-run this script:"
        echo -e "    ${BOLD}curl https://packages.microsoft.com/keys/microsoft.asc | $SUDO tee /etc/apt/trusted.gpg.d/microsoft.asc${NC}"
        echo -e "    ${BOLD}curl https://packages.microsoft.com/config/debian/12/prod.list | $SUDO tee /etc/apt/sources.list.d/mssql-release.list${NC}"
        echo -e "    ${BOLD}$SUDO apt update${NC}"
        echo -e "    ${BOLD}$SUDO ACCEPT_EULA=Y apt install -y msodbcsql18 mssql-tools18 unixodbc-dev${NC}"
        return 1
    fi

    if ! command -v pecl >/dev/null 2>&1; then
        if ui_confirm "Download and install the PHP build tools needed for pdo_sqlsrv?" "y"; then
            apt_update_once
            $SUDO apt-get install -y "php${PHP_MINOR}-dev" >/dev/null 2>&1 || \
                $SUDO apt-get install -y php-dev >/dev/null 2>&1 || true
        fi
    fi

    if command -v pecl >/dev/null 2>&1; then
        echo -e "  ${YELLOW}[INFO]${NC} Building pdo_sqlsrv with pecl (this can take a minute)..."
        printf '\n\n\n' | $SUDO pecl install -f sqlsrv pdo_sqlsrv >/dev/null 2>&1 || true

        local ini_dir="/etc/php/${PHP_MINOR}/mods-available"
        if [ -d "$ini_dir" ]; then
            printf 'extension=sqlsrv.so\n' | $SUDO tee "${ini_dir}/sqlsrv.ini" >/dev/null
            printf 'extension=pdo_sqlsrv.so\n' | $SUDO tee "${ini_dir}/pdo_sqlsrv.ini" >/dev/null
            $SUDO phpenmod -v "$PHP_MINOR" sqlsrv pdo_sqlsrv >/dev/null 2>&1 || true
        fi
    fi

    if have_php_ext pdo_sqlsrv; then
        echo -e "  ${GREEN}[OK]${NC} pdo_sqlsrv installed."
        return 0
    fi

    echo -e "  ${RED}[ERROR]${NC} pdo_sqlsrv is still unavailable for PHP ${PHP_MINOR}."
    echo -e "  Try: ${BOLD}$SUDO pecl install sqlsrv pdo_sqlsrv${NC}, then enable pdo_sqlsrv in php.ini."
    return 1
}

case "$DB_CONN" in
    mysql)
        require_php_ext_for_db pdo_mysql || exit 1

        if [ "$MYSQL_ENGINE" = "xampp_mysql" ]; then
            if systemctl is-active --quiet mysql 2>/dev/null || systemctl is-active --quiet mariadb 2>/dev/null; then
                echo -e "${YELLOW}[INFO] Stopping native MySQL to free port ${DB_PORT} for XAMPP MySQL...${NC}"
                $SUDO systemctl stop mysql 2>/dev/null || $SUDO systemctl stop mariadb 2>/dev/null || true
            fi

            if [ "$ENV_MODE" = "xampp" ]; then
                $SUDO /opt/lampp/lampp start
            else
                echo -e "${YELLOW}[INFO] Starting XAMPP MySQL Engine...${NC}"
                $SUDO /opt/lampp/lampp startmysql
            fi
            MYSQL_BIN="/opt/lampp/bin/mysql"

            if ! wait_for_mysql "$MYSQL_BIN"; then
                echo -e "${RED}[ERROR] XAMPP MySQL did not accept the login for '${DB_USER}'.${NC}"
                echo -e "XAMPP's default root password is empty; re-run and leave the password blank."
                exit 1
            fi

            mysql_query "$MYSQL_BIN" "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || {
                echo -e "${RED}[ERROR] Could not create database '${DB_NAME}' as '${DB_USER}'.${NC}"
                exit 1
            }
        else
            if ! command -v mysql >/dev/null 2>&1; then
                echo -e "${YELLOW}[WARN] Native MySQL/MariaDB server not found.${NC}"
                if ui_confirm "Download and install default-mysql-server now?" "y"; then
                    apt_update_once
                    $SUDO apt-get install -y default-mysql-server || true
                else
                    echo -e "  ${RED}[SKIP]${NC} Skipped the MySQL/MariaDB server install."
                fi
            fi

            if [ -x "/opt/lampp/lampp" ]; then
                $SUDO /opt/lampp/lampp stopmysql >/dev/null 2>&1 || true
            fi

            echo -e "${YELLOW}[INFO] Starting native MySQL/MariaDB service...${NC}"
            $SUDO systemctl start mysql 2>/dev/null || $SUDO systemctl start mariadb 2>/dev/null || $SUDO service mysql start 2>/dev/null || true

            MYSQL_BIN="mysql"

            if ! wait_for_mysql "$MYSQL_BIN"; then
                echo -e "${YELLOW}[INFO] TCP login failed; configuring the database through the local root socket...${NC}"
                $SUDO mysql -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || true

                if [ -n "$DB_PASS" ]; then
                    $SUDO mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}'; ALTER USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}'; GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1'; FLUSH PRIVILEGES;" || true
                else
                    $SUDO mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1'; GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1'; FLUSH PRIVILEGES;" || true
                fi

                if ! wait_for_mysql "$MYSQL_BIN"; then
                    echo -e "${RED}[ERROR] MySQL is running but '${DB_USER}' cannot log in over TCP on ${DB_HOST}:${DB_PORT}.${NC}"
                    echo -e "Set a password for '${DB_USER}' in MySQL, or choose SQLite instead."
                    exit 1
                fi
            else
                mysql_query "$MYSQL_BIN" "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || {
                    echo -e "${RED}[ERROR] Could not create database '${DB_NAME}' as '${DB_USER}'.${NC}"
                    exit 1
                }
            fi
        fi
        ;;

    pgsql)
        require_php_ext_for_db pdo_pgsql || exit 1

        if ! command -v psql >/dev/null 2>&1; then
            echo -e "${YELLOW}[WARN] PostgreSQL server not found.${NC}"
            if ui_confirm "Download and install postgresql now?" "y"; then
                apt_update_once
                $SUDO apt-get install -y postgresql postgresql-contrib || true
            else
                echo -e "  ${RED}[SKIP]${NC} Skipped the PostgreSQL server install."
            fi
        fi

        if ! command -v psql >/dev/null 2>&1; then
            echo -e "${RED}[ERROR] PostgreSQL could not be installed. Install it manually and re-run.${NC}"
            exit 1
        fi

        echo -e "${YELLOW}[INFO] Starting PostgreSQL service...${NC}"
        $SUDO systemctl start postgresql 2>/dev/null || $SUDO service postgresql start 2>/dev/null || true

        if command -v pg_isready >/dev/null 2>&1; then
            for i in $(seq 1 30); do
                pg_isready -q -h "$DB_HOST" -p "$DB_PORT" && break
                sleep 1
            done
        fi

        echo -e "${YELLOW}[INFO] Creating role '${DB_USER}' and database '${DB_NAME}'...${NC}"
        if ! as_postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname = '${DB_USER}'" | grep -q 1; then
            as_postgres psql -v ON_ERROR_STOP=1 -c "CREATE ROLE \"${DB_USER}\" LOGIN" >/dev/null
        fi
        as_postgres psql -v ON_ERROR_STOP=1 -c "ALTER ROLE \"${DB_USER}\" WITH LOGIN PASSWORD '${DB_PASS}';" >/dev/null

        if ! as_postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname = '${DB_NAME}'" | grep -q 1; then
            as_postgres createdb -O "${DB_USER}" "${DB_NAME}"
        fi
        as_postgres psql -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "GRANT ALL ON SCHEMA public TO \"${DB_USER}\";" >/dev/null
        ;;

    sqlite)
        require_php_ext_for_db pdo_sqlite || exit 1
        echo -e "${YELLOW}[INFO] SQLite needs no server; the database file is created with the project.${NC}"
        ;;

    sqlsrv)
        ensure_sqlsrv_driver || exit 1

        SQLCMD_BIN="$(command -v sqlcmd || true)"
        if [ -z "$SQLCMD_BIN" ] && [ -x /opt/mssql-tools18/bin/sqlcmd ]; then
            SQLCMD_BIN="/opt/mssql-tools18/bin/sqlcmd"
        elif [ -z "$SQLCMD_BIN" ] && [ -x /opt/mssql-tools/bin/sqlcmd ]; then
            SQLCMD_BIN="/opt/mssql-tools/bin/sqlcmd"
        fi

        if [ -n "$SQLCMD_BIN" ]; then
            echo -e "${YELLOW}[INFO] Ensuring database '${DB_NAME}' exists on ${DB_HOST}:${DB_PORT}...${NC}"
            SQLCMDPASSWORD="$DB_PASS" "$SQLCMD_BIN" -S "${DB_HOST},${DB_PORT}" -U "$DB_USER" -l 10 \
                -Q "IF DB_ID('${DB_NAME}') IS NULL CREATE DATABASE [${DB_NAME}];" >/dev/null || \
                echo -e "${YELLOW}[WARN] sqlcmd could not create the database; make sure '${DB_NAME}' exists.${NC}"
        else
            echo -e "${YELLOW}[WARN] sqlcmd not found (mssql-tools18). Make sure '${DB_NAME}' exists.${NC}"
        fi
        ;;
esac

if [ "$DB_CONN" != "sqlite" ]; then
    echo -e "\n${CYAN}Verifying ${DB_CONN} login to ${DB_HOST}:${DB_PORT}/${DB_NAME}...${NC}"
    if DB_TEST_RESULT="$(db_ping "$DB_CONN" "$DB_HOST" "$DB_PORT" "$DB_NAME" "$DB_USER" "$DB_PASS")"; then
        echo -e "${GREEN}[OK]${NC} Database connection verified."
    else
        echo -e "${RED}[ERROR] Could not connect: ${DB_TEST_RESULT}${NC}"
        ui_confirm "Continue anyway?" "n" || exit 1
    fi
fi

ui_pause "Database ready. Press enter to build the project"

# ------------------------------------------------------------------------------
# STEP 5: Generate Laravel Project
# ------------------------------------------------------------------------------
ui_step 5 6 "Project generation"

echo -e "${YELLOW}[INFO] Installing Laravel ${LARAVEL_VERSION} with ${PHP_BIN}...${NC}"
ui_spin "Creating Laravel ${LARAVEL_VERSION} project" run_composer create-project "$LARAVEL_PKG" "$PROJECT_FOLDER" --no-scripts --no-interaction --prefer-dist

cd "${CURRENT_DIR}/${PROJECT_FOLDER}"

# Register discovered packages (create-project ran with --no-scripts)
ui_spin "Optimizing the autoloader" run_composer dump-autoload --no-interaction
ui_pause "Project generated. Press enter to configure the environment"

# ------------------------------------------------------------------------------
# STEP 6: Configure .env, Permissions, & Migrations
# ------------------------------------------------------------------------------
ui_step 6 6 "Environment & migrations"

cp -f .env.example .env

if [ "$SERVE_MODE" = "apache" ]; then
    APP_URL_VAL="http://localhost/${PROJECT_FOLDER}/public"
else
    APP_URL_VAL="http://127.0.0.1:8000"
fi

set_env .env APP_NAME "$(env_quote "$RAW_PROJECT_NAME")"
set_env .env APP_URL "$(env_quote "$APP_URL_VAL")"
set_env .env DB_CONNECTION "$DB_CONN"

case "$DB_CONN" in
    sqlite)
        SQLITE_PATH="${CURRENT_DIR}/${PROJECT_FOLDER}/database/database.sqlite"
        touch "$SQLITE_PATH"
        set_env .env DB_DATABASE "$(env_quote "$SQLITE_PATH")"
        ;;
    mysql|pgsql|sqlsrv)
        set_env .env DB_HOST "$DB_HOST"
        set_env .env DB_PORT "$DB_PORT"
        set_env .env DB_DATABASE "$(env_quote "$DB_NAME")"
        set_env .env DB_USERNAME "$(env_quote "$DB_USER")"
        set_env .env DB_PASSWORD "$(env_quote "$DB_PASS")"

        if [ "$DB_CONN" = "sqlsrv" ]; then
            case "$DB_HOST" in
                127.0.0.1|localhost|::1)
                    # Local SQL Server / Docker containers use self-signed certificates
                    set_env .env DB_ENCRYPT "no"
                    set_env .env DB_TRUST_SERVER_CERTIFICATE "true"
                    ;;
            esac
        fi
        ;;
esac

ui_spin "Generating the application key" "$PHP_BIN" artisan key:generate --ansi

CURRENT_USER="$(id -un)"
if [ "$SERVE_MODE" = "apache" ]; then
    $SUDO chown -R "${CURRENT_USER}:daemon" storage bootstrap/cache
    $SUDO chmod -R 775 storage bootstrap/cache
else
    chmod -R 775 storage bootstrap/cache
fi

if [ "$DB_CONN" = "sqlite" ]; then
    if DB_TEST_RESULT="$(db_ping sqlite "" "" "$SQLITE_PATH" "" "")"; then
        echo -e "${GREEN}[OK]${NC} SQLite database file verified."
    else
        echo -e "${RED}[ERROR] SQLite check failed: ${DB_TEST_RESULT}${NC}"
        exit 1
    fi
fi

ui_spin "Running database migrations" "$PHP_BIN" artisan migrate --force

if [ -f "package.json" ] && command -v npm &>/dev/null; then
    echo -e "${YELLOW}[INFO] Installing npm packages and building assets...${NC}"
    ui_spin "Installing npm packages" npm install
    ui_spin "Building frontend assets" npm run build
fi

# ------------------------------------------------------------------------------
# Success screen
# ------------------------------------------------------------------------------
svc_start_hint() { # service -> "sudo systemctl start x" (or without sudo)
    if [ -n "$SUDO" ]; then printf '%s systemctl start %s' "$SUDO" "$1"
    else printf 'systemctl start %s' "$1"; fi
}

ui_clear
echo ""
ui_logo "READY"
ui_center "Your Laravel ${LARAVEL_VERSION} application is ready." "$GREEN"

PROJECT_PATH="${CURRENT_DIR}/${PROJECT_FOLDER}"
SUDO_PREFIX=""
[ -n "$SUDO" ] && SUDO_PREFIX="${SUDO} "

ui_section "Project"
ui_kv "Location" "$PROJECT_PATH"
ui_kv "PHP runtime" "${PHP_BIN} (PHP ${TARGET_PHP})"
if [ "$DB_CONN" = "sqlite" ]; then
    ui_kv "Database" "SQLite (${SQLITE_PATH})"
else
    ui_kv "Database" "${DB_CONN} - ${DB_NAME} at ${DB_HOST}:${DB_PORT}"
fi

if [ "$DB_CONN" = "mysql" ]; then
    if [ "$MYSQL_ENGINE" = "xampp_mysql" ]; then
        ui_kv "DB engine" "XAMPP MySQL (/opt/lampp/lampp startmysql)"
    else
        ui_kv "DB engine" "MySQL/MariaDB ($(svc_start_hint mysql))"
    fi
elif [ "$DB_CONN" = "pgsql" ]; then
    ui_kv "DB engine" "PostgreSQL ($(svc_start_hint postgresql))"
elif [ "$DB_CONN" = "sqlsrv" ]; then
    ui_kv "DB engine" "SQL Server at ${DB_HOST}:${DB_PORT}"
fi

# ------------------------------------------------------------------------------
# How to start the app
# ------------------------------------------------------------------------------
if [ "$SERVE_MODE" = "apache" ]; then
    LAMPP_START="/opt/lampp/lampp start"
    LAMPP_RESTART="/opt/lampp/lampp restartapache"
    [ -n "$SUDO" ] && LAMPP_START="${SUDO} ${LAMPP_START}" && LAMPP_RESTART="${SUDO} ${LAMPP_RESTART}"

    case "$PROJECT_PATH" in
        /opt/lampp/htdocs/*) PROJECT_WEB_PATH="${PROJECT_PATH#/opt/lampp/htdocs/}" ;;
        *)                   PROJECT_WEB_PATH="" ;;
    esac

    if [ -n "$PROJECT_WEB_PATH" ]; then
        ui_panel "START THE APP (XAMPP APACHE)" \
            "1. ${LAMPP_START}     start Apache and MySQL" \
            "2. Open ${APP_URL_VAL}" \
            "3. After editing .env: ${LAMPP_RESTART}" \
            "" \
            "Project folder: /opt/lampp/htdocs/${PROJECT_WEB_PATH}" \
            "phpMyAdmin:     http://localhost/phpmyadmin"
    else
        ui_panel "START THE APP (XAMPP APACHE)" \
            "The project is outside /opt/lampp/htdocs, so Apache cannot" \
            "see it yet. Link it in, then open the site:" \
            "" \
            "  cd /opt/lampp/htdocs" \
            "  ${SUDO_PREFIX}ln -s ${PROJECT_PATH} ${PROJECT_FOLDER}" \
            "  ${LAMPP_RESTART}" \
            "  Open http://localhost/${PROJECT_FOLDER}/public" \
            "" \
            "Or run it without Apache:" \
            "  cd ${PROJECT_PATH}" \
            "  ${PHP_BIN} artisan serve"
    fi
else
    ui_panel "START THE APP (PHP DEV SERVER)" \
        "1. cd ${PROJECT_PATH}" \
        "2. ${PHP_BIN} artisan serve" \
        "3. Open http://127.0.0.1:8000" \
        "" \
        "Ctrl+C stops the server. Other options:" \
        "  ${PHP_BIN} artisan serve --port=8080       use another port" \
        "  ${PHP_BIN} artisan serve --host=0.0.0.0    allow other devices" \
        "" \
        "Add features, then run '${PHP_BIN} artisan migrate' for new migrations."
fi
echo ""

# ------------------------------------------------------------------------------
# How to reach the database: terminal client and web admin for this driver
# ------------------------------------------------------------------------------
GUIDE=()

if [ "$DB_CONN" = "mysql" ]; then
    if [ "$MYSQL_ENGINE" = "xampp_mysql" ] && [ -x /opt/lampp/bin/mysql ]; then
        MYSQL_CLIENT="/opt/lampp/bin/mysql"
    else
        MYSQL_CLIENT="mysql"
    fi

    MYSQL_FLAVOR="MySQL"
    if command -v "$MYSQL_CLIENT" >/dev/null 2>&1 && "$MYSQL_CLIENT" --version 2>/dev/null | grep -qi 'mariadb'; then
        MYSQL_FLAVOR="MariaDB"
    fi

    if command -v "$MYSQL_CLIENT" >/dev/null 2>&1; then
        GUIDE+=("Terminal client: ${MYSQL_CLIENT} (${MYSQL_FLAVOR})" "")
    else
        GUIDE+=("The mysql client is not on your PATH - install mysql-client or" \
            "use /opt/lampp/bin/mysql instead of 'mysql' below." "")
    fi

    GUIDE+=(
        "  ${MYSQL_CLIENT} -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER} -p ${DB_NAME}"
        "  (type the password when asked; '-p' always prompts)"
        ""
        "  SHOW DATABASES;               list every database"
        "  SHOW TABLES;                  list tables in ${DB_NAME}"
        "  DESCRIBE users;               columns and types of a table"
        "  SELECT * FROM users LIMIT 10; read rows"
        "  EXIT;   (or Ctrl+D)           leave the client"
        ""
        "One-shot query from the shell:"
        "  ${MYSQL_CLIENT} -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER} -p -e 'SHOW TABLES' ${DB_NAME}"
        ""
    )

    if [ "$MYSQL_ENGINE" = "xampp_mysql" ]; then
        GUIDE+=(
            "Web admin (XAMPP phpMyAdmin): http://localhost/phpmyadmin"
            "  Log in as '${DB_USER}' (XAMPP default: root, empty password),"
            "  pick ${DB_NAME} on the left, then Browse or run SQL."
        )
    else
        GUIDE+=(
            "Web admin: MySQL Workbench, DBeaver or Adminer."
            "  phpMyAdmin works too when it is installed - open"
            "  http://localhost/phpmyadmin and log in as '${DB_USER}'."
        )
    fi
    ui_panel "DATABASE ACCESS - ${MYSQL_FLAVOR}" "${GUIDE[@]}"
elif [ "$DB_CONN" = "pgsql" ]; then
    if command -v psql >/dev/null 2>&1; then
        GUIDE+=("Terminal client: psql" "")
    else
        GUIDE+=("psql is not installed - install it with your package manager" \
            "(postgresql-client) to use these commands." "")
    fi

    GUIDE+=(
        "  psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d ${DB_NAME}"
        "  (type the password when asked)"
        ""
        "  \\l                    list every database"
        "  \\dt                   list tables in ${DB_NAME}"
        "  \\d users              columns, types and indexes of a table"
        "  SELECT * FROM users LIMIT 10;"
        "  \\q                    leave the client"
        ""
        "One-shot query from the shell:"
        "  psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d ${DB_NAME} -c '\\dt'"
        ""
        "Web admin: pgAdmin (desktop or docker) or Adminer/phpPgAdmin."
        "  phpMyAdmin only reads MySQL, so it cannot open this database."
    )
    ui_panel "DATABASE ACCESS - POSTGRESQL" "${GUIDE[@]}"
elif [ "$DB_CONN" = "sqlite" ]; then
    if command -v sqlite3 >/dev/null 2>&1; then
        GUIDE+=("Terminal client: sqlite3" "")
    else
        GUIDE+=("sqlite3 is not installed - install the sqlite3 package to use" \
            "these commands, or use 'php artisan db:show' instead." "")
    fi

    GUIDE+=(
        "  sqlite3 ${SQLITE_PATH}"
        ""
        "  .databases             show the database file"
        "  .tables                list tables"
        "  .schema users          SQL that created a table"
        "  SELECT * FROM users LIMIT 10;"
        "  .quit                  leave the client"
        ""
        "One-shot query from the shell:"
        "  sqlite3 ${SQLITE_PATH} '.tables'"
        ""
        "Web admin: DB Browser for SQLite, TablePlus or phpLiteAdmin."
        "  phpMyAdmin does not support SQLite."
    )
    ui_panel "DATABASE ACCESS - SQLITE" "${GUIDE[@]}"
else
    if command -v sqlcmd >/dev/null 2>&1; then
        GUIDE+=("Terminal client: sqlcmd" "")
    else
        GUIDE+=("sqlcmd is not installed - install mssql-tools18 to use these" \
            "commands, or use 'php artisan db:show' instead." "")
    fi

    GUIDE+=(
        "  sqlcmd -S ${DB_HOST},${DB_PORT} -U ${DB_USER} -d ${DB_NAME}"
        "  (type the password when asked; GO runs a statement)"
        ""
        "  SELECT name FROM sys.databases;      list every database"
        "  SELECT name FROM sys.tables;         list tables in ${DB_NAME}"
        "  SELECT * FROM INFORMATION_SCHEMA.TABLES;"
        "  EXEC sp_help 'users';                describe a table"
        "  GO"
        "  QUIT"
        ""
        "One-shot query from the shell:"
        "  sqlcmd -S ${DB_HOST},${DB_PORT} -U ${DB_USER} -d ${DB_NAME} -Q 'SELECT name FROM sys.tables'"
        ""
        "Web admin: Azure Data Studio or SQL Server Management Studio."
        "  phpMyAdmin cannot open SQL Server databases."
    )
    ui_panel "DATABASE ACCESS - SQL SERVER" "${GUIDE[@]}"
fi

echo ""
ui_panel "INSPECT DATA - WORKS FOR EVERY DRIVER" \
    "Run these from ${PROJECT_PATH}:" \
    "" \
    "  ${PHP_BIN} artisan db:show" \
    "      Connection, driver, database and table sizes." \
    "  ${PHP_BIN} artisan db:show --counts" \
    "      Same, with a row count for every table." \
    "  ${PHP_BIN} artisan db:table users" \
    "      Columns, indexes and row count of one table." \
    "  ${PHP_BIN} artisan tinker" \
    "      DB::table('users')->count();" \
    "      DB::table('users')->limit(10)->get();"

echo ""

# ------------------------------------------------------------------------------
# Optional GUI: MySQL Workbench, pre-connected to the database just created
# ------------------------------------------------------------------------------
#if [ "$DB_CONN" = "mysql" ]; then
#    WORKBENCH_BIN="$(command -v mysql-workbench || true)"
#
#    if [ -z "$WORKBENCH_BIN" ]; then
#        echo -e "  ${MUTED}MySQL Workbench (the desktop GUI for MySQL/MariaDB) is not installed.${NC}"
#        if ui_confirm "Download and install MySQL Workbench?" "n"; then
#            WANTED=0
#            case "$PM" in
#                apt-get) apt-cache show mysql-workbench >/dev/null 2>&1 && WANTED=1 ;;
#                dnf|pacman|zypper) WANTED=1 ;;
#            esac
#
#            if [ "$WANTED" = "1" ]; then
#                ui_spin "Installing MySQL Workbench" install_packages mysql-workbench || true
#                WORKBENCH_BIN="$(command -v mysql-workbench || true)"
#            else
#                echo -e "  ${YELLOW}[WARN]${NC} mysql-workbench is not in your package repos."
#                echo -e "  ${MUTED}Get it from https://dev.mysql.com/downloads/workbench/ then re-run.${NC}"
#            fi
#        fi
#    fi
#
#    if [ -n "$WORKBENCH_BIN" ]; then
#        echo -e "  ${GREEN}[OK]${NC} MySQL Workbench: ${BOLD}${WORKBENCH_BIN}${NC}"
#
#        if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
#            if ui_confirm "Open MySQL Workbench connected to '${DB_NAME}'?" "n"; then
#                ( nohup "$WORKBENCH_BIN" --query "${DB_USER}@${DB_HOST}:${DB_PORT}" >/dev/null 2>&1 & )
#                echo -e "  ${GREEN}[OK]${NC} MySQL Workbench is starting - pick the password for '${DB_USER}' if it asks."
#            fi
#        else
#            echo -e "  ${MUTED}No desktop session detected, so Workbench was not launched.${NC}"
#            echo -e "  ${MUTED}Run: mysql-workbench --query \"${DB_USER}@${DB_HOST}:${DB_PORT}\"${NC}"
#        fi
#    fi
#
#    echo ""
#fi

#!/usr/bin/env bash
# =============================================================================
# Laravel setup - macOS
#
# - Picks a PHP runtime that can run the current Laravel
# - Installs MySQL, MariaDB, PostgreSQL or SQLite with Homebrew
# - Creates the database and verifies the login
# - Writes .env, runs the first migrations and builds the front-end assets
# =============================================================================
set -uo pipefail

CURRENT_DIR="$(pwd)"
PROJECT_FOLDER=""; RAW_PROJECT_NAME=""
DB_CONN=""; DB_NAME=""; DB_HOST=""; DB_PORT=""; DB_USER=""; DB_PASS=""
PHP_BIN=""; TARGET_PHP=""; SQLITE_PATH=""
STARTED_SERVICE=""

IS_TTY=0; [ -t 1 ] && IS_TTY=1
if [ "$IS_TTY" = "1" ]; then
  E=$'\033'
  GREEN="${E}[38;5;114m"; YELLOW="${E}[38;5;179m"; RED="${E}[38;5;203m"
  CYAN="${E}[38;5;111m"; ACCENT="${E}[38;5;111m"; MUTED="${E}[38;5;244m"
  BOLD="${E}[1m"; DIM="${E}[2m"; NC="${E}[0m"
else
  GREEN=""; YELLOW=""; RED=""; CYAN=""; ACCENT=""; MUTED=""; BOLD=""; DIM=""; NC=""
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
step() { ui_clear; printf '\n%s❯%s %sstep %s of %s%s · %s%s%s\n' "$ACCENT" "$NC" "$MUTED" "$1" "$2" "$NC" "$BOLD" "$3" "$NC"; ui_rule; echo; }
kv()   { printf '  %s%-16s%s %s\n' "$MUTED" "$1" "$NC" "$2"; }

INPUT_DEV=""
if ( exec </dev/tty ) 2>/dev/null; then INPUT_DEV="/dev/tty"
elif [ -t 0 ]; then INPUT_DEV="/dev/stdin"; fi

ask() { # prompt default
  local q="$1" d="${2:-}" a=""
  if [ -z "$INPUT_DEV" ]; then printf '%s' "$d"; return 0; fi
  printf '  %s%s%s ' "$BOLD" "$q" "$NC"
  IFS= read -r a <"$INPUT_DEV" || a=""
  [ -z "$a" ] && a="$d"
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
confirm() {
  local q="$1" d="${2:-n}" a=""
  [ -z "$INPUT_DEV" ] && { [ "$d" = "y" ]; return; }
  printf '  %s%s%s [%s/%s] ' "$BOLD" "$q" "$NC" "$([ "$d" = y ] && echo Y || echo y)" "$([ "$d" = y ] && echo n || echo N)"
  IFS= read -r a <"$INPUT_DEV" || a=""
  [ -z "$a" ] && a="$d"
  case "$a" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

menu_select() {
  local title="$1" def="$2"; shift 2
  local count=$# sel="$def" key rest i
  if [ "$IS_TTY" != "1" ] || [ -z "$INPUT_DEV" ]; then
    echo "$title"
    i=1; for x in "$@"; do printf '  %d) %s\n' "$i" "$x"; i=$((i + 1)); done
    printf 'Choose [1-%d] (default %d): ' "$count" "$((def + 1))"
    IFS= read -r ans </dev/stdin || ans=""
    case "$ans" in ''|*[!0-9]*) MENU_RESULT="$def" ;; *) MENU_RESULT=$((ans - 1)) ;; esac
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

spin() { # label command...
  local label="$1"; shift
  local frame=0 frames='|/-\'
  "$@" >/tmp/laravel-mac-step.log 2>&1 &
  local pid=$!
  if [ "$IS_TTY" = "1" ]; then
    while kill -0 "$pid" 2>/dev/null; do
      printf '\r  %s%s%s %s' "$ACCENT" "${frames:$frame:1}" "$NC" "$label"
      frame=$(( (frame + 1) % 4 ))
      sleep 0.15
    done
    printf '\r%*s\r' "$((${#label} + 6))" ''
  fi
  wait "$pid"; local rc=$?
  if [ "$rc" -eq 0 ]; then ok "$label"; else
    err "$label"
    tail -n 20 /tmp/laravel-mac-step.log | sed 's/^/      /'
  fi
  return "$rc"
}

php_version() { "$1" -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null; }
php_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

ui_clear
ui_panel "$ACCENT" "LARAVEL SETUP · macOS" \
  "PHP, a database and a working app in one guided run." \
  "" \
  "Folder: $CURRENT_DIR" \
  "Nothing is installed until you confirm the packages."
echo

# -----------------------------------------------------------------------------
# 1. Homebrew and dependencies
# -----------------------------------------------------------------------------
step 1 6 "Homebrew and tools"
if command -v brew >/dev/null 2>&1; then
  ok "Homebrew $(brew --version | head -1 | awk '{print $2}')"
else
  warn "Homebrew is required to install PHP and the database."
  if confirm "Install Homebrew now (it asks for your password once)?" y; then
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"; fi
    if [ -x /usr/local/bin/brew ]; then eval "$(/usr/local/bin/brew shellenv)"; fi
    command -v brew >/dev/null 2>&1 || { err "Homebrew install failed."; exit 1; }
    ok "Homebrew installed"
  else
    err "Homebrew is required. Install it from https://brew.sh and run again."
    exit 1
  fi
fi
for cmd in curl git; do
  command -v "$cmd" >/dev/null 2>&1 && ok "$cmd found" || { err "$cmd is missing."; exit 1; }
done

# -----------------------------------------------------------------------------
# 2. PHP runtime
# -----------------------------------------------------------------------------
step 2 6 "PHP runtime"
PHP_CANDIDATES=()
add_candidate() { # path
  [ -n "$1" ] && [ -x "$1" ] || return 0
  local v; v="$(php_version "$1")"
  php_ge "${v:-0}" 8.2 || return 0
  for existing in ${PHP_CANDIDATES[@]+"${PHP_CANDIDATES[@]}"}; do
    [ "$existing" = "$1" ] && return 0
  done
  PHP_CANDIDATES+=("$1")
}
add_candidate "$(command -v php || true)"
add_candidate "/opt/homebrew/bin/php"
add_candidate "/usr/local/bin/php"
for v in 8.4 8.3 8.2; do
  add_candidate "/opt/homebrew/opt/php@$v/bin/php"
  add_candidate "/usr/local/opt/php@$v/bin/php"
done

if [ "${#PHP_CANDIDATES[@]}" -gt 0 ]; then
  if [ "${#PHP_CANDIDATES[@]}" -eq 1 ]; then
    PHP_BIN="${PHP_CANDIDATES[0]}"
  else
    LABELS=()
    for candidate in "${PHP_CANDIDATES[@]}"; do
      LABELS+=("$candidate  (PHP $(php_version "$candidate"))")
    done
    menu_select "Which PHP runtime should run Laravel?" 0 "${LABELS[@]}"
    PHP_BIN="${PHP_CANDIDATES[$MENU_RESULT]}"
  fi
  TARGET_PHP="$(php_version "$PHP_BIN")"
  ok "Using $PHP_BIN (PHP $TARGET_PHP)"
else
  warn "No PHP 8.2+ runtime found. Homebrew can install one."
  if confirm "Install PHP with Homebrew (brew install php)?" y; then
    spin "Installing PHP" brew install php || exit 1
    PHP_BIN="$(command -v php || true)"
    [ -z "$PHP_BIN" ] && PHP_BIN="/opt/homebrew/bin/php"
    [ -x "$PHP_BIN" ] || PHP_BIN="/usr/local/bin/php"
    TARGET_PHP="$(php_version "$PHP_BIN")"
    php_ge "${TARGET_PHP:-0}" 8.2 || { err "The installed PHP ($TARGET_PHP) is older than 8.2."; exit 1; }
    ok "Using $PHP_BIN (PHP $TARGET_PHP)"
  else
    err "PHP 8.2+ is required."
    exit 1
  fi
fi

if command -v composer >/dev/null 2>&1; then
  ok "Composer $(composer --version 2>/dev/null | head -1 | awk '{print $3}')"
else
  if ! confirm "Install Composer with Homebrew?" y; then
    err "Composer is required."
    exit 1
  fi
  spin "Installing Composer" brew install composer || exit 1
  command -v composer >/dev/null 2>&1 || { err "Composer is still not on PATH."; exit 1; }
  ok "Composer installed"
fi

# -----------------------------------------------------------------------------
# 3. Database choice and project settings
# -----------------------------------------------------------------------------
step 3 6 "Database and project"
menu_select "Which database should Laravel use?" 0 \
  "MySQL|Homebrew mysql, port 3306" \
  "MariaDB|Homebrew mariadb, port 3306" \
  "PostgreSQL|Homebrew postgresql@17, port 5432" \
  "SQLite|A file in the project, no server" \
  "Existing server|Connect to MySQL or PostgreSQL already running"
DB_CHOICE="$MENU_RESULT"

case "$DB_CHOICE" in
  0) DB_CONN="mysql"; DB_ENGINE_LABEL="MySQL" ;;
  1) DB_CONN="mysql"; DB_ENGINE_LABEL="MariaDB" ;;
  2) DB_CONN="pgsql"; DB_ENGINE_LABEL="PostgreSQL" ;;
  3) DB_CONN="sqlite"; DB_ENGINE_LABEL="SQLite" ;;
  4)
    menu_select "Which driver does the existing server use?" 0 "MySQL / MariaDB" "PostgreSQL"
    case "$MENU_RESULT" in
      0) DB_CONN="mysql"; DB_ENGINE_LABEL="MySQL" ;;
      *) DB_CONN="pgsql"; DB_ENGINE_LABEL="PostgreSQL" ;;
    esac
    ;;
esac

RAW_PROJECT_NAME="$(ask "Project / webapp name (e.g. test-app):" "laravel-app")"
PROJECT_FOLDER="$(printf '%s' "$RAW_PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
[ -n "$PROJECT_FOLDER" ] || { err "Project name must contain a letter or number."; exit 1; }
if [ -d "$CURRENT_DIR/$PROJECT_FOLDER" ]; then
  err "Folder '$CURRENT_DIR/$PROJECT_FOLDER' already exists."
  exit 1
fi
DEFAULT_DB_NAME="$(printf '%s' "$PROJECT_FOLDER" | tr '-' '_')"

if [ "$DB_CONN" = "sqlite" ]; then
  info "SQLite needs no server or credentials."
elif [ "$DB_CONN" = "mysql" ]; then
  DB_NAME="$(ask "Database name:" "$DEFAULT_DB_NAME")"
  DB_HOST="$(ask "Host:" "127.0.0.1")"
  DB_PORT="$(ask "Port:" "3306")"
  DB_USER="$(ask "Username:" "root")"
  DB_PASS="$(ask_secret "Password (blank for a fresh Homebrew install):")"
elif [ "$DB_CONN" = "pgsql" ]; then
  DB_NAME="$(ask "Database name:" "$DEFAULT_DB_NAME")"
  DB_HOST="$(ask "Host:" "127.0.0.1")"
  DB_PORT="$(ask "Port:" "5432")"
  DB_USER="$(ask "Username:" "$(whoami)")"
  DB_PASS="$(ask_secret "Password (blank to use peer/trust auth):")"
fi

ui_clear
ui_panel "$CYAN" "CONFIGURATION" \
  "Project      $RAW_PROJECT_NAME" \
  "Folder       $CURRENT_DIR/$PROJECT_FOLDER" \
  "PHP          $PHP_BIN (PHP $TARGET_PHP)" \
  "Database     $DB_ENGINE_LABEL" \
  "Host:port    ${DB_HOST:-file}${DB_PORT:+:$DB_PORT}" \
  "DB name      ${DB_NAME:-$DEFAULT_DB_NAME}" \
  "DB user      ${DB_USER:-(none)}"
echo
confirm "Generate the project with these settings?" y || { info "Aborted."; exit 0; }

# -----------------------------------------------------------------------------
# 4. Database provisioning
# -----------------------------------------------------------------------------
step 4 6 "Database setup"
DB_NAME="${DB_NAME:-$DEFAULT_DB_NAME}"

wait_for_port() { # host port
  local i
  for i in $(seq 1 30); do
    nc -z "$1" "$2" >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

if [ "$DB_CHOICE" != "4" ] && [ "$DB_CONN" != "sqlite" ]; then
  case "$DB_ENGINE_LABEL" in
    MySQL|MariaDB)
      if [ "$DB_ENGINE_LABEL" = "MariaDB" ]; then SERVICE="mariadb"; FORMULA="mariadb"; else SERVICE="mysql"; FORMULA="mysql"; fi
      if ! command -v mysql >/dev/null 2>&1; then
        spin "Installing $DB_ENGINE_LABEL" brew install "$FORMULA" || exit 1
      else
        ok "$DB_ENGINE_LABEL client found"
      fi
      if ! nc -z "$DB_HOST" "$DB_PORT" >/dev/null 2>&1; then
        spin "Starting $SERVICE" brew services start "$SERVICE" || warn "Could not start $SERVICE; start it yourself."
        STARTED_SERVICE="$SERVICE"
      fi
      ;;
    PostgreSQL)
      if ! command -v psql >/dev/null 2>&1; then
        spin "Installing PostgreSQL" brew install postgresql@17 || exit 1
      else
        ok "psql found"
      fi
      if ! nc -z "$DB_HOST" "$DB_PORT" >/dev/null 2>&1; then
        spin "Starting postgresql@17" brew services start postgresql@17 || warn "Could not start PostgreSQL; start it yourself."
        STARTED_SERVICE="postgresql@17"
      fi
      ;;
  esac
  if wait_for_port "$DB_HOST" "$DB_PORT"; then
    ok "$DB_ENGINE_LABEL is accepting connections on $DB_HOST:$DB_PORT"
  else
    warn "No answer on $DB_HOST:$DB_PORT yet. Continuing; migrations will report a real error if it stays down."
  fi
fi

if [ "$DB_CONN" = "mysql" ]; then
  export MYSQL_PWD="$DB_PASS"
  if mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -e "SELECT 1" >/dev/null 2>&1; then
    ok "Login accepted as $DB_USER"
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" \
      -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" \
      && ok "Database '$DB_NAME' ready" || warn "Could not create '$DB_NAME' (it may already exist)."
  else
    warn "Could not log in as $DB_USER. The wizard continues; fix the credentials and edit .env later."
  fi
  unset MYSQL_PWD
elif [ "$DB_CONN" = "pgsql" ]; then
  export PGPASSWORD="$DB_PASS"
  if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "SELECT 1" >/dev/null 2>&1; then
    ok "Login accepted as $DB_USER"
    if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -tAc \
      "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1; then
      ok "Database '$DB_NAME' already exists"
    else
      psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres \
        -c "CREATE DATABASE \"$DB_NAME\"" && ok "Database '$DB_NAME' created" \
        || warn "Could not create '$DB_NAME'."
    fi
  else
    warn "Could not log in as $DB_USER. Fix the credentials and edit .env later."
  fi
  unset PGPASSWORD
fi

# -----------------------------------------------------------------------------
# 5. Generate the project
# -----------------------------------------------------------------------------
step 5 6 "Project generation"
info "Creating Laravel in $CURRENT_DIR/$PROJECT_FOLDER ..."
if ! spin "composer create-project" composer create-project laravel/laravel "$PROJECT_FOLDER" \
  --no-scripts --no-interaction --prefer-dist; then
  err "composer create-project failed. Check the log above."
  exit 1
fi
cd "$CURRENT_DIR/$PROJECT_FOLDER" || exit 1
spin "Optimising the autoloader" composer dump-autoload --no-interaction || warn "dump-autoload failed"

# -----------------------------------------------------------------------------
# 6. Environment, migrations, assets
# -----------------------------------------------------------------------------
step 6 6 "Environment and migrations"
[ -f .env.example ] || { err ".env.example is missing from the new project."; exit 1; }
cp -f .env.example .env

set_env() { # file key value
  local f="$1" k="$2" v="$3" tmp="$1.tmp.$$"
  awk -v k="$k" -v v="$v" '
    BEGIN { done = 0 }
    $0 ~ "^" k "=" { print k "=" v; done = 1; next }
    { print }
    END { if (!done) print k "=" v }
  ' "$f" >"$tmp" && mv "$tmp" "$f"
}
env_quote() {
  case "$1" in
    *" "*|*"'"*|*'"'*|*'\'*) printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")" ;;
    *) printf '%s' "$1" ;;
  esac
}

set_env .env APP_NAME "$(env_quote "$RAW_PROJECT_NAME")"
set_env .env APP_URL "http://127.0.0.1:8000"
set_env .env DB_CONNECTION "$DB_CONN"

if [ "$DB_CONN" = "sqlite" ]; then
  SQLITE_PATH="$CURRENT_DIR/$PROJECT_FOLDER/database/database.sqlite"
  : >"$SQLITE_PATH"
  set_env .env DB_DATABASE "$(env_quote "$SQLITE_PATH")"
  ok "SQLite file created at $SQLITE_PATH"
else
  set_env .env DB_HOST "$DB_HOST"
  set_env .env DB_PORT "$DB_PORT"
  set_env .env DB_DATABASE "$(env_quote "$DB_NAME")"
  set_env .env DB_USERNAME "$(env_quote "$DB_USER")"
  set_env .env DB_PASSWORD "$(env_quote "$DB_PASS")"
fi

spin "Generating the application key" "$PHP_BIN" artisan key:generate --ansi || exit 1
chmod -R ug+rwx storage bootstrap/cache 2>/dev/null || warn "Could not adjust permissions on storage/"

spin "Running database migrations" "$PHP_BIN" artisan migrate --force || {
  err "Migrations failed. Check the database credentials in .env."
  exit 1
}

if [ -f package.json ] && command -v npm >/dev/null 2>&1; then
  spin "Installing npm packages" npm install || warn "npm install failed; run it yourself."
  spin "Building front-end assets" npm run build || warn "npm run build failed; run it yourself."
fi

# -----------------------------------------------------------------------------
# Success
# -----------------------------------------------------------------------------
ui_clear
ui_panel "$GREEN" "READY" \
  "Laravel 12/13 application created." \
  "" \
  "Location   $CURRENT_DIR/$PROJECT_FOLDER" \
  "PHP        $PHP_BIN (PHP $TARGET_PHP)" \
  "Database   $DB_ENGINE_LABEL${DB_NAME:+ · $DB_NAME}"

echo
ui_panel "$CYAN" "START THE APP" \
  "cd $CURRENT_DIR/$PROJECT_FOLDER" \
  "$PHP_BIN artisan serve" \
  "Open http://127.0.0.1:8000" \
  "" \
  "Ctrl+C stops the server. Another port: php artisan serve --port=8080"

echo
if [ "$DB_CONN" = "mysql" ]; then
  ui_panel "$CYAN" "DATABASE ACCESS" \
    "mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p $DB_NAME" \
    "" \
    "SHOW TABLES;        list tables" \
    "SELECT * FROM users LIMIT 10;" \
    "" \
    "Web admin: MySQL Workbench, TablePlus or DBeaver."
elif [ "$DB_CONN" = "pgsql" ]; then
  ui_panel "$CYAN" "DATABASE ACCESS" \
    "psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME" \
    "" \
    "\\dt                 list tables" \
    "\\d users            describe a table" \
    "\\q                  leave the client" \
    "" \
    "Web admin: pgAdmin, TablePlus or DBeaver."
else
  ui_panel "$CYAN" "DATABASE ACCESS" \
    "sqlite3 $SQLITE_PATH" \
    "" \
    ".tables             list tables" \
    "SELECT * FROM users LIMIT 10;"
fi

echo
kv "Service" "${STARTED_SERVICE:-not started by this script}"
kv "Undo" "Delete the project folder and drop the database '$DB_NAME'."
echo

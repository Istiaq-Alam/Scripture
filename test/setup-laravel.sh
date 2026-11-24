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
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
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
        echo -e "  ${YELLOW}[WARN]${NC} PHP extension ${ext} missing, installing ${pkg}..."
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

db_driver_label() {
    if have_php_ext "$1"; then
        printf '%binstalled%b' "$GREEN" "$NC"
    else
        printf '%bmissing%b' "$RED" "$NC"
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
# Helpers: output
# ------------------------------------------------------------------------------
banner() {
    local text="$1"
    if command -v figlet >/dev/null 2>&1; then
        if command -v lolcat >/dev/null 2>&1; then
            figlet -w 120 -f standard "$text" | lolcat || true
        else
            figlet -w 120 -f standard "$text" || true
        fi
    else
        echo -e "${CYAN}${BOLD}>>> ${text} <<<${NC}"
    fi
}

step_header() {
    local title="$1"
    echo ""
    if command -v figlet >/dev/null 2>&1; then
        if command -v lolcat >/dev/null 2>&1; then
            figlet -w 120 -f small "$title" | lolcat || true
        else
            figlet -w 120 -f small "$title" || true
        fi
    else
        echo -e "${CYAN}${BOLD}--- ${title} ---${NC}"
    fi
}

ensure_display_tools() {
    local missing=() tool
    for tool in figlet lolcat; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done
    [ ${#missing[@]} -eq 0 ] && return 0

    if command -v apt-get >/dev/null 2>&1; then
        echo -e "${YELLOW}[INFO] Installing display tools: ${missing[*]}${NC}"
        apt_update_once
        $SUDO apt-get install -y "${missing[@]}" >/dev/null 2>&1 || true
    fi
}

ensure_display_tools

banner "LARAVEL SETUP"
echo -e "${CYAN}${BOLD}Ultimate Interactive Laravel Project Generator${NC}"
echo -e "Working Directory: ${YELLOW}${CURRENT_DIR}${NC}\n"

# ------------------------------------------------------------------------------
# STEP 1: Environment & Dependency Checks
# ------------------------------------------------------------------------------
step_header "Step 1/6 - Requirements"

if ! command -v php &>/dev/null; then
    echo -e "${RED}[ERROR] PHP is not installed or not in PATH.${NC}"
    exit 1
fi

SYSTEM_PHP_BIN="$(command -v php)"
echo -e "${GREEN}[OK]${NC} System PHP CLI: ${BOLD}$(php_full_version "$SYSTEM_PHP_BIN")${NC} (${SYSTEM_PHP_BIN})"

if [ -z "$COMPOSER_BIN" ]; then
    echo -e "${YELLOW}[WARN] Composer not found. Installing Composer globally...${NC}"
    EXPECTED_SIG="$(php -r "copy('https://composer.github.io/installer.sig', 'php://stdout');" 2>/dev/null | tr -d '[:space:]' || true)"
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    ACTUAL_SIG="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

    if [ -n "$EXPECTED_SIG" ] && [ "$EXPECTED_SIG" != "$ACTUAL_SIG" ]; then
        rm -f composer-setup.php
        echo -e "${RED}[ERROR] Composer installer signature mismatch, refusing to install.${NC}"
        exit 1
    fi

    $SUDO php composer-setup.php --install-dir=/usr/local/bin --filename=composer
    rm -f composer-setup.php
    COMPOSER_BIN="$(command -v composer || true)"

    if [ -z "$COMPOSER_BIN" ]; then
        echo -e "${RED}[ERROR] Composer could not be installed.${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}[OK]${NC} Composer: ${BOLD}${COMPOSER_BIN}${NC}"

# ------------------------------------------------------------------------------
# STEP 2: Environment & PHP Runtime Selection
# ------------------------------------------------------------------------------
step_header "Step 2/6 - Environment"

echo -e "Select how you want to run and host your local development project:"
echo -e "  1) ${BOLD}XAMPP Stack${NC}      -> XAMPP MySQL (and Apache if its PHP is new enough)"
echo -e "  2) ${BOLD}Native CLI${NC}       -> System PHP, native database engines, 'php artisan serve'"
read -r -p "Choose environment [1 or 2] [default: 2]: " ENV_CHOICE
ENV_CHOICE=${ENV_CHOICE:-2}

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
step_header "Step 3/6 - Project and DB"

while :; do
    read -r -p "Enter your Project / Webapp Name (e.g., test-app): " RAW_PROJECT_NAME
    PROJECT_FOLDER=$(printf '%s' "$RAW_PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
    if [ -z "$PROJECT_FOLDER" ]; then
        echo -e "${RED}Project name must contain at least one letter or number.${NC}"
        continue
    fi
    break
done

DEFAULT_DB_NAME=$(printf '%s' "$PROJECT_FOLDER" | tr '-' '_')

if [ -d "${CURRENT_DIR}/${PROJECT_FOLDER}" ]; then
    echo -e "${RED}[ERROR] Folder '${CURRENT_DIR}/${PROJECT_FOLDER}' already exists!${NC}"
    exit 1
fi

echo -e "\nDatabase engines supported by Laravel on this machine:"
printf '  %-3s%-18s%-26s%s\n' "#" "ENGINE" "PHP DRIVER" "SERVER / NOTES"
printf '  %-3s%-18s%-26s%s\n' "1" "MySQL / MariaDB" "pdo_mysql: $(db_driver_label pdo_mysql)" "$(mysql_server_label)"
printf '  %-3s%-18s%-26s%s\n' "2" "PostgreSQL" "pdo_pgsql: $(db_driver_label pdo_pgsql)" "$(pgsql_server_label)"
printf '  %-3s%-18s%-26s%s\n' "3" "SQLite" "pdo_sqlite: $(db_driver_label pdo_sqlite)" "file based, no server needed"
printf '  %-3s%-18s%-26s%s\n' "4" "SQL Server" "pdo_sqlsrv: $(db_driver_label pdo_sqlsrv)" "external server on port 1433"

while :; do
    read -r -p "Choose database engine [1-4] [default: 1]: " DB_CHOICE
    DB_CHOICE=${DB_CHOICE:-1}
    case "$DB_CHOICE" in
        1|2|3|4) break ;;
        *) echo -e "${RED}Please choose 1, 2, 3 or 4.${NC}" ;;
    esac
done

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

    echo -e "\nSelect MySQL Engine:"
    echo -e "  1) ${BOLD}Native MySQL/MariaDB${NC} -> Uses the system MySQL/MariaDB service"
    echo -e "  2) ${BOLD}XAMPP's MySQL Engine${NC} -> Uses /opt/lampp MySQL"
    read -r -p "Choose MySQL engine [1 or 2] [default: ${DEFAULT_MYSQL_ENGINE}]: " MYSQL_ENGINE_CHOICE
    MYSQL_ENGINE_CHOICE=${MYSQL_ENGINE_CHOICE:-$DEFAULT_MYSQL_ENGINE}

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

    read -r -p "Enter MySQL Database Name [default: ${DEFAULT_DB_NAME}]: " DB_NAME
    DB_NAME=${DB_NAME:-$DEFAULT_DB_NAME}

    read -r -p "Enter MySQL Host [default: 127.0.0.1]: " DB_HOST
    DB_HOST=${DB_HOST:-127.0.0.1}

    read -r -p "Enter MySQL Port [default: 3306]: " DB_PORT
    DB_PORT=${DB_PORT:-3306}

    read -r -p "Enter MySQL Username [default: root]: " DB_USER
    DB_USER=${DB_USER:-root}

    while :; do
        read -r -s -p "Enter MySQL Password (leave blank for empty/XAMPP default): " DB_PASS
        echo ""
        case "$DB_PASS" in
            *"'"*|*\\*)
                echo -e "${RED}A password containing a single quote or backslash is not supported here.${NC}"
                ;;
            *) break ;;
        esac
    done
elif [ "$DB_CONN" = "pgsql" ]; then
    read -r -p "Enter PostgreSQL Database Name [default: ${DEFAULT_DB_NAME}]: " DB_NAME
    DB_NAME=${DB_NAME:-$DEFAULT_DB_NAME}

    read -r -p "Enter PostgreSQL Host [default: 127.0.0.1]: " DB_HOST
    DB_HOST=${DB_HOST:-127.0.0.1}

    read -r -p "Enter PostgreSQL Port [default: 5432]: " DB_PORT
    DB_PORT=${DB_PORT:-5432}

    read -r -p "Enter PostgreSQL Username [default: ${DEFAULT_DB_NAME}]: " DB_USER
    DB_USER=${DB_USER:-$DEFAULT_DB_NAME}

    while :; do
        read -r -s -p "Enter PostgreSQL Password (required for TCP logins): " DB_PASS
        echo ""
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
    read -r -p "Enter SQL Server Database Name [default: ${DEFAULT_DB_NAME}]: " DB_NAME
    DB_NAME=${DB_NAME:-$DEFAULT_DB_NAME}

    read -r -p "Enter SQL Server Host [default: 127.0.0.1]: " DB_HOST
    DB_HOST=${DB_HOST:-127.0.0.1}

    read -r -p "Enter SQL Server Port [default: 1433]: " DB_PORT
    DB_PORT=${DB_PORT:-1433}

    read -r -p "Enter SQL Server Username [default: sa]: " DB_USER
    DB_USER=${DB_USER:-sa}

    while :; do
        read -r -s -p "Enter SQL Server Password: " DB_PASS
        echo ""
        if [ -z "$DB_PASS" ]; then
            echo -e "${RED}SQL Server needs a password for this login.${NC}"
            continue
        fi
        break
    done
fi

# Summary Display
echo -e "\n${YELLOW}${BOLD}==============================================================${NC}"
echo -e "${YELLOW}${BOLD}                     CONFIGURATION SUMMARY                    ${NC}"
echo -e "${YELLOW}${BOLD}==============================================================${NC}"
echo -e " Project Name   : ${RAW_PROJECT_NAME}"
echo -e " Folder Path    : ${CURRENT_DIR}/${PROJECT_FOLDER}"
echo -e " Architecture   : ${BOLD}${ENV_MODE^^}${NC}"
echo -e " PHP Runtime    : ${PHP_BIN} (PHP ${TARGET_PHP})"
echo -e " Laravel Pkg    : ${LARAVEL_PKG}"
echo -e " DB Connection  : ${DB_CONN}"
if [ "$DB_CONN" = "mysql" ]; then
    echo -e " MySQL Engine   : $( [ "$MYSQL_ENGINE" = "xampp_mysql" ] && echo "XAMPP MySQL (/opt/lampp)" || echo "Native MySQL/MariaDB" )"
    echo -e " DB Host:Port   : ${DB_HOST}:${DB_PORT}"
    echo -e " DB Name        : ${DB_NAME}"
    echo -e " DB User        : ${DB_USER}"
elif [ "$DB_CONN" = "pgsql" ]; then
    echo -e " DB Host:Port   : ${DB_HOST}:${DB_PORT}"
    echo -e " DB Name        : ${DB_NAME}"
    echo -e " DB User        : ${DB_USER}"
elif [ "$DB_CONN" = "sqlsrv" ]; then
    echo -e " DB Host:Port   : ${DB_HOST}:${DB_PORT}"
    echo -e " DB Name        : ${DB_NAME}"
    echo -e " DB User        : ${DB_USER}"
else
    echo -e " DB File        : ${CURRENT_DIR}/${PROJECT_FOLDER}/database/database.sqlite"
fi
echo -e "${YELLOW}${BOLD}==============================================================${NC}\n"

read -r -p "Proceed with project generation? (y/n) [y]: " CONFIRM
CONFIRM=${CONFIRM:-y}
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "${RED}Aborted by user.${NC}"
    exit 0
fi

# ------------------------------------------------------------------------------
# STEP 4: Install, Provision & Verify the Database
# ------------------------------------------------------------------------------
step_header "Step 4/6 - Database Setup"

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
        if apt-cache show msodbcsql18 >/dev/null 2>&1; then
            echo -e "  ${YELLOW}[INFO]${NC} Installing Microsoft ODBC Driver 18..."
            ( $SUDO ACCEPT_EULA=Y apt-get install -y msodbcsql18 unixodbc-dev >/dev/null 2>&1 ) || true
        elif apt-cache show msodbcsql17 >/dev/null 2>&1; then
            echo -e "  ${YELLOW}[INFO]${NC} Installing Microsoft ODBC Driver 17..."
            ( $SUDO ACCEPT_EULA=Y apt-get install -y msodbcsql17 unixodbc-dev >/dev/null 2>&1 ) || true
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
        apt_update_once
        $SUDO apt-get install -y "php${PHP_MINOR}-dev" >/dev/null 2>&1 || \
            $SUDO apt-get install -y php-dev >/dev/null 2>&1 || true
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
                echo -e "${YELLOW}[WARN] Native MySQL/MariaDB not found. Installing default-mysql-server...${NC}"
                apt_update_once
                $SUDO apt-get install -y default-mysql-server || true
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
            echo -e "${YELLOW}[WARN] PostgreSQL not found. Installing postgresql...${NC}"
            apt_update_once
            $SUDO apt-get install -y postgresql postgresql-contrib || true
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
        read -r -p "Continue anyway? (y/n) [n]: " KEEP_GOING
        KEEP_GOING=${KEEP_GOING:-n}
        [[ "$KEEP_GOING" =~ ^[Yy]$ ]] || exit 1
    fi
fi

# ------------------------------------------------------------------------------
# STEP 5: Generate Laravel Project
# ------------------------------------------------------------------------------
step_header "Step 5/6 - Project Generation"

echo -e "${YELLOW}[INFO] Installing Laravel ${LARAVEL_VERSION} with ${PHP_BIN}...${NC}"
run_composer create-project "$LARAVEL_PKG" "$PROJECT_FOLDER" --no-scripts --no-interaction --prefer-dist

cd "${CURRENT_DIR}/${PROJECT_FOLDER}"

# Register discovered packages (create-project ran with --no-scripts)
run_composer dump-autoload --no-interaction >/dev/null

# ------------------------------------------------------------------------------
# STEP 6: Configure .env, Permissions, & Migrations
# ------------------------------------------------------------------------------
step_header "Step 6/6 - Env and Migrate"

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

"$PHP_BIN" artisan key:generate --ansi

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

"$PHP_BIN" artisan migrate --force

if [ -f "package.json" ] && command -v npm &>/dev/null; then
    echo -e "${YELLOW}[INFO] Installing npm packages and building assets...${NC}"
    npm install
    npm run build
fi

# ------------------------------------------------------------------------------
# Success Banner
# ------------------------------------------------------------------------------
echo ""
banner "READY TO GO"
echo -e "${GREEN}${BOLD}Your Laravel ${LARAVEL_VERSION} application is ready!${NC}"
echo -e " Project Location : ${YELLOW}${CURRENT_DIR}/${PROJECT_FOLDER}${NC}"
echo -e " PHP Runtime      : ${PHP_BIN} (PHP ${TARGET_PHP})"
echo -e " Database         : ${BOLD}${DB_CONN}${NC}"

if [ "$DB_CONN" = "mysql" ]; then
    echo -e " Database Engine  : $( [ "$MYSQL_ENGINE" = "xampp_mysql" ] && echo "XAMPP MySQL (/opt/lampp/lampp startmysql)" || echo "Native MySQL/MariaDB ($SUDO systemctl start mysql)" )"
elif [ "$DB_CONN" = "pgsql" ]; then
    echo -e " Database Engine  : PostgreSQL ($SUDO systemctl start postgresql)"
elif [ "$DB_CONN" = "sqlsrv" ]; then
    echo -e " Database Engine  : SQL Server at ${DB_HOST}:${DB_PORT}"
else
    echo -e " Database Engine  : SQLite (${SQLITE_PATH})"
fi

if [ "$SERVE_MODE" = "apache" ]; then
    echo -e " Browser URL      : ${CYAN}${APP_URL_VAL}${NC}"
    echo -e " phpMyAdmin       : ${CYAN}http://localhost/phpmyadmin${NC}"
else
    echo -e " Development Run  : ${CYAN}cd ${PROJECT_FOLDER} && ${PHP_BIN} artisan serve${NC}"
    echo -e " Browser URL      : ${CYAN}http://127.0.0.1:8000${NC}"
fi
echo -e "${GREEN}${BOLD}==============================================================${NC}"

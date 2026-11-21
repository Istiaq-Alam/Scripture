# MySQL & MariaDB CLI Cheatsheet (`sudo mysql -u root`)

> **Quick Note:** Every SQL statement inside the MySQL prompt must end with a semicolon (`;`), while built-in client shortcuts (`\c`, `\G`, `EXIT`) do not require one.

---

## 1. CLI Client & Session Commands
Built-in commands for navigating and controlling the terminal prompt itself:

```sql
STATUS;                         -- Show server version, uptime, current DB, and user
SELECT VERSION();               -- Check exact MySQL/MariaDB version
SELECT USER();                  -- Check which user you are logged in as
\c                              -- Cancel/clear the current unfinished query line
\G                              -- Display query output vertically (great for wide tables)
SOURCE /path/to/file.sql;       -- Import and execute an external .sql file
SYSTEM clear;                   -- Run a Linux bash command (like clear) inside MySQL
HELP;                           -- Show built-in CLI help
EXIT;                           -- Exit the MySQL prompt (or use QUIT; / Ctrl+D)
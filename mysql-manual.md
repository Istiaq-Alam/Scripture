MySQL & MariaDB CLI Cheatsheet (`sudo mysql -u root`)

> **Quick Note:** Every SQL statement inside the MySQL prompt must end with a semicolon (`;`), while built-in client shortcuts (`\c`, `\G`, `EXIT`) do not require one.

### 1. CLI Client & Session Commands

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
```

### 2. Database Management

```sql
SHOW DATABASES;                                 -- List all databases on the server
CREATE DATABASE db_name;                        -- Create a new database
CREATE DATABASE IF NOT EXISTS db_name;          -- Create only if it doesn't already exist
USE db_name;                                    -- Switch into a database to work on its tables
SELECT DATABASE();                              -- Show which database is currently selected
DROP DATABASE db_name;                          -- Permanently delete a database and all its tables
DROP DATABASE IF EXISTS db_name;                -- Delete safely without error if missing
```

### 3. User & Permission Management

```sql
SELECT User, Host FROM mysql.user;                                      -- List all database users
CREATE USER 'username'@'localhost' IDENTIFIED BY 'password';            -- Create a new local user
ALTER USER 'username'@'localhost' IDENTIFIED BY 'new_password';         -- Change a user's password
GRANT ALL PRIVILEGES ON *.* TO 'username'@'localhost' WITH GRANT OPTION;-- Give full admin rights
GRANT ALL PRIVILEGES ON db_name.* TO 'username'@'localhost';            -- Give rights to one DB only
SHOW GRANTS FOR 'username'@'localhost';                                 -- View a user's permissions
REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'username'@'localhost';        -- Remove all permissions
DROP USER 'username'@'localhost';                                       -- Delete a user
FLUSH PRIVILEGES;                                                       -- Reload permission tables
```

### 4. Table Structure (DDL — Data Definition Language)

```sql
SHOW TABLES;                                    -- List all tables in the current database
DESCRIBE table_name;                            -- Show columns, data types, keys (or DESC table_name;)
SHOW CREATE TABLE table_name;                   -- Show the exact SQL used to build the table

-- Create a new table
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(150) UNIQUE NOT NULL,
    role ENUM('admin', 'user') DEFAULT 'user',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Modify an existing table
ALTER TABLE users ADD COLUMN phone VARCHAR(20);             -- Add a new column
ALTER TABLE users MODIFY COLUMN name VARCHAR(150);          -- Change column type/size
ALTER TABLE users RENAME COLUMN phone TO mobile;            -- Rename a column
ALTER TABLE users DROP COLUMN mobile;                       -- Delete a column
RENAME TABLE old_name TO new_name;                          -- Rename a table

-- Remove data or table
TRUNCATE TABLE table_name;                      -- Delete all rows & reset AUTO_INCREMENT IDs
DROP TABLE table_name;                          -- Permanently delete the entire table
```

### 5. Reading & Filtering Data (DQL — Data Query Language)

```sql
SELECT * FROM users;                                        -- Fetch all columns and rows
SELECT id, name, email FROM users;                          -- Fetch specific columns only
SELECT DISTINCT role FROM users;                            -- Fetch unique values without duplicates

-- Filtering (WHERE)
SELECT * FROM users WHERE id = 1;
SELECT * FROM users WHERE role = 'admin' AND id > 5;
SELECT * FROM users WHERE name LIKE '%alam%';               -- Search partial text (% = wildcard)
SELECT * FROM users WHERE id IN (1, 3, 5);                  -- Match any value in a list
SELECT * FROM users WHERE created_at BETWEEN '2026-01-01' AND '2026-12-31';
SELECT * FROM users WHERE phone IS NULL;                    -- Find empty/NULL fields

-- Sorting & Limiting
SELECT * FROM users ORDER BY created_at DESC;               -- Sort newest first (ASC = oldest first)
SELECT * FROM users LIMIT 10;                               -- Return only the first 10 rows
SELECT * FROM users LIMIT 10 OFFSET 20;                     -- Skip 20 rows, return next 10

-- Counting & Grouping
SELECT COUNT(*) FROM users;                                 -- Count total rows
SELECT role, COUNT(*) FROM users GROUP BY role;             -- Count rows per category
```

### 6. Inserting, Updating & Deleting Data (DML — Data Manipulation Language)

```sql
-- Insert single or multiple rows
INSERT INTO users (name, email, role) VALUES ('Istiaq', 'istiaq@example.com', 'admin');

INSERT INTO users (name, email) VALUES 
    ('Alice', 'alice@example.com'),
    ('Bob', 'bob@example.com');

-- Update existing rows (ALWAYS include a WHERE clause!)
UPDATE users SET role = 'admin', name = 'Istiaq Alam' WHERE id = 1;

-- Delete specific rows (ALWAYS include a WHERE clause!)
DELETE FROM users WHERE id = 5;
```

### 7. Joins & Foreign Keys

```sql
-- Add a foreign key relationship
ALTER TABLE posts 
ADD CONSTRAINT fk_user 
FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

-- INNER JOIN (only rows with matches in both tables)
SELECT users.name, posts.title 
FROM users 
INNER JOIN posts ON users.id = posts.user_id;

-- LEFT JOIN (all users, even if they have 0 posts)
SELECT users.name, posts.title 
FROM users 
LEFT JOIN posts ON users.id = posts.user_id;
```

### 8. Import & Export via Linux Terminal (Outside MySQL Prompt)
Run these directly in your normal **Kali Bash/Zsh terminal** (not inside `mysql>`):

```bash
# Export (backup) a database to a .sql file
sudo mysqldump -u root db_name > backup.sql

# Import a .sql file from your GitHub folder into an existing database
sudo mysql -u root db_name < /path/to/github-folder/database.sql
```

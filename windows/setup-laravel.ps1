#requires -version 5.1
<#
  Laravel setup - Windows

  - Picks a PHP runtime that can run the current Laravel
  - Installs MySQL, PostgreSQL or SQLite (winget where possible)
  - Creates the database and verifies the login
  - Writes .env, runs the first migrations and builds the front-end assets

  Run from the folder where the project should be created:
    powershell -ExecutionPolicy Bypass -File .\setup-laravel.ps1
#>

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$E = [char]27
$C = @{
  green = "$E[38;5;114m"; yellow = "$E[38;5;179m"; red = "$E[38;5;203m"
  cyan = "$E[38;5;111m"; accent = "$E[38;5;111m"
  muted = "$E[38;5;244m"; bold = "$E[1m"; dim = "$E[2m"; nc = "$E[0m"
}
if ($env:NO_COLOR) { $colorKeys = @($C.Keys); foreach ($k in $colorKeys) { $C[$k] = '' } }

$StartDir = (Get-Location).Path
$TempDir = Join-Path $env:TEMP ("scripture-laravel-" + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

# --- UI ---------------------------------------------------------------------
function Get-UiWidth {
  try { $w = $Host.UI.RawUI.WindowSize.Width } catch { $w = 80 }
  if (-not $w) { $w = 80 }
  if ($w -lt 60) { $w = 60 }; if ($w -gt 96) { $w = 96 }
  return $w
}
function Clear-Ui { if (-not [Console]::IsOutputRedirected) { [Console]::Clear() } }
function Write-Rule { Write-Host ($C.muted + ('─' * (Get-UiWidth)) + $C.nc) }
function Write-Panel {
  param([string]$Color, [string]$Title, [string[]]$Lines)
  $w = Get-UiWidth; $inner = $w - 4; $head = " $Title "
  $fill = $w - 3 - $head.Length; if ($fill -lt 0) { $fill = 0 }
  Write-Host ""
  Write-Host ($Color + "╭─" + $head + ("─" * $fill) + "╮" + $C.nc)
  foreach ($line in $Lines) {
    if ($null -eq $line) { $line = "" }
    if ($line.Length -gt $inner) { $line = $line.Substring(0, $inner) }
    Write-Host ($Color + "│" + $C.nc + " " + $line.PadRight($inner - 2) + " " + $Color + "│" + $C.nc)
  }
  Write-Host ($Color + "╰" + ("─" * ($w - 2)) + "╯" + $C.nc)
}
function Write-Step {
  param([int]$Number, [int]$Total, [string]$Title)
  Clear-Ui; Write-Host ""
  Write-Host ("$($C.accent)❯$($C.nc) $($C.muted)step $Number of $Total$($C.nc) · $($C.bold)$Title$($C.nc)")
  Write-Rule; Write-Host ""
}
function Write-Ok   { param([string]$m) Write-Host ("  $($C.green)[OK]$($C.nc)   $m") }
function Write-Warn { param([string]$m) Write-Host ("  $($C.yellow)[WARN]$($C.nc) $m") }
function Write-Err  { param([string]$m) Write-Host ("  $($C.red)[FAIL]$($C.nc) $m") }
function Write-Info { param([string]$m) Write-Host ("  $($C.muted)$m$($C.nc)") }
function Write-Kv   { param([string]$K, [string]$V) Write-Host ("  $($C.muted)$($K.PadRight(16))$($C.nc) $V") }

function Read-Ask {
  param([string]$Prompt, [string]$Default = "")
  $answer = Read-Host "  $Prompt"
  if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
  return $answer.Trim()
}
function Read-Secret {
  param([string]$Prompt)
  $secure = Read-Host "  $Prompt" -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}
function Read-Confirm {
  param([string]$Question, [string]$Default = "n")
  $hint = if ($Default -eq "y") { "[Y/n]" } else { "[y/N]" }
  $answer = Read-Host "  $Question $hint"
  if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $Default }
  return ($answer -match '^(y|yes)$')
}
function Show-Menu {
  param([string]$Title, [string[]]$Items, [int]$Default = 0)
  if ([Console]::IsInputRedirected) {
    Write-Host $Title
    for ($i = 0; $i -lt $Items.Count; $i++) { Write-Host ("  {0}) {1}" -f ($i + 1), $Items[$i]) }
    $pick = Read-Host ("Choose [1-{0}] (default {1})" -f $Items.Count, ($Default + 1))
    if ($pick -match '^\d+$' -and [int]$pick -ge 1 -and [int]$pick -le $Items.Count) { return ([int]$pick - 1) }
    return $Default
  }
  $sel = $Default
  while ($true) {
    Clear-Ui; Write-Host ""
    Write-Host ("  " + $C.bold + $Title + $C.nc); Write-Host ""
    for ($i = 0; $i -lt $Items.Count; $i++) {
      if ($i -eq $sel) { Write-Host ("  " + $C.accent + "❯ " + $Items[$i] + $C.nc) }
      else { Write-Host ("    " + $Items[$i]) }
    }
    Write-Host ""; Write-Host ("  " + $C.muted + "↑ ↓ move   Enter select" + $C.nc)
    $key = [Console]::ReadKey($true)
    switch ($key.Key) {
      'UpArrow'   { if ($sel -gt 0) { $sel-- } }
      'DownArrow' { if ($sel -lt $Items.Count - 1) { $sel++ } }
      { $_ -in 'Enter', 'Escape' } { return $sel }
      default {
        if ($key.KeyChar -eq 'k' -and $sel -gt 0) { $sel-- }
        if ($key.KeyChar -eq 'j' -and $sel -lt $Items.Count - 1) { $sel++ }
      }
    }
  }
}
function Resolve-Exe {
  param([string]$Name)
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $Name
}
function Update-SessionPath {
  $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $user = [Environment]::GetEnvironmentVariable('Path', 'User')
  $env:Path = "$machine;$user"
}
function Invoke-Exe {
  param([string]$Label, [string]$Exe, [string[]]$Arguments = @(), [int]$TimeoutSec = 2400)
  $out = Join-Path $TempDir ([guid]::NewGuid().ToString('n') + ".out")
  $err = Join-Path $TempDir ([guid]::NewGuid().ToString('n') + ".err")
  $proc = Start-Process -FilePath (Resolve-Exe $Exe) -ArgumentList $Arguments -NoNewWindow -PassThru `
    -RedirectStandardOutput $out -RedirectStandardError $err
  $frames = '|', '/', '-', '\'; $i = 0; $start = Get-Date
  while (-not $proc.HasExited) {
    if (-not [Console]::IsOutputRedirected) { [Console]::Write("`r  $($C.accent)$($frames[$i % 4])$($C.nc) $Label") }
    $i++; Start-Sleep -Milliseconds 140
    if (((Get-Date) - $start).TotalSeconds -gt $TimeoutSec) {
      try { $proc.Kill() } catch { }
      Write-Host "`r$(' ' * ($Label.Length + 6))`r"
      Write-Err "$Label timed out"; return $false
    }
  }
  try { $proc.WaitForExit() } catch { }
  if (-not [Console]::IsOutputRedirected) { Write-Host ("`r" + (' ' * ($Label.Length + 6)) + "`r") -NoNewline }
  if ($proc.ExitCode -eq 0) { Write-Ok $Label; return $true }
  Write-Err "$Label (exit $($proc.ExitCode))"
  if (Test-Path $out) { Get-Content $out -Tail 15 | Where-Object { $_ } | ForEach-Object { Write-Host "      $_" } }
  if (Test-Path $err) { Get-Content $err -Tail 15 | Where-Object { $_ } | ForEach-Object { Write-Host "      $_" } }
  return $false
}

function Get-PhpVersion {
  param([string]$Php)
  try { return (& $Php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>$null).Trim() } catch { return "" }
}
function Find-Php {
  $candidates = New-Object System.Collections.Generic.List[string]
  $cmd = Get-Command php -ErrorAction SilentlyContinue
  if ($cmd) { $candidates.Add($cmd.Source) }
  foreach ($pattern in @("C:\php\php.exe", "C:\xampp\php\php.exe", "C:\laragon\bin\php\*\php.exe", "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\PHP.PHP*\php.exe", "C:\tools\php*\php.exe")) {
    Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | ForEach-Object {
      $candidates.Add($_.FullName)
    }
  }
  $found = New-Object System.Collections.Generic.List[string]
  foreach ($candidate in $candidates) {
    if (-not (Test-Path $candidate)) { continue }
    $version = Get-PhpVersion $candidate
    if (-not $version) { continue }
    if ([version]$version -ge [version]"8.2" -and -not $found.Contains($candidate)) { $found.Add($candidate) }
  }
  return $found
}
function Find-Mysql {
  $cmd = Get-Command mysql -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $hit = Get-ChildItem -Path "C:\Program Files\MySQL\MySQL Server*\bin\mysql.exe" -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1
  if ($hit) { return $hit.FullName }
  return ""
}
function Find-Psql {
  $cmd = Get-Command psql -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $hit = Get-ChildItem -Path "C:\Program Files\PostgreSQL\*\bin\psql.exe" -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1
  if ($hit) { return $hit.FullName }
  return ""
}
function Wait-Port {
  param([string]$ComputerName, [int]$Port, [int]$Seconds = 30)
  for ($i = 0; $i -lt $Seconds; $i++) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
      $async = $client.BeginConnect($ComputerName, $Port, $null, $null)
      if ($async.AsyncWaitHandle.WaitOne(800) -and $client.Connected) { $client.Close(); return $true }
    } catch { }
    finally { $client.Close() }
    Start-Sleep -Seconds 1
  }
  return $false
}
function Set-EnvValue {
  param([string]$File, [string]$Key, [string]$Value)
  $lines = @(Get-Content $File -ErrorAction SilentlyContinue)
  $done = $false
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($line in $lines) {
    if ($line -match "^$([regex]::Escape($Key))=") { $out.Add("$Key=$Value"); $done = $true }
    else { $out.Add($line) }
  }
  if (-not $done) { $out.Add("$Key=$Value") }
  [IO.File]::WriteAllLines($File, $out, (New-Object System.Text.UTF8Encoding($false)))
}
function Quote-Env {
  param([string]$Value)
  if ($Value -match '[\s#"'']') { return "'" + ($Value -replace "'", "\'") + "'" }
  return $Value
}

# --- Start ------------------------------------------------------------------
Clear-Ui
Write-Panel $C.accent "LARAVEL SETUP · WINDOWS" @(
  "PHP, a database and a working app in one guided run.",
  "",
  "Folder: $StartDir",
  "Nothing is installed until you confirm the packages."
)
Write-Host ""

# --- 1. Tools ---------------------------------------------------------------
Write-Step 1 6 "Windows tools"
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  Write-Warn "winget is not available. Install packages manually when asked."
} else { Write-Ok "winget available" }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Write-Warn "git is not installed; Composer may need it for create-project."
} else { Write-Ok "git found" }

# --- 2. PHP -----------------------------------------------------------------
Write-Step 2 6 "PHP runtime"
$phpCandidates = Find-Php
if ($phpCandidates.Count -gt 0) {
  if ($phpCandidates.Count -eq 1) { $phpBin = $phpCandidates[0] }
  else {
    $labels = $phpCandidates | ForEach-Object { "$_  (PHP $(Get-PhpVersion $_))" }
    $pick = Show-Menu "Which PHP runtime should run Laravel?" $labels 0
    $phpBin = $phpCandidates[$pick]
  }
  $phpVersion = Get-PhpVersion $phpBin
  Write-Ok "Using $phpBin (PHP $phpVersion)"
} else {
  Write-Warn "No PHP 8.2+ runtime found."
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Err "Install PHP 8.2+ from https://windows.php.net/download and add it to PATH, then run again."
    exit 1
  }
  if (-not (Read-Confirm "Install PHP 8.3 with winget?" "y")) { Write-Err "PHP 8.2+ is required."; exit 1 }
  Invoke-Exe "Installing PHP 8.3" "winget" @("install", "--id", "PHP.PHP.8.3", "-e", "--source", "winget", "--accept-package-agreements", "--accept-source-agreements") | Out-Null
  Update-SessionPath
  $phpCandidates = Find-Php
  if ($phpCandidates.Count -eq 0) {
    Write-Err "PHP was installed but php.exe was not found. Open a new terminal and run this script again."
    exit 1
  }
  $phpBin = $phpCandidates[0]
  $phpVersion = Get-PhpVersion $phpBin
  Write-Ok "Using $phpBin (PHP $phpVersion)"
}

# --- Composer ---------------------------------------------------------------
$composerCmd = Get-Command composer -ErrorAction SilentlyContinue
$composerPhar = Join-Path $env:LOCALAPPDATA "Composer\composer.phar"
if ($composerCmd) {
  Write-Ok "Composer found"
} elseif (Test-Path $composerPhar) {
  Write-Ok "Composer found at $composerPhar"
} else {
  Write-Warn "Composer is not installed."
  if (-not (Read-Confirm "Download and verify Composer now?" "y")) { Write-Err "Composer is required."; exit 1 }
  $installer = Join-Path $TempDir "composer-setup.php"
  $sigFile = Join-Path $TempDir "composer-setup.sig"
  Invoke-WebRequest -UseBasicParsing -Uri "https://getcomposer.org/installer" -OutFile $installer
  Invoke-WebRequest -UseBasicParsing -Uri "https://composer.github.io/installer.sig" -OutFile $sigFile
  $expected = (Get-Content $sigFile -Raw).Trim()
  $actual = (& $phpBin -r "echo hash_file('sha384', '$(($installer -replace '\\','/'))');").Trim()
  if ($expected -ne $actual) {
    Write-Err "Composer installer signature mismatch. Aborting."
    exit 1
  }
  Write-Ok "Composer installer signature verified"
  New-Item -ItemType Directory -Path (Split-Path -Parent $composerPhar) -Force | Out-Null
  if (-not (Invoke-Exe "Installing Composer" $phpBin @($installer, "--install-dir=" + (Split-Path -Parent $composerPhar), "--filename=composer.phar"))) {
    Write-Err "Composer install failed."
    exit 1
  }
  $shimDir = Split-Path -Parent $composerPhar
  $shim = Join-Path $shimDir "composer.cmd"
  Set-Content -Path $shim -Value "@echo off`r`n`"$phpBin`" `"$composerPhar`" %*" -Encoding ASCII
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  if ($userPath -notlike "*$shimDir*") {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$shimDir", 'User')
  }
  Update-SessionPath
  Write-Ok "Composer installed at $composerPhar (composer.cmd added to PATH)"
}

# --- 3. Database and project settings ---------------------------------------
Write-Step 3 6 "Database and project"
$dbLabels = @(
  "MySQL       winget install, port 3306",
  "PostgreSQL  winget install, port 5432",
  "SQLite      a file in the project, no server",
  "Existing    connect to MySQL or PostgreSQL already running"
)
$dbChoice = Show-Menu "Which database should Laravel use?" $dbLabels 0

$engine = ""; $conn = ""; $defaultPort = ""
switch ($dbChoice) {
  0 { $engine = "MySQL"; $conn = "mysql"; $defaultPort = "3306" }
  1 { $engine = "PostgreSQL"; $conn = "pgsql"; $defaultPort = "5432" }
  2 { $engine = "SQLite"; $conn = "sqlite" }
  3 {
    $driver = Show-Menu "Which driver does the existing server use?" @("MySQL / MariaDB", "PostgreSQL") 0
    if ($driver -eq 0) { $engine = "MySQL"; $conn = "mysql"; $defaultPort = "3306" }
    else { $engine = "PostgreSQL"; $conn = "pgsql"; $defaultPort = "5432" }
  }
}

$rawName = Read-Ask "Project / webapp name (e.g. test-app):" "laravel-app"
$projectFolder = ($rawName.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')
if ([string]::IsNullOrWhiteSpace($projectFolder)) { Write-Err "Project name must contain a letter or number."; exit 1 }
if (Test-Path (Join-Path $StartDir $projectFolder)) {
  Write-Err "Folder '$(Join-Path $StartDir $projectFolder)' already exists."
  exit 1
}
$defaultDbName = $projectFolder -replace '-', '_'

$dbName = ""; $dbHost = ""; $dbPort = ""; $dbUser = ""; $dbPass = ""
if ($conn -eq "sqlite") {
  Write-Info "SQLite needs no server or credentials."
  $dbName = $defaultDbName
} else {
  $dbName = Read-Ask "Database name:" $defaultDbName
  $dbHost = Read-Ask "Host:" "127.0.0.1"
  $dbPort = Read-Ask "Port:" $defaultPort
  if ($conn -eq "mysql") { $dbUser = Read-Ask "Username:" "root" }
  else { $dbUser = Read-Ask "Username:" "postgres" }
  $dbPass = Read-Secret "Password (blank if the server allows it):"
}

Clear-Ui
Write-Panel $C.cyan "CONFIGURATION" @(
  "Project      $rawName",
  "Folder       $(Join-Path $StartDir $projectFolder)",
  "PHP          $phpBin (PHP $phpVersion)",
  "Database     $engine",
  "Host:port    $(if ($conn -eq 'sqlite') { 'file' } else { "$dbHost`:$dbPort" })",
  "DB name      $dbName",
  "DB user      $(if ($dbUser) { $dbUser } else { '(none)' })"
)
Write-Host ""
if (-not (Read-Confirm "Generate the project with these settings?" "y")) { Write-Info "Aborted."; exit 0 }

# --- 4. Provision the database ---------------------------------------------
Write-Step 4 6 "Database setup"
$installedService = ""

if ($conn -eq "mysql" -and $dbChoice -eq 0) {
  $mysql = Find-Mysql
  if (-not $mysql) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
      if (Read-Confirm "Install MySQL with winget (large download)?" "y") {
        Invoke-Exe "Installing MySQL" "winget" @("install", "--id", "Oracle.MySQL", "-e", "--source", "winget", "--accept-package-agreements", "--accept-source-agreements") | Out-Null
        Update-SessionPath
        $mysql = Find-Mysql
      }
    }
  }
  if ($mysql) { Write-Ok "mysql client: $mysql" } else { Write-Warn "mysql.exe not found. Install MySQL, start it, then retry." }
  $names = @(Get-Service -Name "*mysql*" -ErrorAction SilentlyContinue)
  foreach ($svc in $names) {
    if ($svc.Status -ne "Running") {
      try { Start-Service $svc.Name; Write-Ok "Started service $($svc.Name)"; $installedService = $svc.Name } catch { Write-Warn "Could not start $($svc.Name) (needs an elevated shell)." }
    }
  }
  if (Wait-Port $dbHost ([int]$dbPort)) { Write-Ok "$engine accepts connections on $dbHost`:$dbPort" }
  else { Write-Warn "No answer on $dbHost`:$dbPort yet. Migrations will report the real error." }
}
elseif ($conn -eq "pgsql" -and $dbChoice -eq 1) {
  if (-not (Find-Psql)) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
      if (Read-Confirm "Install PostgreSQL 16 with winget (large download)?" "y") {
        Invoke-Exe "Installing PostgreSQL" "winget" @("install", "--id", "PostgreSQL.PostgreSQL.16", "-e", "--source", "winget", "--accept-package-agreements", "--accept-source-agreements") | Out-Null
        Update-SessionPath
      }
    }
  }
  foreach ($svc in @(Get-Service -Name "postgresql*" -ErrorAction SilentlyContinue)) {
    if ($svc.Status -ne "Running") {
      try { Start-Service $svc.Name; Write-Ok "Started service $($svc.Name)"; $installedService = $svc.Name } catch { Write-Warn "Could not start $($svc.Name)." }
    }
  }
  if (Wait-Port $dbHost ([int]$dbPort)) { Write-Ok "$engine accepts connections on $dbHost`:$dbPort" }
  else { Write-Warn "No answer on $dbHost`:$dbPort yet. Migrations will report the real error." }
}

if ($conn -eq "mysql") {
  $mysql = Find-Mysql
  if ($mysql) {
    if ($dbPass) { $env:MYSQL_PWD = $dbPass } else { Remove-Item Env:\MYSQL_PWD -ErrorAction SilentlyContinue }
    $login = & $mysql -h $dbHost -P $dbPort -u $dbUser -e "SELECT 1" 2>&1
    if ($LASTEXITCODE -eq 0) {
      Write-Ok "Login accepted as $dbUser"
      & $mysql -h $dbHost -P $dbPort -u $dbUser -e "CREATE DATABASE IF NOT EXISTS ``$dbName`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>&1 | Out-Null
      if ($LASTEXITCODE -eq 0) { Write-Ok "Database '$dbName' ready" } else { Write-Warn "Could not create '$dbName'." }
    } else {
      Write-Warn "Could not log in as $dbUser. Fix the credentials and edit .env later."
    }
    Remove-Item Env:\MYSQL_PWD -ErrorAction SilentlyContinue
  }
}
elseif ($conn -eq "pgsql") {
  $psql = Find-Psql
  if ($psql) {
    $env:PGPASSWORD = $dbPass
    & $psql -h $dbHost -p $dbPort -U $dbUser -d postgres -c "SELECT 1" *> $null
    if ($LASTEXITCODE -eq 0) {
      Write-Ok "Login accepted as $dbUser"
      $exists = & $psql -h $dbHost -p $dbPort -U $dbUser -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$dbName'"
      if ($exists -match "1") { Write-Ok "Database '$dbName' already exists" }
      elseif ((& $psql -h $dbHost -p $dbPort -U $dbUser -d postgres -c "CREATE DATABASE `"$dbName`"" 2>&1) -and $LASTEXITCODE -eq 0) {
        Write-Ok "Database '$dbName' created"
      } else { Write-Warn "Could not create '$dbName'." }
    } else { Write-Warn "Could not log in as $dbUser. Fix the credentials and edit .env later." }
    Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue
  } else {
    Write-Warn "psql.exe not found. Install PostgreSQL and retry, or create the database by hand."
  }
}

# --- 5. Create the project --------------------------------------------------
Write-Step 5 6 "Project generation"
$projectPath = Join-Path $StartDir $projectFolder
Write-Info "Creating Laravel in $projectPath ..."
if (-not (Invoke-Exe "composer create-project" "composer" @("create-project", "laravel/laravel", $projectFolder, "--no-scripts", "--no-interaction", "--prefer-dist"))) {
  Write-Err "composer create-project failed."
  exit 1
}
Set-Location $projectPath
Invoke-Exe "Optimising the autoloader" "composer" @("dump-autoload", "--no-interaction") | Out-Null

# --- 6. .env, migrations, assets -------------------------------------------
Write-Step 6 6 "Environment and migrations"
if (-not (Test-Path ".env.example")) { Write-Err ".env.example is missing from the new project."; exit 1 }
Copy-Item ".env.example" ".env" -Force

Set-EnvValue ".env" "APP_NAME" (Quote-Env $rawName)
Set-EnvValue ".env" "APP_URL" "http://127.0.0.1:8000"
Set-EnvValue ".env" "DB_CONNECTION" $conn

if ($conn -eq "sqlite") {
  $sqlitePath = Join-Path $projectPath "database\database.sqlite"
  New-Item -ItemType File -Path $sqlitePath -Force | Out-Null
  Set-EnvValue ".env" "DB_DATABASE" (Quote-Env ($sqlitePath -replace '\\', '/'))
  Write-Ok "SQLite file created at $sqlitePath"
} else {
  Set-EnvValue ".env" "DB_HOST" $dbHost
  Set-EnvValue ".env" "DB_PORT" $dbPort
  Set-EnvValue ".env" "DB_DATABASE" (Quote-Env $dbName)
  Set-EnvValue ".env" "DB_USERNAME" (Quote-Env $dbUser)
  Set-EnvValue ".env" "DB_PASSWORD" (Quote-Env $dbPass)
}

if (-not (Invoke-Exe "Generating the application key" $phpBin @("artisan", "key:generate", "--ansi"))) { exit 1 }
if (-not (Invoke-Exe "Running database migrations" $phpBin @("artisan", "migrate", "--force"))) {
  Write-Err "Migrations failed. Check the database credentials in .env."
  exit 1
}

if ((Test-Path "package.json") -and (Get-Command npm -ErrorAction SilentlyContinue)) {
  Invoke-Exe "Installing npm packages" "npm" @("install") | Out-Null
  Invoke-Exe "Building front-end assets" "npm" @("run", "build") | Out-Null
}

# --- Success ----------------------------------------------------------------
Clear-Ui
$dbLabel = $engine
if ($dbName) { $dbLabel = "$engine · $dbName" }
Write-Panel $C.green "READY" @(
  "Laravel 12/13 application created.",
  "",
  "Location   $projectPath",
  "PHP        $phpBin (PHP $phpVersion)",
  "Database   $dbLabel"
)
Write-Host ""
Write-Panel $C.cyan "START THE APP" @(
  "cd $projectPath",
  "$phpBin artisan serve",
  "Open http://127.0.0.1:8000",
  "",
  "Ctrl+C stops the server. Another port: php artisan serve --port=8080"
)
Write-Host ""
if ($conn -eq "mysql" -and (Find-Mysql)) {
  Write-Panel $C.cyan "DATABASE ACCESS" @(
    "mysql -h $dbHost -P $dbPort -u $dbUser -p $dbName",
    "",
    "SHOW TABLES;        list tables",
    "SELECT * FROM users LIMIT 10;",
    "",
    "Web admin: MySQL Workbench, TablePlus or DBeaver."
  )
} elseif ($conn -eq "pgsql" -and (Find-Psql)) {
  Write-Panel $C.cyan "DATABASE ACCESS" @(
    "psql -h $dbHost -p $dbPort -U $dbUser -d $dbName",
    "",
    "\dt                 list tables",
    "\d users            describe a table",
    "\q                  leave the client"
  )
} else {
  Write-Panel $C.cyan "DATABASE ACCESS" @(
    "sqlite3 $sqlitePath",
    "",
    ".tables             list tables",
    "SELECT * FROM users LIMIT 10;"
  )
}
Write-Host ""
Write-Kv "Service" $(if ($installedService) { $installedService } else { "not started by this script" })
Write-Kv "Undo" "Delete the project folder and drop the database '$dbName'."
Write-Host ""

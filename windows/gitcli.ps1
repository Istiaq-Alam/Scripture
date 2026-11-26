#requires -version 5.1
<#
  GitHub first-time setup helper for Windows.
  Run this from the root of the project you want to publish:

    powershell -ExecutionPolicy Bypass -File .\gitcli.ps1
#>

$ErrorActionPreference = 'Continue'
$E = [char]27
$C = @{
  green = "$E[38;5;114m"; yellow = "$E[38;5;179m"; red = "$E[38;5;203m"
  cyan = "$E[38;5;111m"; accent = "$E[38;5;111m"
  muted = "$E[38;5;244m"; bold = "$E[1m"; nc = "$E[0m"
}
if ($env:NO_COLOR) { $colorKeys = @($C.Keys); foreach ($k in $colorKeys) { $C[$k] = '' } }

function Get-UiWidth {
  try { $w = $Host.UI.RawUI.WindowSize.Width } catch { $w = 80 }
  if (-not $w) { $w = 80 }
  if ($w -lt 60) { $w = 60 }; if ($w -gt 96) { $w = 96 }
  return $w
}
function Clear-Ui { if (-not [Console]::IsOutputRedirected) { [Console]::Clear() } }
function Write-Rule {
  Write-Host ($C.muted + ('─' * (Get-UiWidth)) + $C.nc)
}
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
  param([string]$Title)
  Clear-Ui; Write-Host ""
  Write-Host ("$($C.accent)❯$($C.nc) $($C.bold)$Title$($C.nc)")
  Write-Rule; Write-Host ""
}
function Write-Ok   { param([string]$m) Write-Host ("  $($C.green)[OK]$($C.nc)   $m") }
function Write-Warn { param([string]$m) Write-Host ("  $($C.yellow)[WARN]$($C.nc) $m") }
function Write-Err  { param([string]$m) Write-Host ("  $($C.red)[FAIL]$($C.nc) $m") }
function Write-Info { param([string]$m) Write-Host ("  $($C.muted)$m$($C.nc)") }
function Write-Kv   { param([string]$K, [string]$V) Write-Host ("  $($C.muted)$($K.PadRight(14))$($C.nc) $V") }
function Die        { param([string]$m) Write-Err $m; exit 1 }
function Read-Ask {
  param([string]$Prompt, [string]$Default = "")
  $answer = Read-Host "  $Prompt"
  if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
  return $answer.Trim()
}
function Read-Confirm {
  param([string]$Question, [string]$Default = "n")
  $hint = if ($Default -eq "y") { "[Y/n]" } else { "[y/N]" }
  $answer = Read-Host "  $Question $hint"
  if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $Default }
  return ($answer -match '^(y|yes)$')
}

function Invoke-Git {
  param([string[]]$Arguments, [switch]$AllowFail)
  $output = & git @Arguments 2>&1
  $code = $LASTEXITCODE
  if ($code -ne 0 -and -not $AllowFail) {
    Die ("git {0} failed: {1}" -f ($Arguments -join ' '), ($output | Select-Object -Last 3 | Out-String).Trim())
  }
  return @{ Code = $code; Output = $output }
}

# --- Banner -----------------------------------------------------------------
function Show-Banner {
  Clear-Ui
  if (Get-Command figlet -ErrorAction SilentlyContinue) {
    $art = & figlet "GIT" 2>$null
    if ($art) { $art | ForEach-Object { Write-Host $_ } } else { Write-Host "$($C.bold)GIT$($C.nc)" }
  } else {
    Write-Host "$($C.bold)GIT$($C.nc)"
  }
  Write-Rule
}

# --- Dependencies -----------------------------------------------------------
Clear-Ui
Write-Step "Checking dependencies"
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Write-Warn "git is not installed."
  if ((Get-Command winget -ErrorAction SilentlyContinue) -and (Read-Confirm "Install Git with winget?" "y")) {
    & winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
  }
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Die "Git is required. Install it from https://git-scm.com/download/win" }
}
Write-Ok "git $((& git --version) -replace 'git version ','')"
Write-Info "figlet and lolcat are Linux extras; the Windows banner uses plain text."

$top = (& git rev-parse --show-toplevel 2>$null)
$projectRoot = if ($top) { $top.Trim() } else { (Get-Location).Path }
Set-Location $projectRoot

# --- Existing repository: push, pull, repair --------------------------------
$inside = $false
& git rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -eq 0) { $inside = $true }

if ($inside) {
  Show-Banner
  Write-Kv "Project" $projectRoot
  Write-Host ""
  Write-Host "  1) Push changes"
  Write-Host "  2) Pull latest changes"
  Write-Host "  3) Run initial setup / repair remote"
  Write-Host ""
  $action = Read-Ask "Choose an option [1-3]:" "3"
  switch ($action) {
    "1" {
      $message = Read-Ask "Commit message:"
      if ([string]::IsNullOrWhiteSpace($message)) { Die "Commit message cannot be empty." }
      Invoke-Git @("add", "-A") | Out-Null
      & git diff --cached --quiet
      if ($LASTEXITCODE -ne 0) { Invoke-Git @("commit", "-m", $message) | Out-Null }
      else { Write-Info "No new changes to commit. Pushing the current branch." }
      $branch = (& git branch --show-current).Trim()
      if (-not $branch) { Die "Could not determine the current branch." }
      Invoke-Git @("push", "-u", "origin", $branch) | Out-Null
      Write-Ok "Push completed"; exit 0
    }
    "2" {
      $branch = (& git branch --show-current).Trim()
      if (-not $branch) { Die "Could not determine the current branch." }
      & git remote get-url origin *> $null
      if ($LASTEXITCODE -ne 0) { Die "No 'origin' remote is configured." }
      Write-Info "Pulling origin/$branch"
      Invoke-Git @("pull", "--ff-only", "origin", $branch) | Out-Null
      Write-Ok "Pull completed"; exit 0
    }
    "3" { Write-Info "Continuing with setup / repair." }
    default { Die "Invalid choice. Run the script again and choose 1, 2 or 3." }
  }
}

# --- First-time setup -------------------------------------------------------
Show-Banner
Write-Kv "Project" $projectRoot
Write-Host ""

if ((Test-Path ".git") -and -not $inside) {
  Die "A .git path exists but Git cannot use it. Check it before continuing."
}

Invoke-Git @("init") -AllowFail | Out-Null
Invoke-Git @("branch", "-M", "main") -AllowFail | Out-Null
Write-Ok "Initialised the repository on branch main"

$repoUrl = Read-Ask "GitHub repository URL (HTTPS or SSH):"
if ([string]::IsNullOrWhiteSpace($repoUrl)) { Die "Repository URL cannot be empty." }
if ($repoUrl -match 'YOUR_USERNAME|YOUR_REPOSITORY') { Die "Replace the example username/repository with your real URL." }

& git remote get-url origin *> $null
if ($LASTEXITCODE -eq 0) {
  $current = (& git remote get-url origin).Trim()
  Write-Warn "Remote origin already exists: $current"
  if (Read-Confirm "Replace origin with the URL you entered?" "n") {
    Invoke-Git @("remote", "set-url", "origin", $repoUrl) | Out-Null
    Write-Ok "origin replaced"
  } else { Write-Info "Keeping the existing origin." }
} else {
  Invoke-Git @("remote", "add", "origin", $repoUrl) | Out-Null
  Write-Ok "origin added"
}

$userName = (& git config user.name 2>$null)
if (-not $userName) {
  $name = Read-Ask "Git author name:"
  if ([string]::IsNullOrWhiteSpace($name)) { Die "Git author name cannot be empty." }
  & git config --global user.name $name
}
$userEmail = (& git config user.email 2>$null)
if (-not $userEmail) {
  $email = Read-Ask "Git author email:"
  if ([string]::IsNullOrWhiteSpace($email)) { Die "Git author email cannot be empty." }
  & git config --global user.email $email
}

if (-not (Test-Path ".gitignore")) {
  @'
# Secrets and environment files
.env
.env.*
!.env.example
!.env.*.example

# Dependencies
node_modules/
vendor/

# Build output and caches
dist/
build/
.next/
.nuxt/
.cache/
coverage/

# Logs and temporary files
*.log
npm-debug.log*
yarn-debug.log*
pnpm-debug.log*
tmp/
temp/

# Operating system and editor files
.DS_Store
Thumbs.db
.idea/
.vscode/

# Python
__pycache__/
*.py[cod]
.venv/
venv/

# Private keys and certificates
*.pem
*.key

# Local database files (remove these rules if you intentionally version them)
*.sqlite
*.sqlite3
'@ | Set-Content -Path ".gitignore" -Encoding UTF8
  Write-Ok "Created .gitignore"
} else { Write-Info "Keeping the existing .gitignore (not overwritten)." }

if (-not (Test-Path "push.ps1")) {
  @'
# Stage, commit and push. Pull with:  .\push.ps1 pull
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "Git is not installed." }
& git rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) { throw "Run this from inside a Git repository." }

$action = "push"
if ($Args.Count -gt 0 -and $Args[0] -eq "pull") { $action = "pull"; $Args = $Args[1..($Args.Count - 1)] }
elseif ($Args.Count -gt 0 -and $Args[0] -eq "push") { $Args = $Args[1..($Args.Count - 1)] }

& git remote get-url origin *> $null
if ($LASTEXITCODE -ne 0) { throw "No 'origin' remote. Run gitcli.ps1 first." }
$branch = (& git branch --show-current).Trim()
if (-not $branch) { throw "Could not determine the current branch." }

if ($action -eq "pull") { & git pull --ff-only origin $branch; exit $LASTEXITCODE }

$message = if ($Args.Count -gt 0) { $Args -join " " } else { Read-Host "Commit message" }
if ([string]::IsNullOrWhiteSpace($message)) { throw "Commit message cannot be empty." }

& git add -A
& git diff --cached --quiet
if ($LASTEXITCODE -ne 0) { & git commit -m $message } else { Write-Host "No staged changes." }
& git push -u origin $branch
'@ | Set-Content -Path "push.ps1" -Encoding UTF8
  Write-Ok "Created push.ps1"
} else { Write-Info "Keeping the existing push.ps1." }

Write-Host ""
Write-Warn "Review the files below before uploading. No passwords, keys or tokens should appear."
& git status --short

$firstMessage = Read-Ask "First commit message:" "Initial commit"
if ([string]::IsNullOrWhiteSpace($firstMessage)) { Die "Commit message cannot be empty." }

Invoke-Git @("add", "-A") | Out-Null
& git diff --cached --quiet
if ($LASTEXITCODE -ne 0) { Invoke-Git @("commit", "-m", $firstMessage) | Out-Null }
else {
  & git rev-parse --verify HEAD *> $null
  if ($LASTEXITCODE -ne 0) { Die "Nothing to commit and no existing commit." }
  Write-Info "No new files to commit."
}

Write-Info "Pushing branch main to origin..."
Invoke-Git @("push", "-u", "origin", "main") | Out-Null

Write-Host ""
Write-Panel $C.green "DONE" @(
  "Repository  $projectRoot",
  "Remote      $((& git remote get-url origin).Trim())",
  "Branch      main",
  "",
  'Next updates: .\push.ps1 "Describe your changes"'
)
Write-Host ""

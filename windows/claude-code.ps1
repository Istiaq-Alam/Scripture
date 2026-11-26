#requires -version 5.1
<#
  Claude Code on a local Ollama model - Windows port.
  Installs Ollama, picks a Gemma model for this machine, installs Claude Code
  and points the Anthropic endpoints at 127.0.0.1:11434.

  Run:
    powershell -ExecutionPolicy Bypass -File .\claude-code.ps1
#>

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$E = [char]27
$C = @{
  green = "$E[38;5;114m"; yellow = "$E[38;5;179m"; red = "$E[38;5;203m"
  cyan = "$E[38;5;111m"; accent = "$E[38;5;111m"
  muted = "$E[38;5;244m"; bold = "$E[1m"; nc = "$E[0m"
}
if ($env:NO_COLOR) { $colorKeys = @($C.Keys); foreach ($k in $colorKeys) { $C[$k] = '' } }

$TempDir = Join-Path $env:TEMP ("scripture-claude-" + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

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
  param([string]$Number, [string]$Total, [string]$Title)
  Clear-Ui; Write-Host ""
  Write-Host ("$($C.accent)❯$($C.nc) $($C.muted)step $Number of $Total$($C.nc) · $($C.bold)$Title$($C.nc)")
  Write-Rule; Write-Host ""
}
function Write-Ok   { param([string]$m) Write-Host ("  $($C.green)[OK]$($C.nc)   $m") }
function Write-Warn { param([string]$m) Write-Host ("  $($C.yellow)[WARN]$($C.nc) $m") }
function Write-Err  { param([string]$m) Write-Host ("  $($C.red)[FAIL]$($C.nc) $m") }
function Write-Info { param([string]$m) Write-Host ("  $($C.muted)$m$($C.nc)") }

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
  if (Test-Path $err) { Get-Content $err -Tail 10 | Where-Object { $_ } | ForEach-Object { Write-Host "      $_" } }
  return $false
}
function Test-Ollama {
  try {
    $response = Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 -Uri "http://127.0.0.1:11434/api/tags"
    return $response.StatusCode -eq 200
  } catch { return $false }
}

# --- Start ------------------------------------------------------------------
Clear-Ui
Write-Panel $C.accent "CLAUDE CODE · OLLAMA · WINDOWS" @(
  "A local model, a local endpoint, no hosted API.",
  "",
  "Steps: Ollama, a Gemma model, Node.js, Claude Code, environment."
)
Write-Host ""

Write-Step "0" "5" "Checking network"
try {
  Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 -Uri "https://ollama.com" | Out-Null
  Write-Ok "Internet reachable"
} catch {
  Write-Err "No internet connection detected (ollama.com unreachable)."
  exit 1
}

Write-Step "1" "5" "Ollama"
if (Get-Command ollama -ErrorAction SilentlyContinue) {
  Write-Ok "Ollama already installed"
} else {
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Err "winget is not available. Install Ollama from https://ollama.com/download/windows, then run again."
    exit 1
  }
  if (-not (Invoke-Exe "Installing Ollama" "winget" @("install", "--id", "Ollama.Ollama", "-e", "--source", "winget", "--accept-package-agreements", "--accept-source-agreements"))) {
    Write-Err "Ollama install failed."
    exit 1
  }
  Update-SessionPath
}

if (-not (Test-Ollama)) {
  Write-Info "Starting the Ollama server..."
  $ollama = Resolve-Exe "ollama"
  Start-Process -FilePath $ollama -ArgumentList "serve" -WindowStyle Hidden | Out-Null
  for ($i = 0; $i -lt 30; $i++) {
    if (Test-Ollama) { break }
    Start-Sleep -Seconds 1
  }
}
if (Test-Ollama) { Write-Ok "Ollama API is answering on 127.0.0.1:11434" }
else {
  Write-Err "Ollama did not start. Run 'ollama serve' in another window and retry."
  exit 1
}

Write-Step "2" "5" "Choose a Gemma model"
$ramGb = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
Write-Host ("  Detected RAM: " + $C.green + "$ramGb GB" + $C.nc)
Write-Host ""
if ($ramGb -le 8) { $suggested = "gemma4:e2b" }
elseif ($ramGb -le 16) { $suggested = "gemma4:e4b" }
else { $suggested = "gemma4:26b" }
Write-Info "Recommended for this machine: $suggested"
$pick = Show-Menu "Choose a model" @(
  "gemma4:e2b  (~3GB)  → 8GB RAM",
  "gemma4:e4b  (~7GB)  → 16GB RAM",
  "gemma4:26b (~18GB) → 32GB RAM"
) 1
$model = @("gemma4:e2b", "gemma4:e4b", "gemma4:26b")[$pick]
Write-Ok "Selected $model"

$listed = (& ollama list 2>$null) -join "`n"
if ($listed -match [regex]::Escape(($model -split ':')[0])) {
  Write-Ok "Model already present, skipping the download"
} else {
  Write-Info "Pulling $model (this can take a while)..."
  if (-not (Invoke-Exe "Downloading $model" "ollama" @("pull", $model))) { Write-Err "ollama pull failed"; exit 1 }
}

Write-Step "3" "5" "Node.js"
if (Get-Command node -ErrorAction SilentlyContinue) {
  Write-Ok "Node.js already installed ($(& node -v))"
} else {
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Err "Install Node.js from https://nodejs.org, then run again."
    exit 1
  }
  if (-not (Invoke-Exe "Installing Node.js LTS" "winget" @("install", "--id", "OpenJS.NodeJS.LTS", "-e", "--source", "winget", "--accept-package-agreements", "--accept-source-agreements"))) {
    Write-Err "Node.js install failed."
    exit 1
  }
  Update-SessionPath
}
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
  Write-Err "npm is missing from PATH. Open a new PowerShell window and run this script again."
  exit 1
}

Write-Step "4" "5" "Claude Code"
if (Get-Command claude -ErrorAction SilentlyContinue) {
  Write-Ok "Claude Code already installed"
} else {
  if (-not (Invoke-Exe "Installing Claude Code" "npm" @("install", "-g", "@anthropic-ai/claude-code"))) {
    Write-Err "Claude Code install failed. Try an elevated PowerShell."
    exit 1
  }
}
Write-Info "Claude Code version: $(& claude --version 2>$null)"

Write-Step "5" "5" "Environment"
$settings = [ordered]@{
  "ANTHROPIC_AUTH_TOKEN"             = "ollama"
  "ANTHROPIC_API_KEY"                = ""
  "ANTHROPIC_BASE_URL"               = "http://localhost:11434"
  "ANTHROPIC_DEFAULT_HAIKU_MODEL"    = $model
  "ANTHROPIC_DEFAULT_SONNET_MODEL"   = $model
  "ANTHROPIC_DEFAULT_OPUS_MODEL"     = $model
}
foreach ($name in $settings.Keys) {
  [Environment]::SetEnvironmentVariable($name, $settings[$name], 'User')
  Set-Item -Path "Env:$name" -Value $settings[$name]
  Write-Ok "$name set for your user"
}

Clear-Ui
Write-Panel $C.green "READY" @(
  "Ollama          running on 11434",
  "Model           $model",
  "Claude Code     installed",
  "Environment     six ANTHROPIC_ variables (user scope)",
  "",
  "Open a new PowerShell window, then run:  claude"
)
Write-Host ""

if (Read-Confirm "Test the model with a short prompt now?" "n") {
  Write-Info "Sending a test prompt to $model..."
  & ollama run $model "Hello, I am $env:USERNAME. Greet me in one sentence."
} else {
  Write-Info "Skipped the test prompt. Try it later with: ollama run $model"
}

Write-Host ""
Write-Info "Start Claude Code later with:"
Write-Host "    claude --model $model"
Write-Host "    ollama launch claude --model $model   # when your Ollama version supports it"
Write-Host ""

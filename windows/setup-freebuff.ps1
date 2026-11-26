#requires -version 5.1
<#
  Freebuff CLI on Windows, configured with a Gemini API key.
  Verifies the key, installs the CLI and writes one marked block to $PROFILE.

  Run:
    powershell -ExecutionPolicy Bypass -File .\setup-freebuff.ps1
#>

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# --- UI ---------------------------------------------------------------------
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
  if ($w -lt 60) { $w = 60 }
  if ($w -gt 96) { $w = 96 }
  return $w
}
function Clear-Ui {
  if (-not [Console]::IsOutputRedirected) { [Console]::Clear() }
}
function Write-Rule {
  $w = Get-UiWidth
  Write-Host ($C.muted + ('─' * $w) + $C.nc)
}
function Write-Panel {
  param([string]$Color, [string]$Title, [string[]]$Lines)
  $w = Get-UiWidth
  $inner = $w - 4
  $head = " $Title "
  $fill = $w - 3 - $head.Length
  if ($fill -lt 0) { $fill = 0 }
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
  Clear-Ui
  Write-Host ""
  Write-Host ("$($C.accent)❯$($C.nc) $($C.muted)step $Number of $Total$($C.nc) · $($C.bold)$Title$($C.nc)")
  Write-Rule
  Write-Host ""
}
function Write-Ok   { param([string]$m) Write-Host ("  $($C.green)[OK]$($C.nc)   $m") }
function Write-Warn { param([string]$m) Write-Host ("  $($C.yellow)[WARN]$($C.nc) $m") }
function Write-Err  { param([string]$m) Write-Host ("  $($C.red)[FAIL]$($C.nc) $m") }
function Write-Info { param([string]$m) Write-Host ("  $($C.muted)$m$($C.nc)") }
function Write-Kv   { param([string]$K, [string]$V) Write-Host ("  $($C.muted)$($K.PadRight(14))$($C.nc) $V") }

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
    Clear-Ui
    Write-Host ""
    Write-Host ("  " + $C.bold + $Title + $C.nc)
    Write-Host ""
    for ($i = 0; $i -lt $Items.Count; $i++) {
      if ($i -eq $sel) { Write-Host ("  " + $C.accent + "❯ " + $Items[$i] + $C.nc) }
      else { Write-Host ("    " + $Items[$i]) }
    }
    Write-Host ""
    Write-Host ("  " + $C.muted + "↑ ↓ move   Enter select" + $C.nc)
    $key = [Console]::ReadKey($true)
    switch ($key.Key) {
      'UpArrow'   { if ($sel -gt 0) { $sel-- } }
      'DownArrow' { if ($sel -lt $Items.Count - 1) { $sel++ } }
      { $_ -in 'Enter','Escape' } { return $sel }
      default {
        if ($key.KeyChar -eq 'k') { if ($sel -gt 0) { $sel-- } }
        if ($key.KeyChar -eq 'j') { if ($sel -lt $Items.Count - 1) { $sel++ } }
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
function Invoke-Exe {
  param([string]$Label, [string]$Exe, [string[]]$Arguments = @(), [int]$TimeoutSec = 1800)
  $out = Join-Path $env:TEMP ("scripture-" + [guid]::NewGuid().ToString('n') + ".out")
  $err = Join-Path $env:TEMP ("scripture-" + [guid]::NewGuid().ToString('n') + ".err")
  $exePath = Resolve-Exe $Exe
  $proc = Start-Process -FilePath $exePath -ArgumentList $Arguments -NoNewWindow -PassThru `
    -RedirectStandardOutput $out -RedirectStandardError $err
  $frames = '|', '/', '-', '\'
  $i = 0
  $start = Get-Date
  while (-not $proc.HasExited) {
    if (-not [Console]::IsOutputRedirected) {
      [Console]::Write("`r  $($C.accent)$($frames[$i % 4])$($C.nc) $Label")
    }
    $i++
    Start-Sleep -Milliseconds 140
    if (((Get-Date) - $start).TotalSeconds -gt $TimeoutSec) {
      try { $proc.Kill() } catch { }
      Write-Host "`r$(' ' * ($Label.Length + 6))`r"
      Write-Err "$Label timed out after $TimeoutSec seconds"
      return $false
    }
  }
  try { $proc.WaitForExit() } catch { }
  if (-not [Console]::IsOutputRedirected) { [Console]::Write("`r" + (' ' * ($Label.Length + 6)) + "`r") }
  if ($proc.ExitCode -eq 0) { Write-Ok $Label; return $true }
  Write-Err "$Label (exit $($proc.ExitCode))"
  $tail = @()
  if (Test-Path $out) { $tail += Get-Content $out -Tail 12 }
  if (Test-Path $err) { $tail += Get-Content $err -Tail 12 }
  $tail | Where-Object { $_ } | ForEach-Object { Write-Host "      $_" }
  return $false
}

# --- Flow -------------------------------------------------------------------
Clear-Ui
Write-Panel $C.accent "FREEBUFF CLI · WINDOWS" @(
  "Gemini key, the CLI, and one marked block in your PowerShell profile.",
  "",
  "Profile: $PROFILE",
  "Nothing is written until the key is verified."
)
Write-Host ""

Write-Step "1" "4" "Gemini API key"
$secure = Read-Host "  Paste your Google Gemini API key (AIza..., input hidden)" -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try { $geminiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }

if ([string]::IsNullOrWhiteSpace($geminiKey)) { Write-Err "API key cannot be empty."; exit 1 }

Write-Step "2" "4" "Verifying the key"
Write-Info "Checking Google's OpenAI-compatible endpoint..."
try {
  $response = Invoke-WebRequest -UseBasicParsing -TimeoutSec 20 `
    -Uri "https://generativelanguage.googleapis.com/v1beta/openai/models" `
    -Headers @{ Authorization = "Bearer $geminiKey" }
  if ($response.StatusCode -ne 200) { throw "HTTP $($response.StatusCode)" }
  Write-Ok "API key verified"
} catch {
  Write-Err "The key could not be verified: $($_.Exception.Message)"
  Write-Info "Create a new key in Google AI Studio and run this script again."
  exit 1
}

Write-Step "3" "4" "Freebuff CLI"
if (Get-Command freebuff -ErrorAction SilentlyContinue) {
  Write-Ok "freebuff already installed"
} else {
  if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Err "npm is not installed. Install Node.js first: winget install OpenJS.NodeJS.LTS"
    exit 1
  }
  Write-Info "Installing freebuff@latest globally..."
  if (-not (Invoke-Exe "Installing freebuff" "npm" @("install", "-g", "freebuff@latest"))) {
    Write-Err "npm install failed. Try running PowerShell as Administrator."
    exit 1
  }
}

Write-Step "4" "4" "PowerShell profile"
$profileDir = Split-Path -Parent $PROFILE
if ($profileDir -and -not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force | Out-Null; Write-Ok "Created $PROFILE" }

$startMarker = '# >>> freebuff-gemini-setup >>>'
$endMarker = '# <<< freebuff-gemini-setup <<<'
$lines = @()
if (Test-Path $PROFILE) { $lines = Get-Content $PROFILE }
$kept = New-Object System.Collections.Generic.List[string]
$inside = $false
foreach ($line in $lines) {
  if ($line -eq $startMarker) { $inside = $true; continue }
  if ($line -eq $endMarker) { $inside = $false; continue }
  if (-not $inside) { $kept.Add($line) }
}
$safeKey = $geminiKey.Replace('"', '`"').Replace('$', '`$')
$kept.Add("")
$kept.Add($startMarker)
$kept.Add('$env:GEMINI_API_KEY = "' + $safeKey + '"')
$kept.Add($endMarker)
[IO.File]::WriteAllLines($PROFILE, $kept, (New-Object System.Text.UTF8Encoding($false)))
Write-Ok "Saved GEMINI_API_KEY to your PowerShell profile (marked block)"

Write-Host ""
Write-Panel $C.green "READY" @(
  "Gemini key   verified",
  "freebuff     installed",
  "profile      $PROFILE",
  "",
  "Next:",
  "  . `$PROFILE",
  "  freebuff"
)
Write-Host ""

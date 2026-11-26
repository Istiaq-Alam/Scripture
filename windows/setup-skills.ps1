#requires -version 5.1
<#
  Setup-Skills - Windows
  Installs 5 frontend design skills + CLAUDE.md / AGENTS.md into the CURRENT
  project folder. Run it from your project root in PowerShell.

    .\setup-skills.ps1                 # interactive menu: pick a design
    .\setup-skills.ps1 -Brand linear   # pick a design directly
    .\setup-skills.ps1 -List           # list all designs and exit
    .\setup-skills.ps1 -SkipDesign     # skills only, no DESIGN.md
    .\setup-skills.ps1 -Debug          # show full output of every command

  Optional extras (the script ASKS you; switches skip the question):
    -Security / -NoSecurity         Claude-Red offensive security skills
    -Superpowers / -NoSuperpowers   obra/superpowers workflow skills
    -Unslop / -NoUnslop             heydamir/unslop (fix AI-looking UI)
#>
param(
  [string]$Brand = "",
  [switch]$List,
  [switch]$SkipDesign,
  [switch]$Debug,
  [ValidateSet("ask", "yes", "no")][string]$Security = "ask",
  [ValidateSet("ask", "yes", "no")][string]$Superpowers = "ask",
  [ValidateSet("ask", "yes", "no")][string]$Unslop = "ask"
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$E = [char]27
$C = @{
  green = "$E[38;5;114m"; yellow = "$E[38;5;179m"; red = "$E[38;5;203m"
  cyan = "$E[38;5;111m"; accent = "$E[38;5;111m"; magenta = "$E[38;5;141m"
  muted = "$E[38;5;244m"; bold = "$E[1m"; nc = "$E[0m"
}
if ($env:NO_COLOR) { $colorKeys = @($C.Keys); foreach ($k in $colorKeys) { $C[$k] = '' } }

$ProjectRoot = (Get-Location).Path
$LogDir = Join-Path $ProjectRoot ".design-setup-logs"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$TempDir = Join-Path $env:TEMP ("scripture-skills-" + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
$Failed = New-Object System.Collections.Generic.List[string]
$Done = New-Object System.Collections.Generic.List[string]

# --- UI ---------------------------------------------------------------------
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
  param([string]$Number, [string]$Total, [string]$Title)
  Clear-Ui; Write-Host ""
  Write-Host ("$($C.accent)❯$($C.nc) $($C.muted)step $Number of $Total$($C.nc) · $($C.bold)$Title$($C.nc)")
  Write-Rule; Write-Host ""
}
function Write-Ok   { param([string]$m) Write-Host ("  $($C.green)[OK]$($C.nc)   $m") }
function Write-Warn { param([string]$m) Write-Host ("  $($C.yellow)[WARN]$($C.nc) $m") }
function Write-Err  { param([string]$m) Write-Host ("  $($C.red)[FAIL]$($C.nc) $m") }
function Write-Info { param([string]$m) Write-Host ("  $($C.muted)$m$($C.nc)") }
function Write-Hint { param([string]$m) Write-Host ("  $($C.cyan)$m$($C.nc)") }
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
function Invoke-Exe {
  param([string]$Label, [string]$Exe, [string[]]$Arguments = @(), [int]$TimeoutSec = 1200)
  $out = Join-Path $TempDir ([guid]::NewGuid().ToString('n') + ".out")
  $err = Join-Path $TempDir ([guid]::NewGuid().ToString('n') + ".err")
  $proc = Start-Process -FilePath (Resolve-Exe $Exe) -ArgumentList $Arguments -NoNewWindow -PassThru `
    -RedirectStandardOutput $out -RedirectStandardError $err
  $frames = '|', '/', '-', '\'; $i = 0; $start = Get-Date
  while (-not $proc.HasExited) {
    if (-not [Console]::IsOutputRedirected) { [Console]::Write("`r  $($C.accent)$($frames[$i % 4])$($C.nc) $Label") }
    $i++
    Start-Sleep -Milliseconds 140
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
  if ($Debug) {
    if (Test-Path $out) { Get-Content $out -Tail 20 | ForEach-Object { Write-Host "      $_" } }
    if (Test-Path $err) { Get-Content $err -Tail 20 | ForEach-Object { Write-Host "      $_" } }
  }
  return $false
}

# --- Helpers ----------------------------------------------------------------
function Test-Skill {
  param([string]$Name)
  (Test-Path (Join-Path $ProjectRoot ".claude/skills/$Name/SKILL.md")) -or
  (Test-Path (Join-Path $ProjectRoot ".agents/skills/$Name/SKILL.md"))
}
function Install-Fallback {
  param([string]$Repo, [string]$Only = "")
  $dest = Join-Path $TempDir ("fb-" + ($Repo -replace '[\\/]', '-'))
  Write-Warn "Using the git fallback for $Repo"
  if (-not (Invoke-Exe "Clone $Repo" "git" @("clone", "--depth", "1", "https://github.com/$Repo.git", $dest))) { return $false }
  $found = $false
  $skillFiles = @(Get-ChildItem -Path $dest -Recurse -Filter "SKILL.md" -File -ErrorAction SilentlyContinue)
  foreach ($file in $skillFiles) {
    $dir = $file.Directory
    if ($Only -and $dir.Name -ne $Only) { continue }
    foreach ($target in @(".claude/skills", ".agents/skills")) {
      $destSkill = Join-Path $ProjectRoot (Join-Path $target $dir.Name)
      New-Item -ItemType Directory -Path $destSkill -Force | Out-Null
      Copy-Item -Path (Join-Path $dir.FullName '*') -Destination $destSkill -Recurse -Force
    }
    Write-Ok "Copied skill '$($dir.Name)'"
    $found = $true
  }
  return $found
}
function Install-Skill {
  param([string]$Label, [string[]]$Expected, [string]$Repo, [string]$Only = "", [string[]]$NpxArgs = @())
  $npxCommand = @("--yes", "skills", "add") + $NpxArgs + @("-a", "claude-code", "-y")
  $okRun = Invoke-Exe "Installing $Label" "npx" $npxCommand
  $verified = $true
  foreach ($name in $Expected) { if (-not (Test-Skill $name)) { $verified = $false } }
  if ($okRun -and $verified) {
    Write-Ok "$Label installed (verified: $($Expected -join ', '))"
    $Done.Add($Label)
    return
  }
  Write-Warn "$Label not found after npx. Trying the git fallback."
  if ((Install-Fallback -Repo $Repo -Only $Only) -and ($Expected | Where-Object { Test-Skill $_ })) {
    Write-Ok "$Label installed via fallback"
    $Done.Add($Label)
  } else {
    Write-Err "$Label failed. Logs: $LogDir"
    $Failed.Add($Label)
  }
}

# --- Prerequisites ----------------------------------------------------------
Clear-Ui
if (-not $List) {
  Write-Panel $C.accent "SETUP SKILLS · WINDOWS" @(
    "Design skills, a DESIGN.md and the rules your agent reads.",
    "",
    "Project: $ProjectRoot",
    "Nothing is written until you confirm a choice."
  )
  Write-Host ""
}
Write-Step "0" "5" "Checking prerequisites"

foreach ($cmd in @("git", "node", "npx")) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    Write-Err "'$cmd' is not installed (need git + Node.js 18+)."
    Write-Hint "Install Node: winget install OpenJS.NodeJS.LTS"
    Write-Hint "Install Git:  winget install Git.Git"
    exit 1
  }
}
$nodeVersion = (& node -v).Trim()
$nodeMajor = [int](($nodeVersion -replace '^v', '') -split '\.')[0]
if ($nodeMajor -lt 18) {
  Write-Err "Node $nodeVersion is too old. The skills CLI needs Node 18+."
  exit 1
}
Write-Ok "git $((& git --version) -replace 'git version ','') | node $nodeVersion"
Write-Info "Project root: $ProjectRoot"

if (-not (Invoke-Exe "Reaching github.com" "git" @("ls-remote", "--heads", "https://github.com/voltagent/awesome-design-md.git"))) {
  Write-Err "Cannot reach github.com. Check your internet, proxy or firewall."
  exit 1
}

New-Item -ItemType Directory -Path (Join-Path $ProjectRoot ".claude/skills") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $ProjectRoot ".agents/skills") -Force | Out-Null

# --- 1. Design system -------------------------------------------------------
$designNames = New-Object System.Collections.Generic.List[string]
$designPaths = New-Object System.Collections.Generic.List[string]

if ($SkipDesign) {
  Write-Warn "Skipping DESIGN.md (-SkipDesign)"
} else {
  Write-Step "1" "5" "Design system"
  $designRepo = Join-Path $TempDir "design-md"
  if (-not (Invoke-Exe "Downloading the design library" "git" @("clone", "--depth", "1", "https://github.com/voltagent/awesome-design-md.git", $designRepo))) {
    Write-Err "Could not download the design list. Get one manually: https://getdesign.md/"
    $Failed.Add("DESIGN.md")
  } else {
    Get-ChildItem -Path $designRepo -Recurse -Filter "DESIGN.md" -File |
      Where-Object { $_.FullName -notmatch '\\.git\\' } |
      Sort-Object FullName | ForEach-Object {
        $designNames.Add($_.Directory.Name)
        $designPaths.Add($_.FullName)
      }

    if ($designNames.Count -eq 0) {
      Write-Err "No DESIGN.md files found in the library. Use https://getdesign.md/"
      $Failed.Add("DESIGN.md")
    } elseif ($List) {
      Write-Info "Found $($designNames.Count) design systems"
      Write-Host ""
      for ($i = 0; $i -lt $designNames.Count; $i++) {
        Write-Host ("  {0,3}) {1}" -f ($i + 1), $designNames[$i]) -NoNewline
        if (($i + 1) % 3 -eq 0) { Write-Host "" }
      }
      Write-Host ""
      $designNames | Set-Content -Path (Join-Path $ProjectRoot "design-list.txt") -Encoding UTF8
      Write-Ok "Full list also saved to design-list.txt"
      exit 0
    } else {
      Write-Info "Found $($designNames.Count) design systems"
      $selected = -1
      if ($Brand) {
        for ($i = 0; $i -lt $designNames.Count; $i++) {
          if ($designNames[$i] -like "*$Brand*") { $selected = $i; break }
        }
        if ($selected -lt 0) { Write-Warn "Brand '$Brand' not found." }
      }
      if ($selected -lt 0) { $selected = Show-Menu "Choose a design system" $designNames.ToArray() 0 }
      $designPath = Join-Path $ProjectRoot "DESIGN.md"
      if (Test-Path $designPath) {
        Copy-Item $designPath (Join-Path $ProjectRoot "DESIGN.md.bak") -Force
        Write-Warn "Old DESIGN.md saved as DESIGN.md.bak"
      }
      Copy-Item $designPaths[$selected] $designPath -Force
      Write-Ok "DESIGN.md for '$($designNames[$selected])' copied to the project root"
    }
  }
}

# --- 2-5. Skills ------------------------------------------------------------
$skillNumber = 1
Write-Step ([string](++$skillNumber)) "5" "Installing: Impeccable"
Install-Skill -Label "Impeccable" -Expected @("impeccable") -Repo "pbakaus/impeccable" -Only "impeccable" `
  -NpxArgs @("pbakaus/impeccable")

Write-Step ([string](++$skillNumber)) "5" "Installing: Taste Skill"
Install-Skill -Label "Taste Skill" -Expected @("design-taste-frontend") -Repo "Leonxlnx/taste-skill" `
  -NpxArgs @("Leonxlnx/taste-skill")

Write-Step ([string](++$skillNumber)) "5" "Installing: Vercel Web Design Guidelines"
Install-Skill -Label "Vercel Web Design Guidelines" -Expected @("web-design-guidelines") `
  -Repo "vercel-labs/agent-skills" -Only "web-design-guidelines" `
  -NpxArgs @("https://github.com/vercel-labs/agent-skills", "--skill", "web-design-guidelines")

Write-Step ([string](++$skillNumber)) "5" "Installing: LP Design Skill"
Install-Skill -Label "LP Design Skill" -Expected @("landing-page-design") -Repo "elayadesign/ai-design-skills" `
  -Only "landing-page-design" -NpxArgs @("elayadesign/ai-design-skills", "--skill", "landing-page-design")

Write-Step "4" "5" "Optional packs"
Write-Panel $C.yellow "WARNING: offensive security pack" @(
  "About 50-80 red-team skills.",
  "Use them ONLY on systems you own or are authorized to test."
)
$wantSecurity = if ($Security -eq "yes") { $true } elseif ($Security -eq "no") { $false } else { Read-Confirm "Install the Claude-Red security skills?" "n" }
if ($wantSecurity) {
  Install-Skill -Label "Claude-Red security skills" -Expected @("offensive-advanced-redteam") `
    -Repo "SnailSploit/Claude-Red" -NpxArgs @("SnailSploit/Claude-Red", "--skill", "*")
} else { Write-Ok "Skipped security skills" }

$wantSuperpowers = if ($Superpowers -eq "yes") { $true } elseif ($Superpowers -eq "no") { $false } else { Read-Confirm "Install the Superpowers workflow skills?" "n" }
if ($wantSuperpowers) {
  Install-Skill -Label "Superpowers skills" -Expected @("using-superpowers", "brainstorming", "test-driven-development") `
    -Repo "obra/superpowers" -NpxArgs @("obra/superpowers", "--skill", "*")
} else { Write-Ok "Skipped Superpowers" }

$wantUnslop = if ($Unslop -eq "yes") { $true } elseif ($Unslop -eq "no") { $false } else { Read-Confirm "Install the Unslop skill?" "n" }
if ($wantUnslop) {
  Install-Skill -Label "Unslop skill" -Expected @("unslop") -Repo "heydamir/unslop" -Only "unslop" `
    -NpxArgs @("heydamir/unslop", "--skill", "unslop")
} else { Write-Ok "Skipped Unslop" }

# --- Mirror, MCP, Chromium --------------------------------------------------
Write-Step "4" "5" "Wiring up other agents"
Get-ChildItem -Path (Join-Path $ProjectRoot ".claude/skills") -Directory -ErrorAction SilentlyContinue | ForEach-Object {
  $target = Join-Path $ProjectRoot (Join-Path ".agents/skills" $_.Name)
  if (-not (Test-Path (Join-Path $target "SKILL.md"))) {
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Copy-Item -Path (Join-Path $_.FullName '*') -Destination $target -Recurse -Force
    Write-Ok "Mirrored $($_.Name)"
  }
}

$mcpPath = Join-Path $ProjectRoot ".mcp.json"
if (-not (Test-Path $mcpPath)) {
  @'
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["@playwright/mcp@latest"]
    }
  }
}
'@ | Set-Content -Path $mcpPath -Encoding UTF8
  Write-Ok "Created .mcp.json with Playwright MCP"
} elseif ((Get-Content $mcpPath -Raw) -match '"playwright"') {
  Write-Ok ".mcp.json already has playwright"
} else {
  Write-Warn ".mcp.json exists - add the playwright server manually"
}

if (Get-Command claude -ErrorAction SilentlyContinue) {
  if (-not (Invoke-Exe "Registering Playwright MCP with Claude Code" "claude" @("mcp", "add", "playwright", "npx", "@playwright/mcp@latest"))) {
    Write-Warn "'claude mcp add' failed (maybe already added) - .mcp.json is in place."
  }
}

if (-not (Invoke-Exe "Installing Chromium for Playwright" "npx" @("--yes", "playwright", "install", "chromium"))) {
  Write-Warn "Chromium install failed. Run manually: npx playwright install chromium"
}

# --- Rules files ------------------------------------------------------------
Write-Step "5" "5" "Writing agent rules"
$rules = @'
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
'@
$marker = "# Frontend Design Engineering Rules (Score 98/100 Pipeline)"
foreach ($file in @("CLAUDE.md", "AGENTS.md")) {
  $path = Join-Path $ProjectRoot $file
  if ((Test-Path $path) -and ((Get-Content $path -Raw) -match [regex]::Escape($marker))) {
    Write-Ok "$file already has the rules"
  } elseif (Test-Path $path) {
    Add-Content -Path $path -Value ("`r`n" + $rules) -Encoding UTF8
    Write-Ok "Appended rules to $file"
  } else {
    Set-Content -Path $path -Value $rules -Encoding UTF8
    Write-Ok "Created $file"
  }
}
foreach ($file in @("CLAUDE.md", "AGENTS.md")) {
  $path = Join-Path $ProjectRoot $file
  $content = Get-Content $path -Raw -ErrorAction SilentlyContinue
  if ($content -notmatch 'skill-instructions\.md') {
    Add-Content -Path $path -Value @'

## Skill instructions (MANDATORY)
At the start of every session, read ./skill-instructions.md and follow it for all work in this project.
'@ -Encoding UTF8
  }
}

$instructions = @'
# skill-instructions.md

> Generated by Setup-Skills on Windows. Re-run the script to refresh this file.

**AI AGENT: read this whole file at the start of every session in this project, then follow it for ALL work.**

## 0. Operating rules (MANDATORY)

1. Read this file first. Then read `./CLAUDE.md` or `./AGENTS.md` and `./DESIGN.md` (if they exist).
2. Before every task, decide which skills below apply. Open each applicable `SKILL.md` and follow it.
3. Never skip a skill to save time. Never invent rules you have not read.
4. If instructions conflict, use this priority: the user's explicit request > `DESIGN.md` > skill instructions > your own defaults.
5. A UI task is NOT finished until it passes the checklist in section 3.

## 1. Installed skills

- Impeccable - `.claude/skills/impeccable/SKILL.md`
- Taste Skill - `.claude/skills/design-taste-frontend/SKILL.md`
- Vercel Web Design Guidelines - `.claude/skills/web-design-guidelines/SKILL.md`
- LP Design Skill - `.claude/skills/landing-page-design/SKILL.md`
- Unslop (optional) - `.claude/skills/unslop/SKILL.md`

Open the SKILL.md before using a skill.

## 2. Workflow for every UI task

1. **Ground** - read `DESIGN.md`; use its exact tokens.
2. **Plan** - name the skills you will use and what you will build.
3. **Build** - follow the Taste Skill so the result does not look generic.
4. **Audit and polish** - run Impeccable on components, typography and backgrounds.
5. **Review** - run the Vercel Web Design Guidelines on the code.
6. **Browser QA** - open the page with Playwright, click the interactive elements, take a screenshot, fix visual bugs.
7. **Report** - say what you built and what you verified.

## 3. Definition of done

- [ ] Colors, fonts and spacing match `DESIGN.md`
- [ ] No purple-to-blue gradient headlines; SVG icons, not emoji tiles
- [ ] Buttons and close icons hit 24x24px (44x44px on mobile)
- [ ] Browser zoom is not disabled
- [ ] Every async action shows a loading state
- [ ] Impeccable audit and Vercel review done
- [ ] Screenshot taken in a real browser, no overflow or overlap

## 4. Browser QA tools

- Playwright MCP is configured in `.mcp.json`.
- Manual fallback: `npx playwright screenshot http://localhost:3000 shot.png`
- Missing browser: `npx playwright install chromium`

## 5. For the human

Start your agent here and say: **"Read skill-instructions.md and follow it for everything in this project."**
To change the design: `.\setup-skills.ps1 -Brand <name>` (the old DESIGN.md is kept as DESIGN.md.bak).
'@
Set-Content -Path (Join-Path $ProjectRoot "skill-instructions.md") -Value $instructions -Encoding UTF8
Write-Ok "Created skill-instructions.md"

# --- Summary ----------------------------------------------------------------
Clear-Ui
$rows = New-Object System.Collections.Generic.List[string]
$rows.Add("Folder: $ProjectRoot"); $rows.Add("")
function Add-Row([bool]$Present, [string]$Label, [string]$Missing = "not installed") {
  if ($Present) { $rows.Add("[OK]  $Label") } else { $rows.Add("[--]  $Label ($Missing)") }
}
Add-Row (Test-Path (Join-Path $ProjectRoot "DESIGN.md")) "DESIGN.md (design system)"
Add-Row (Test-Path (Join-Path $ProjectRoot "CLAUDE.md")) "CLAUDE.md (agent rules)"
Add-Row (Test-Path (Join-Path $ProjectRoot "AGENTS.md")) "AGENTS.md (agent rules)"
Add-Row (Test-Path $mcpPath) "Playwright MCP (.mcp.json)"
Add-Row (Test-Path (Join-Path $ProjectRoot "skill-instructions.md")) "skill-instructions.md"
Add-Row (Test-Skill "impeccable") "Skill: Impeccable"
Add-Row (Test-Skill "design-taste-frontend") "Skill: Taste Skill"
Add-Row (Test-Skill "web-design-guidelines") "Skill: Vercel Web Design Guidelines"
Add-Row (Test-Skill "landing-page-design") "Skill: LP Design (landing page)"
Add-Row (Test-Skill "offensive-advanced-redteam") "Optional: Claude-Red security skills"
Add-Row (Test-Skill "using-superpowers") "Optional: Superpowers skills"
Add-Row (Test-Skill "unslop") "Optional: Unslop skill"
$skillFolders = @(Get-ChildItem -Path (Join-Path $ProjectRoot ".claude/skills") -Directory -ErrorAction SilentlyContinue).Count
$rows.Add(""); $rows.Add("Total skill folders: $skillFolders")

$sumColor = if ($Failed.Count -gt 0) { $C.red } else { $C.green }
Write-Panel $sumColor "INSTALL REPORT" $rows.ToArray()
Write-Host ""

if ($Failed.Count -gt 0) {
  Write-Err "Some steps failed: $($Failed -join ', ')"
  Write-Info "Logs are in: $LogDir"
  exit 1
}
Remove-Item -Recurse -Force $LogDir -ErrorAction SilentlyContinue
Write-Panel $C.cyan "ALL DONE - NEXT STEPS" @(
  "1. Start your AI agent in this folder",
  "2. Tell it: Read skill-instructions.md and follow it",
  "3. Claude Code: try  /impeccable audit"
)
Write-Host ""

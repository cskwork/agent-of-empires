<#
.SYNOPSIS
    Install Agent of Empires (aoe) on Windows via WSL2.

.DESCRIPTION
    Native Windows is not supported by aoe — it depends on tmux and POSIX
    process handling. This installer sets up aoe inside your default WSL2
    distribution and registers a PowerShell wrapper (aoe.ps1) so you can
    run `aoe` from Windows Terminal, PowerShell, or cmd as if it were
    native. The wrapper transparently delegates to WSL2.

.PARAMETER InstallDir
    Where to place the Windows-side launcher (aoe.ps1, aoe.cmd).
    Defaults to "$env:LOCALAPPDATA\Programs\aoe".

.PARAMETER Distribution
    WSL distribution to install aoe into. Defaults to the WSL default
    distribution (`wsl --list --quiet` first line).

.PARAMETER SkipPathUpdate
    Don't touch the user PATH environment variable.

.EXAMPLE
    irm https://raw.githubusercontent.com/njbrake/agent-of-empires/main/scripts/install.ps1 | iex

.EXAMPLE
    .\install.ps1 -Distribution Ubuntu-22.04
#>

[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'Programs\aoe'),
    [string]$Distribution = '',
    [switch]$SkipPathUpdate
)

$ErrorActionPreference = 'Stop'

function Write-Info    { param([string]$m) Write-Host "[info] $m"    -ForegroundColor Cyan }
function Write-Ok      { param([string]$m) Write-Host "[ok] $m"      -ForegroundColor Green }
function Write-Warn    { param([string]$m) Write-Host "[warn] $m"    -ForegroundColor Yellow }
function Write-ErrMsg  { param([string]$m) Write-Host "[error] $m"   -ForegroundColor Red }

function Test-Wsl {
    try {
        $null = Get-Command wsl.exe -ErrorAction Stop
    } catch {
        return $false
    }
    # `wsl --status` exits non-zero when WSL is not installed even if wsl.exe is present.
    & wsl.exe --status *>$null
    return ($LASTEXITCODE -eq 0)
}

function Get-DefaultDistro {
    # `wsl --list --quiet` output is UTF-16LE; PowerShell handles it via [Console]::OutputEncoding.
    $prev = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
        $names = (& wsl.exe --list --quiet) -split "`r?`n" | Where-Object { $_ -and $_.Trim() }
    } finally {
        [Console]::OutputEncoding = $prev
    }
    if (-not $names) { return $null }
    return $names[0].Trim()
}

function Invoke-InDistro {
    param(
        [Parameter(Mandatory)] [string]$Distro,
        [Parameter(Mandatory)] [string]$BashCommand
    )
    & wsl.exe -d $Distro -e bash -lc $BashCommand
    return $LASTEXITCODE
}

# --- Preflight ---------------------------------------------------------------

Write-Info "Checking for WSL2..."
if (-not (Test-Wsl)) {
    Write-ErrMsg "WSL is not installed or not running."
    Write-Host ""
    Write-Host "Install WSL2 first:" -ForegroundColor Yellow
    Write-Host "    wsl --install" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Then re-run this installer. See:" -ForegroundColor Yellow
    Write-Host "    https://learn.microsoft.com/windows/wsl/install" -ForegroundColor Yellow
    exit 1
}
Write-Ok "WSL is available."

if (-not $Distribution) {
    $Distribution = Get-DefaultDistro
    if (-not $Distribution) {
        Write-ErrMsg "No WSL distribution found. Install one: `wsl --install -d Ubuntu`"
        exit 1
    }
}
Write-Info "Target WSL distribution: $Distribution"

# Confirm the distro actually responds.
& wsl.exe -d $Distribution -e true *>$null
if ($LASTEXITCODE -ne 0) {
    Write-ErrMsg "WSL distribution '$Distribution' is not reachable."
    exit 1
}

# --- Install aoe inside WSL --------------------------------------------------

Write-Info "Installing aoe inside WSL ($Distribution)..."
$installCmd = 'curl -fsSL https://raw.githubusercontent.com/njbrake/agent-of-empires/main/scripts/install.sh | bash'
$rc = Invoke-InDistro -Distro $Distribution -BashCommand $installCmd
if ($rc -ne 0) {
    Write-ErrMsg "Linux-side installer failed (exit $rc). Open WSL and inspect manually:"
    Write-Host "    wsl -d $Distribution" -ForegroundColor Yellow
    exit $rc
}

# Verify aoe is on the WSL PATH (login shell so .bashrc/.zshrc-managed PATHs load).
$probe = (& wsl.exe -d $Distribution -e bash -lc 'command -v aoe').Trim()
if (-not $probe) {
    Write-Warn "aoe installed but not on the WSL login shell PATH."
    Write-Warn "Add `$HOME/.local/bin` to PATH in your WSL shell rc file."
} else {
    Write-Ok "aoe installed at: $probe (inside $Distribution)"
}

# tmux is mandatory for aoe.
$tmuxProbe = (& wsl.exe -d $Distribution -e bash -lc 'command -v tmux').Trim()
if (-not $tmuxProbe) {
    Write-Warn "tmux is not installed inside $Distribution. aoe requires it."
    Write-Warn "Install with: sudo apt-get install -y tmux  (or your distro's equivalent)"
}

# --- Install Windows-side launcher ------------------------------------------

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

$wrapperDst = Join-Path $InstallDir 'aoe.ps1'
$cmdShimDst = Join-Path $InstallDir 'aoe.cmd'

# When run via `irm | iex` there is no $PSScriptRoot; otherwise prefer the
# sibling aoe.ps1 from the same checkout.
$wrapperSrc = $null
if ($PSScriptRoot) {
    $candidate = Join-Path $PSScriptRoot 'aoe.ps1'
    if (Test-Path $candidate) { $wrapperSrc = $candidate }
}
if ($wrapperSrc) {
    Copy-Item -Path $wrapperSrc -Destination $wrapperDst -Force
} else {
    $wrapperUrl = 'https://raw.githubusercontent.com/njbrake/agent-of-empires/main/scripts/aoe.ps1'
    try {
        Invoke-WebRequest -Uri $wrapperUrl -OutFile $wrapperDst -UseBasicParsing
    } catch {
        Write-ErrMsg "Could not fetch aoe.ps1 from $wrapperUrl"
        throw
    }
}

# aoe.cmd is a tiny shim so `aoe` works from cmd.exe and from inside other
# tools that spawn a child process without PowerShell.
@'
@echo off
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0aoe.ps1" %*
'@ | Set-Content -LiteralPath $cmdShimDst -Encoding ASCII

# Pin the default distro for the wrapper so the user's wsl default change
# won't silently retarget aoe at an unprepared distro.
$configDir = Join-Path $env:APPDATA 'aoe'
if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
}
@{
    distribution = $Distribution
    installed_at = (Get-Date -Format 'o')
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $configDir 'windows.json') -Encoding UTF8

Write-Ok "Launcher installed: $wrapperDst"
Write-Ok "Config written: $(Join-Path $configDir 'windows.json')"

# --- PATH update -------------------------------------------------------------

if (-not $SkipPathUpdate) {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries  = ($userPath -split ';') | Where-Object { $_ -ne '' }
    if ($entries -notcontains $InstallDir) {
        [Environment]::SetEnvironmentVariable('Path', (($entries + $InstallDir) -join ';'), 'User')
        Write-Ok "Added $InstallDir to user PATH (open a new terminal to pick it up)."
    } else {
        Write-Info "$InstallDir is already on user PATH."
    }
}

Write-Host ""
Write-Ok "Done. Test with: aoe --version"
Write-Host "Detach from a tmux session inside aoe with: Ctrl+b d"

<#
.SYNOPSIS
    Windows launcher for Agent of Empires (aoe).

.DESCRIPTION
    Native Windows is not supported. This wrapper transparently runs `aoe`
    inside your configured WSL2 distribution, forwarding arguments and
    translating Windows-style paths to their WSL mount points
    (C:\foo\bar -> /mnt/c/foo/bar) so commands like:

        aoe add --cmd claude --dir C:\src\my-proj

    work the same as on Linux/macOS.

    To bypass path translation for a single argument, prefix it with the
    literal token "wsl:" — everything after the prefix is passed through
    unchanged (useful for paths that already live inside the WSL
    filesystem, e.g. `wsl:/home/me/proj`).

.NOTES
    Configuration: %APPDATA%\aoe\windows.json
        {
          "distribution": "Ubuntu-22.04"
        }

    Environment overrides (take precedence over the config file):
        AOE_WSL_DISTRO   - WSL distribution name
        AOE_WSL_USER     - run inside WSL as this user (default: distro default)
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$Arguments
)

$ErrorActionPreference = 'Stop'

function Get-WslConfig {
    $configPath = Join-Path $env:APPDATA 'aoe\windows.json'
    if (Test-Path $configPath) {
        try {
            return Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        } catch {
            Write-Host "[aoe] warning: $configPath is invalid JSON, ignoring." -ForegroundColor Yellow
        }
    }
    return $null
}

function Resolve-Distribution {
    if ($env:AOE_WSL_DISTRO) { return $env:AOE_WSL_DISTRO }
    $cfg = Get-WslConfig
    if ($cfg -and $cfg.distribution) { return [string]$cfg.distribution }
    # Fall back to wsl default.
    $prev = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
        $names = (& wsl.exe --list --quiet) -split "`r?`n" | Where-Object { $_ -and $_.Trim() }
    } finally {
        [Console]::OutputEncoding = $prev
    }
    if ($names) { return $names[0].Trim() }
    return $null
}

function ConvertTo-WslPath {
    param([string]$Path)
    # Token escape: caller marked the arg as already-WSL with a `wsl:` prefix.
    if ($Path.StartsWith('wsl:')) {
        return $Path.Substring(4)
    }
    # Drive-letter path: C:\foo\bar  or  c:/foo/bar
    if ($Path -match '^[A-Za-z]:[\\/]') {
        $drive = $Path.Substring(0,1).ToLower()
        $rest  = $Path.Substring(2) -replace '\\','/'
        # Collapse any leading slash so we get /mnt/c/foo not /mnt/c//foo
        $rest  = $rest.TrimStart('/')
        return "/mnt/$drive/$rest"
    }
    # UNC path \\server\share\foo — WSL has no automatic mount, pass through and let the user know.
    if ($Path.StartsWith('\\')) {
        Write-Host "[aoe] note: UNC path '$Path' is not auto-mounted in WSL; ensure your distro can resolve it." -ForegroundColor Yellow
        return $Path
    }
    return $Path
}

function Looks-LikePath {
    param([string]$Value)
    if (-not $Value) { return $false }
    if ($Value.StartsWith('wsl:'))           { return $true }
    if ($Value -match '^[A-Za-z]:[\\/]')     { return $true }
    if ($Value.StartsWith('\\'))             { return $true }
    return $false
}

function Quote-Bash {
    param([string]$Value)
    # Single-quote and escape inner single quotes the POSIX way.
    return "'" + ($Value -replace "'", "'\''") + "'"
}

# --- Main --------------------------------------------------------------------

$distro = Resolve-Distribution
if (-not $distro) {
    Write-Host "[aoe] error: could not determine WSL distribution. Set AOE_WSL_DISTRO or re-run install.ps1." -ForegroundColor Red
    exit 1
}

# Translate path-shaped arguments. Non-paths pass through untouched.
$translated = @()
foreach ($a in $Arguments) {
    if (Looks-LikePath $a) {
        $translated += (ConvertTo-WslPath $a)
    } else {
        $translated += $a
    }
}

# Build a quoted bash command so word splitting inside WSL matches the
# original Windows arg vector. `exec` keeps the process tree clean so Ctrl+C
# is forwarded straight to aoe.
$quoted = ($translated | ForEach-Object { Quote-Bash $_ }) -join ' '
$bashCmd = "exec aoe $quoted"

$wslArgs = @('-d', $distro)
if ($env:AOE_WSL_USER) {
    $wslArgs += @('-u', $env:AOE_WSL_USER)
}
$wslArgs += @('-e', 'bash', '-lc', $bashCmd)

# Hand off — `aoe` is a TUI so we want the WSL process to own the terminal.
& wsl.exe @wslArgs
exit $LASTEXITCODE

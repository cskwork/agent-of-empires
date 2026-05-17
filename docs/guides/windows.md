# Windows

`aoe` does not run as a native Windows binary. It depends on `tmux` and POSIX
process handling for session persistence — both unavailable outside a Unix
environment.

This fork ships a **WSL2 bridge** so you can drive `aoe` from PowerShell,
cmd, or Windows Terminal exactly as if it were native. The wrapper
transparently forwards every invocation into your WSL2 distribution, where
the real Linux `aoe` runs.

## What you get

- `aoe` is callable from PowerShell, cmd.exe, or Windows Terminal.
- Path arguments are translated automatically: `C:\src\foo` becomes
  `/mnt/c/src/foo` before reaching the Linux side.
- Sessions persist across terminal restarts because `aoe` and `tmux` are
  running inside WSL2 the whole time.
- The web dashboard (`aoe serve`) listens inside WSL2 and is reachable on
  `http://localhost:<port>` from your Windows browser thanks to WSL2's
  localhost forwarding.

## What you don't get (yet)

- No standalone `.exe` build. `aoe.exe` does not exist; native Windows
  support would require replacing tmux with a ConPTY-based multiplexer.
- No Docker sandboxing inside Docker Desktop on Windows unless Docker
  Desktop's WSL integration is enabled for your distro.
- Slightly slower file I/O when working against `/mnt/c/...` paths — for
  best performance, keep agent workspaces inside the WSL filesystem
  (`/home/<you>/...`) and pass them with the `wsl:` prefix (below).

## Install

### Option A: one-liner (PowerShell)

```powershell
irm https://raw.githubusercontent.com/njbrake/agent-of-empires/main/scripts/install.ps1 | iex
```

This will:

1. Verify WSL2 is installed.
2. Run the Linux `install.sh` inside your default WSL distro.
3. Drop `aoe.ps1` + `aoe.cmd` into `%LOCALAPPDATA%\Programs\aoe` and add
   that directory to your user `PATH`.
4. Pin the chosen distribution in `%APPDATA%\aoe\windows.json`.

### Option B: target a specific distribution

```powershell
git clone https://github.com/njbrake/agent-of-empires
cd agent-of-empires
.\scripts\install.ps1 -Distribution Ubuntu-22.04
```

## Prerequisites inside WSL

`aoe` requires `tmux`. On Ubuntu/Debian:

```bash
sudo apt-get update && sudo apt-get install -y tmux git
```

If you want the Docker sandbox feature, enable Docker Desktop's WSL
integration for the same distro:

> Docker Desktop → Settings → Resources → WSL Integration → enable for `<your-distro>`.

## Daily usage

From PowerShell or Windows Terminal:

```powershell
aoe                              # launch TUI
aoe add --cmd claude             # create a Claude Code session
aoe add --cmd claude --dir C:\src\my-project    # path is translated
aoe serve                        # web dashboard on http://localhost:<port>
```

### Path translation rules

| Windows path                  | WSL path passed to `aoe`                |
| ----------------------------- | --------------------------------------- |
| `C:\src\foo`                  | `/mnt/c/src/foo`                        |
| `D:/data/proj`                | `/mnt/d/data/proj`                      |
| `\\server\share\dir`          | passed through; not auto-mounted in WSL |
| `wsl:/home/danny/proj`        | `/home/danny/proj` (prefix stripped)    |
| `wsl:~/proj`                  | `~/proj`                                |

The `wsl:` prefix is an escape hatch for paths that already live inside
the WSL filesystem — prefer them for performance.

### Choosing the distribution

The installer pins a default in `%APPDATA%\aoe\windows.json`:

```json
{ "distribution": "Ubuntu-22.04" }
```

Override per-invocation with `AOE_WSL_DISTRO`:

```powershell
$env:AOE_WSL_DISTRO = 'Debian'
aoe
```

To run as a different user inside the distro:

```powershell
$env:AOE_WSL_USER = 'danny'
aoe
```

## Troubleshooting

### `aoe` says it can't find tmux

Open the WSL distribution and install tmux:

```powershell
wsl -d Ubuntu-22.04
# inside WSL:
sudo apt-get install -y tmux
```

### `aoe` is not recognized

Restart your terminal. The installer added
`%LOCALAPPDATA%\Programs\aoe` to your user `PATH`, but a running shell
keeps its old environment until restarted.

### Web dashboard URL doesn't open

Check that WSL2's localhost forwarding is enabled (it is by default).
Test from PowerShell:

```powershell
wsl -d Ubuntu-22.04 -e bash -lc "curl -s http://localhost:8765/health"
```

### I want a real native Windows port

Open an issue. The architectural cost is high — replacing `tmux` with
ConPTY + a Windows-aware session manager, gating ~85 `nix::` and
`std::os::unix` call sites, and porting the install scripts. Pull
requests welcome.

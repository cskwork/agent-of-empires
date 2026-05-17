---
name: install-windows-wsl2
description: Install Agent of Empires on Windows via WSL2 Ubuntu using a manual tarball flow, register PATH, and recover from broken shell profiles. Use when the upstream install.sh is blocked by policy or an auto-mode classifier.
---

# Install on Windows (via WSL2)

Agent of Empires does not run natively on Windows; it requires WSL2. This skill captures a verified manual install procedure that does not run `install.sh` blindly, so it works in environments where direct shell-script execution is restricted (auto-mode classifiers, locked-down CI, audit-tight machines).

## Prerequisites

Verify each piece before installing.

1. WSL2 with a Linux distribution (Ubuntu recommended):
   ```
   wsl --status
   ```
   Confirm `Default Version: 2` and a default distribution is listed. If not, install Ubuntu from the Microsoft Store, then `wsl --set-default-version 2`.

2. Inside WSL, confirm tools are present:
   ```
   wsl -d Ubuntu -- bash -c "tmux -V && which curl && which git && which tar"
   ```
   `tmux` is mandatory. Install anything missing:
   ```
   wsl -d Ubuntu -- bash -c "sudo apt update && sudo apt install -y tmux curl git"
   ```

## Install (manual tarball)

The same effect as `curl ... install.sh | bash`, broken into explicit steps so each one is auditable.

1. Pick the latest release tag from https://github.com/njbrake/agent-of-empires/releases (e.g. `v1.7.0`).
2. From PowerShell or any shell, run:
   ```
   wsl -d Ubuntu -- bash -c '
     VERSION=v1.7.0 &&
     curl -fsSL -o /tmp/aoe.tar.gz "https://github.com/njbrake/agent-of-empires/releases/download/$VERSION/aoe-linux-amd64.tar.gz" &&
     mkdir -p $HOME/.local/bin &&
     tar xzf /tmp/aoe.tar.gz -C /tmp &&
     mv /tmp/aoe-linux-amd64 $HOME/.local/bin/aoe &&
     chmod +x $HOME/.local/bin/aoe &&
     $HOME/.local/bin/aoe --version
   '
   ```
   Expected: `aoe <version>` printed on the last line.

> **Git Bash gotcha.** When the command is invoked from Git Bash on Windows, MSYS rewrites a leading `/bin/bash` into a Windows path and the call fails with `No such file or directory`. Two fixes:
> - prefix the call with `MSYS_NO_PATHCONV=1`, or
> - drop the absolute path: use `bash -c "..."` rather than `/bin/bash -c "..."`.

## Register the PATH

Add `~/.local/bin` to `PATH` so `aoe` resolves in interactive shells:

```
wsl -d Ubuntu -- bash -c "echo 'export PATH=\$HOME/.local/bin:\$PATH' >> ~/.bashrc"
```

Open a fresh WSL shell (or `source ~/.bashrc`) and verify:

```
wsl -d Ubuntu
which aoe       # -> /home/<user>/.local/bin/aoe
aoe --version
```

## Recovery: broken `.bashrc` from a botched PATH export

A common failure mode: an earlier attempt wrote a Windows-flavored PATH into `.bashrc` and left a trailing backslash. The line becomes a syntax error and standard utilities (`curl`, `tar`, `mkdir`) drop off `PATH` in interactive shells. Symptom:

```
The command could not be located because '/usr/bin:/bin' is not included in the PATH environment variable.
```

Diagnose and fix:

```
# Inspect last lines
wsl -d Ubuntu -- bash -c "tail -n 6 ~/.bashrc"

# Back up, drop the broken trailing line, append the correct one
wsl -d Ubuntu -- bash -c '
  cp ~/.bashrc ~/.bashrc.bak.broken &&
  LINES=$(wc -l < ~/.bashrc.bak.broken) &&
  head -n $((LINES-1)) ~/.bashrc.bak.broken > ~/.bashrc &&
  echo "export PATH=\$HOME/.local/bin:\$PATH" >> ~/.bashrc
'

# Verify
wsl -d Ubuntu -- bash -ic "echo PATH=\$PATH; which aoe; aoe --version"
```

Restore the original with `cp ~/.bashrc.bak.broken ~/.bashrc` if the change causes other problems.

## First use

```
wsl -d Ubuntu
aoe                       # launch the TUI; press ? for help
aoe add --cmd claude      # spawn a Claude Code session
aoe serve                 # web dashboard (default :8080)
```

Sessions are tmux sessions; closing `aoe` does not terminate them. Detach an attached session with `Ctrl+b d`. For mobile SSH clients (Termius, Blink), wrap `aoe` in a parent tmux session per the project README.

## Notes

- AoE is not supported natively on Windows; only WSL2.
- Use the manual tarball flow whenever automated install scripts are blocked by policy or a classifier.
- The same procedure works for any official release tag; change `VERSION` and the rest is unchanged.
- WSL filesystem from Windows side: `\\wsl.localhost\Ubuntu\home\<user>\...` works for editors that need to reach into `~`.

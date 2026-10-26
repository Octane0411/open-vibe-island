# SSH Remote Agent Setup

Connect Open Island to agents running on a remote server over SSH. The Python setup below is for Claude Code; Pi and Oh My Pi use their TypeScript extension instead.

## How it works

```
macOS (local)                         Remote server
┌──────────────┐    SSH tunnel     ┌────────────────────┐
│ Open Island  │◀═══════════════▶│ Unix socket (fwd)  │
│ BridgeServer │   RemoteForward   │        ▲           │
│ Unix socket  │                   │        │           │
└──────────────┘                   │  open-island-      │
                                   │  hooks.py          │
                                   │        ▲           │
                                   │        │           │
                                   │  Claude Code       │
                                   └────────────────────┘
```

SSH's `RemoteForward` tunnels the Unix socket from your Mac to the remote server. The Python hook client (`open-island-hooks.py`) connects to the forwarded socket, and the bridge protocol works identically to the local case.

## Prerequisites

- Open Island running on your Mac
- SSH access to the remote server
- Python 3.6+ on the remote server
- Claude Code installed on the remote server

## Quick setup

Run the automated setup script:

```bash
./scripts/remote-setup.sh user@myserver
```

This will:
1. Copy `open-island-hooks.py` to the remote server (`~/.local/bin/`)
2. Configure Claude Code hooks in `~/.claude/settings.json` on the remote
3. Print the SSH config snippet you need

## Manual setup

### 1. Deploy the hook script

```bash
scp scripts/open-island-hooks.py user@myserver:~/.local/bin/
ssh user@myserver chmod +x ~/.local/bin/open-island-hooks.py
```

### 2. Configure Claude Code hooks on the remote

Edit `~/.claude/settings.json` on the remote server:

```json
{
  "hooks": {
    "PreToolUse": [{ "type": "command", "command": "python3 ~/.local/bin/open-island-hooks.py --source claude" }],
    "PostToolUse": [{ "type": "command", "command": "python3 ~/.local/bin/open-island-hooks.py --source claude" }],
    "SessionStart": [{ "type": "command", "command": "python3 ~/.local/bin/open-island-hooks.py --source claude" }],
    "SessionEnd": [{ "type": "command", "command": "python3 ~/.local/bin/open-island-hooks.py --source claude" }],
    "PermissionRequest": [{ "type": "command", "command": "python3 ~/.local/bin/open-island-hooks.py --source claude" }],
    "Notification": [{ "type": "command", "command": "python3 ~/.local/bin/open-island-hooks.py --source claude" }],
    "Stop": [{ "type": "command", "command": "python3 ~/.local/bin/open-island-hooks.py --source claude" }],
    "UserPromptSubmit": [{ "type": "command", "command": "python3 ~/.local/bin/open-island-hooks.py --source claude" }],
    "SubagentStart": [{ "type": "command", "command": "python3 ~/.local/bin/open-island-hooks.py --source claude" }],
    "SubagentStop": [{ "type": "command", "command": "python3 ~/.local/bin/open-island-hooks.py --source claude" }]
  }
}
```

### 3. Configure SSH socket forwarding

Add to your local `~/.ssh/config`:

```
Host myserver
    HostName myserver.example.com
    User youruser
    RemoteForward /tmp/open-island-501.sock /tmp/open-island-501.sock
```

Replace `501` with your local UID (`id -u`).

Or connect directly with:

```bash
ssh -R /tmp/open-island-$(id -u).sock:/tmp/open-island-$(id -u).sock user@myserver
```

### 4. Verify

1. Make sure Open Island is running on your Mac
2. SSH to the remote with socket forwarding enabled
3. Run Claude Code on the remote — sessions should appear in the Open Island overlay

## Important: sshd configuration

The remote server's sshd must allow cleaning up stale socket files on reconnect. Ask the server admin to add this to `/etc/ssh/sshd_config`:

```
StreamLocalBindUnlink yes
```

Without this, reconnecting after a dropped SSH session will fail with "Address already in use" because the old socket file is still on disk.

## Mac-to-Mac Setup (Different UIDs)

When both machines are macOS but have different UIDs (common when local and remote machines were set up independently), the default socket path on the remote will not match the forwarded socket from the local machine.

**Check your UIDs:**

```bash
# On local Mac
id -u  # e.g. 502

# On remote Mac
id -u  # e.g. 501
```

**If UIDs differ**, configure `RemoteForward` to map the remote UID socket to the local UID socket:

```
Host myserver
    HostName 192.168.x.x
    User youruser
    RemoteForward /tmp/open-island-<remote-uid>.sock /tmp/open-island-<local-uid>.sock
```

Then set the socket path explicitly on the remote machine so the hook can find it:

```bash
# Add to ~/.zshrc on remote Mac
export OPEN_ISLAND_SOCKET_PATH=/tmp/open-island-<remote-uid>.sock
export VIBE_ISLAND_SOCKET_PATH=/tmp/open-island-<remote-uid>.sock
```

> **Note:** This was tested on a Mac-to-Mac configuration. The default documentation assumes matching UIDs (e.g. Docker environments where UID is typically `1000` on both ends).

## Troubleshooting

**Sessions not appearing?**

- Check the socket exists on remote: `ls -la /tmp/open-island-*.sock`
- Test connectivity: `python3 -c "import socket; s=socket.socket(socket.AF_UNIX); s.connect('/tmp/open-island-$(id -u).sock'); print('OK')"`
- Make sure Open Island is running locally before establishing the SSH connection

**"Address already in use" on SSH connect?**

The remote socket file from a previous session wasn't cleaned up:

```bash
ssh user@myserver rm /tmp/open-island-*.sock
```

Then reconnect.

**Permission denied on the socket?**

Ensure the remote UID in the socket filename matches your local UID. If they differ, set the socket path explicitly:

```bash
# In SSH config:
RemoteForward /tmp/open-island-remote.sock /tmp/open-island-501.sock

# On remote, set env var (add to ~/.bashrc):
export OPEN_ISLAND_SOCKET_PATH=/tmp/open-island-remote.sock
```

## Pi and Oh My Pi (OMP)

Use an Open Island build containing Pi/OMP remote recognition and reinstall the extension from **Settings → Setup → CLI Hooks**. Managed extension version 5 detects non-empty `SSH_CONNECTION`, `SSH_CLIENT`, or `SSH_TTY`, and also recognizes Remote-SSH through the VS Code companion below. The app shows the SSH badge and preserves remote identity across heartbeat recovery and registry restore. Updating only the extension does not add remote recognition or precise terminal jumps to older app builds, including 1.2.1.

For OMP, copy the installed extension to the remote machine:

```bash
ssh user@server 'mkdir -p ~/.omp/agent/extensions'
scp ~/.omp/agent/extensions/open-island.ts user@server:~/.omp/agent/extensions/open-island.ts
```

For Pi, substitute `~/.pi/agent/extensions` on both sides. Copy the installed file, not the bundled template containing `__OPEN_ISLAND_PI_SOURCE__`. The Claude-specific `remote-setup.sh` is not needed.

Forward a socket in a private remote directory to the Mac's current bridge path:

```bash
ssh user@server 'mkdir -p ~/.open-island; chmod 700 ~/.open-island'
ssh -o ExitOnForwardFailure=yes \
  -R "/home/REMOTE_USER/.open-island/bridge.sock:$HOME/Library/Application Support/OpenIsland/bridge.sock" \
  user@server
```

Replace `/home/REMOTE_USER` with the actual remote home directory. In that remote shell:

```bash
OPEN_ISLAND_SOCKET_PATH="$HOME/.open-island/bridge.sock" omp
```

Keep the SSH tunnel open and restart existing Pi/OMP sessions after installing or updating the extension. In tmux, the agent must inherit an SSH environment variable; sessions launched without those variables cannot infer remote origin. The socket override alone is not treated as proof of a remote session because local setups can also use custom sockets.

If reconnecting fails because the socket already exists, follow the sshd `StreamLocalBindUnlink` guidance above or remove only the known stale socket after confirming its listener is disconnected. Never remove a live socket.

This transports live status, not historical session files. The SSH flag alone does not provide a local terminal-tab mapping or precise remote tmux jump-back.

### Exact VS Code Remote-SSH terminal jump

Build the dependency-free companion from this checkout:

```bash
cd vscode-terminal-jump
npx --yes @vscode/vsce package --allow-missing-repository --skip-license --out ../open-island-terminal-jump.vsix
```

Install the VSIX into the **SSH remote** extension host using **Extensions: Install from VSIX** in the Remote-SSH window, or run `code --install-extension /path/to/open-island-terminal-jump.vsix` in that window's remote terminal. The extension ID is `open-island.terminal-jump`; it is a locally built companion, not a Marketplace dependency.

Use the patched Mac app and managed Pi/OMP extension version 5 together. Reload the agent extensions with `/reload` while idle, or restart the agent. Existing VS Code terminals do not need recreation. The companion registers their shell process IDs in private `~/.cache/open-island/vscode-terminals` files; the agent matches its process ancestry and reports the window-routed URI. Heartbeats update that locator without resetting task state. Records refresh every 15 seconds and the agent rejects records older than 45 seconds.

Clicking the island item asks VS Code to focus the exact existing terminal, even when several terminals share a directory. No SSH login, terminal creation, shell input, or Accessibility permission is used for this jump. A closed terminal or expired window token is reported as stale rather than selecting a different terminal. Reloading/reconnecting the VS Code window refreshes routing on subsequent heartbeats. Check the **Open Island Terminal Jump** output channel for focus results.

Without the companion, existing workspace-level jumping remains best-effort; exact tmux pane selection inside a remote VS Code terminal is not provided.

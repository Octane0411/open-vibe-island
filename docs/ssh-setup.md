# SSH Remote Agent Setup

Connect Open Island to Claude Code or Codex CLI running on a remote server over SSH.

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
                                   │  Claude Code /     │
                                   │  Codex CLI         │
                                   └────────────────────┘
```

SSH's `RemoteForward` tunnels the Unix socket from your Mac to the remote server. The Python hook client (`open-island-hooks.py`) connects to the forwarded socket, and the bridge protocol works identically to the local case.

## Prerequisites

- Open Island running on your Mac
- SSH access to the remote server
- Python 3.6+ on the remote server
- Claude Code or Codex CLI installed on the remote server

## Quick setup

For Claude Code, run:

```bash
./scripts/remote-setup.sh user@myserver
```

This will:
1. Copy `open-island-hooks.py` to the remote server (`~/.local/bin/`)
2. Configure Claude Code hooks in `~/.claude/settings.json` on the remote
3. Print the SSH config snippet you need

For Codex CLI, run:

```bash
./scripts/remote-setup-codex.sh user@myserver
```

This will:
1. Copy `open-island-hooks.py` to the remote server (`~/.local/bin/`)
2. Configure Codex hooks in `~/.codex/hooks.json` on the remote
3. Enable `[features].hooks = true` in `~/.codex/config.toml`
4. Print the SSH config snippet you need

After installing Codex hooks, open `/hooks` inside Codex CLI on the remote and approve the Open Island hook entries if Codex asks for trust review.

## Manual setup

### 1. Deploy the hook script

```bash
scp scripts/open-island-hooks.py user@myserver:~/.local/bin/
ssh user@myserver chmod +x ~/.local/bin/open-island-hooks.py
```

### 2a. Configure Claude Code hooks on the remote

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

### 2b. Configure Codex CLI hooks on the remote

Edit `~/.codex/hooks.json` on the remote server:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [
          {
            "type": "command",
            "command": "OPEN_ISLAND_SOCKET_PATH=/tmp/open-island-1000.sock python3 ~/.local/bin/open-island-hooks.py --source codex",
            "timeout": 45
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "OPEN_ISLAND_SOCKET_PATH=/tmp/open-island-1000.sock python3 ~/.local/bin/open-island-hooks.py --source codex",
            "timeout": 45
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "OPEN_ISLAND_SOCKET_PATH=/tmp/open-island-1000.sock python3 ~/.local/bin/open-island-hooks.py --source codex",
            "timeout": 3600
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "OPEN_ISLAND_SOCKET_PATH=/tmp/open-island-1000.sock OPEN_ISLAND_NOTIFY_ONLY=1 OPEN_ISLAND_NOTIFY_TIMEOUT=2 python3 ~/.local/bin/open-island-hooks.py --source codex",
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "OPEN_ISLAND_SOCKET_PATH=/tmp/open-island-1000.sock OPEN_ISLAND_NOTIFY_ONLY=1 OPEN_ISLAND_NOTIFY_TIMEOUT=2 python3 ~/.local/bin/open-island-hooks.py --source codex",
            "timeout": 5
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "OPEN_ISLAND_SOCKET_PATH=/tmp/open-island-1000.sock python3 ~/.local/bin/open-island-hooks.py --source codex",
            "timeout": 45
          }
        ]
      }
    ]
  }
}
```

Replace `1000` with the remote user's UID (`ssh user@myserver id -u`) and make sure `[features].hooks = true` is present in `~/.codex/config.toml`:

```toml
[features]
hooks = true
```

Codex may require a manual trust review before running new hooks. Open `/hooks` inside Codex CLI and approve the Open Island entries.

### 3. Configure SSH socket forwarding

Add to your local `~/.ssh/config`:

```
Host myserver
    HostName myserver.example.com
    User youruser
    RemoteForward /tmp/open-island-1000.sock /tmp/open-island-501.sock
```

Replace `501` with your local UID (`id -u`) and `1000` with your remote UID (`ssh myserver id -u`).

Or connect directly with:

```bash
ssh -R /tmp/open-island-<remote-uid>.sock:/tmp/open-island-<local-uid>.sock user@myserver
```

### 4. Verify

1. Make sure Open Island is running on your Mac
2. SSH to the remote with socket forwarding enabled
3. Run Claude Code or Codex CLI on the remote — sessions should appear in the Open Island overlay

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

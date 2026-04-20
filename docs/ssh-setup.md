# SSH Remote Claude Code Setup

Connect Agent Deck to Claude Code running on a remote server over SSH.

## How it works

```
macOS (local)                         Remote server
┌──────────────┐    SSH tunnel     ┌────────────────────┐
│ Agent Deck  │◀═══════════════▶│ Unix socket (fwd)  │
│ BridgeServer │   RemoteForward   │        ▲           │
│ Unix socket  │                   │        │           │
└──────────────┘                   │  agent-deck-      │
                                   │  hooks.py          │
                                   │        ▲           │
                                   │        │           │
                                   │  Claude Code       │
                                   └────────────────────┘
```

SSH's `RemoteForward` tunnels the Unix socket from your Mac to the remote server. The Python hook client (`agent-deck-hooks.py`) connects to the forwarded socket, and the bridge protocol works identically to the local case.

## Prerequisites

- Agent Deck running on your Mac
- SSH access to the remote server
- Python 3.6+ on the remote server
- Claude Code installed on the remote server

## Quick setup

Run the automated setup script:

```bash
./scripts/remote-setup.sh user@myserver
```

This will:
1. Copy `agent-deck-hooks.py` to the remote server (`~/.local/bin/`)
2. Configure Claude Code hooks in `~/.claude/settings.json` on the remote
3. Print the SSH config snippet you need

## Manual setup

### 1. Deploy the hook script

```bash
scp scripts/agent-deck-hooks.py user@myserver:~/.local/bin/
ssh user@myserver chmod +x ~/.local/bin/agent-deck-hooks.py
```

### 2. Configure Claude Code hooks on the remote

Edit `~/.claude/settings.json` on the remote server:

```json
{
  "hooks": {
    "PreToolUse": [{ "type": "command", "command": "python3 ~/.local/bin/agent-deck-hooks.py --source claude" }],
    "PostToolUse": [{ "type": "command", "command": "python3 ~/.local/bin/agent-deck-hooks.py --source claude" }],
    "SessionStart": [{ "type": "command", "command": "python3 ~/.local/bin/agent-deck-hooks.py --source claude" }],
    "SessionEnd": [{ "type": "command", "command": "python3 ~/.local/bin/agent-deck-hooks.py --source claude" }],
    "PermissionRequest": [{ "type": "command", "command": "python3 ~/.local/bin/agent-deck-hooks.py --source claude" }],
    "Notification": [{ "type": "command", "command": "python3 ~/.local/bin/agent-deck-hooks.py --source claude" }],
    "Stop": [{ "type": "command", "command": "python3 ~/.local/bin/agent-deck-hooks.py --source claude" }],
    "UserPromptSubmit": [{ "type": "command", "command": "python3 ~/.local/bin/agent-deck-hooks.py --source claude" }],
    "SubagentStart": [{ "type": "command", "command": "python3 ~/.local/bin/agent-deck-hooks.py --source claude" }],
    "SubagentStop": [{ "type": "command", "command": "python3 ~/.local/bin/agent-deck-hooks.py --source claude" }]
  }
}
```

### 3. Configure SSH socket forwarding

Add to your local `~/.ssh/config`:

```
Host myserver
    HostName myserver.example.com
    User youruser
    RemoteForward /tmp/agent-deck-501.sock /tmp/agent-deck-501.sock
```

Replace `501` with your local UID (`id -u`).

Or connect directly with:

```bash
ssh -R /tmp/agent-deck-$(id -u).sock:/tmp/agent-deck-$(id -u).sock user@myserver
```

### 4. Verify

1. Make sure Agent Deck is running on your Mac
2. SSH to the remote with socket forwarding enabled
3. Run Claude Code on the remote — sessions should appear in the Agent Deck overlay

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
    RemoteForward /tmp/agent-deck-<remote-uid>.sock /tmp/agent-deck-<local-uid>.sock
```

Then set the socket path explicitly on the remote machine so the hook can find it:

```bash
# Add to ~/.zshrc on remote Mac
export AGENT_DECK_SOCKET_PATH=/tmp/agent-deck-<remote-uid>.sock
export AGENT_DECK_SOCKET_PATH=/tmp/agent-deck-<remote-uid>.sock
```

> **Note:** This was tested on a Mac-to-Mac configuration. The default documentation assumes matching UIDs (e.g. Docker environments where UID is typically `1000` on both ends).

## Troubleshooting

**Sessions not appearing?**

- Check the socket exists on remote: `ls -la /tmp/agent-deck-*.sock`
- Test connectivity: `python3 -c "import socket; s=socket.socket(socket.AF_UNIX); s.connect('/tmp/agent-deck-$(id -u).sock'); print('OK')"`
- Make sure Agent Deck is running locally before establishing the SSH connection

**"Address already in use" on SSH connect?**

The remote socket file from a previous session wasn't cleaned up:

```bash
ssh user@myserver rm /tmp/agent-deck-*.sock
```

Then reconnect.

**Permission denied on the socket?**

Ensure the remote UID in the socket filename matches your local UID. If they differ, set the socket path explicitly:

```bash
# In SSH config:
RemoteForward /tmp/agent-deck-remote.sock /tmp/agent-deck-501.sock

# On remote, set env var (add to ~/.bashrc):
export AGENT_DECK_SOCKET_PATH=/tmp/agent-deck-remote.sock
```

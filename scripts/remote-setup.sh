#!/usr/bin/env bash
#
# Open Island — remote SSH setup
#
# Deploys the Python hook client to a remote server and configures
# Claude Code and Codex to use it.  Also prints the SSH config snippet
# needed for Unix socket forwarding.
#
# Usage:
#   ./scripts/remote-setup.sh user@host
#
# Prerequisites:
#   - SSH access to the remote host
#   - Python 3.6+ on the remote host
#   - Claude Code and/or Codex installed on the remote host

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/open-island-hooks.py"
REMOTE_BIN_DIR=".local/bin"
REMOTE_HOOK_PATH="\$HOME/$REMOTE_BIN_DIR/open-island-hooks.py"

if [ $# -lt 1 ]; then
    echo "Usage: $0 user@host"
    exit 1
fi

REMOTE="$1"
LOCAL_UID=$(id -u)
SOCKET_NAME="open-island-${LOCAL_UID}.sock"

echo "==> Deploying open-island-hooks.py to $REMOTE ..."
ssh "$REMOTE" "mkdir -p ~/$REMOTE_BIN_DIR"
scp "$HOOK_SCRIPT" "$REMOTE:~/$REMOTE_BIN_DIR/open-island-hooks.py"
ssh "$REMOTE" "chmod +x ~/$REMOTE_BIN_DIR/open-island-hooks.py"

echo ""
echo "==> Configuring Claude Code hooks on $REMOTE ..."
# Build the hooks JSON fragment.
# Use the *local* UID in the socket path so the remote hook connects to the
# forwarded socket created by the local Open Island app.  The heredoc is
# unquoted so that $SOCKET_NAME is expanded.
HOOK_CMD="OPEN_ISLAND_SOCKET_PATH=/tmp/$SOCKET_NAME python3 ~/.local/bin/open-island-hooks.py --source claude"
HOOK_ENTRY="{\"matcher\": \"\", \"hooks\": [{\"type\": \"command\", \"command\": \"$HOOK_CMD\"}]}"
HOOKS_JSON=$(cat <<ENDJSON
{
  "hooks": {
    "PreToolUse": [$HOOK_ENTRY],
    "PostToolUse": [$HOOK_ENTRY],
    "Notification": [$HOOK_ENTRY],
    "SessionStart": [$HOOK_ENTRY],
    "SessionEnd": [$HOOK_ENTRY],
    "Stop": [$HOOK_ENTRY],
    "UserPromptSubmit": [$HOOK_ENTRY],
    "PermissionRequest": [$HOOK_ENTRY],
    "SubagentStart": [$HOOK_ENTRY],
    "SubagentStop": [$HOOK_ENTRY]
  }
}
ENDJSON
)

# Merge into existing settings.json on remote (or create new)
ssh "$REMOTE" "python3 -c \"
import json, os, sys

settings_path = os.path.expanduser('~/.claude/settings.json')
os.makedirs(os.path.dirname(settings_path), exist_ok=True)

existing = {}
if os.path.exists(settings_path):
    with open(settings_path) as f:
        existing = json.load(f)

new_hooks = json.loads(sys.stdin.read())

# Merge per-event instead of replacing the entire hooks dict, so
# user's custom hooks for other events are preserved.
if 'hooks' not in existing:
    existing['hooks'] = {}
for event, entries in new_hooks['hooks'].items():
    cur = existing['hooks'].get(event, [])
    # Avoid duplicating the same command
    existing_cmds = {e.get('command') for e in cur if isinstance(e, dict)}
    for entry in entries:
        if entry.get('command') not in existing_cmds:
            cur.append(entry)
    existing['hooks'][event] = cur

with open(settings_path, 'w') as f:
    json.dump(existing, f, indent=2)
    f.write('\n')

print('Updated ' + settings_path)
\"" <<< "$HOOKS_JSON"

echo ""
echo "==> Configuring Codex hooks on $REMOTE ..."
# Codex hooks.json uses the same forwarded socket; the remote hook client
# marks payloads as remote so the app keeps the session alive.
CODEX_HOOK_CMD="OPEN_ISLAND_SOCKET_PATH=/tmp/$SOCKET_NAME python3 ~/.local/bin/open-island-hooks.py --source codex"
CODEX_HOOKS_JSON=$(cat <<ENDJSON
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [{"type": "command", "command": "$CODEX_HOOK_CMD", "timeout": 45}]
      }
    ],
    "UserPromptSubmit": [
      {"hooks": [{"type": "command", "command": "$CODEX_HOOK_CMD", "timeout": 45}]}
    ],
    "PermissionRequest": [
      {"hooks": [{"type": "command", "command": "$CODEX_HOOK_CMD", "timeout": 3600}]}
    ],
    "Stop": [
      {"hooks": [{"type": "command", "command": "$CODEX_HOOK_CMD", "timeout": 45}]}
    ]
  }
}
ENDJSON
)

# Merge into existing hooks.json on remote (or create new), preserving
# user-authored hook groups for the same events.
ssh "$REMOTE" "python3 -c \"
import json, os, sys

hooks_path = os.path.expanduser('~/.codex/hooks.json')
os.makedirs(os.path.dirname(hooks_path), exist_ok=True)

existing = {}
if os.path.exists(hooks_path):
    with open(hooks_path) as f:
        existing = json.load(f)

new_hooks = json.loads(sys.stdin.read())

if 'hooks' not in existing:
    existing['hooks'] = {}

def existing_commands(event):
    commands = set()
    for group in existing['hooks'].get(event, []):
        for hook in group.get('hooks', []):
            if isinstance(hook, dict) and hook.get('command'):
                commands.add(hook['command'])
    return commands

for event, groups in new_hooks['hooks'].items():
    cur = existing['hooks'].get(event, [])
    known = existing_commands(event)
    for group in groups:
        commands = [h.get('command') for h in group.get('hooks', []) if isinstance(h, dict)]
        if commands and all(c in known for c in commands):
            continue
        cur.append(group)
        for c in commands:
            known.add(c)
    existing['hooks'][event] = cur

with open(hooks_path, 'w') as f:
    json.dump(existing, f, indent=2)
    f.write('\n')

print('Updated ' + hooks_path)
\"" <<< "$CODEX_HOOKS_JSON"

echo ""
echo "==> Done!"
echo ""
echo "Codex may require a manual trust review before running the hooks:"
echo "open \`/hooks\` inside Codex CLI and approve the Open Island entries."
echo ""
echo "IMPORTANT: Ensure the remote sshd has 'StreamLocalBindUnlink yes' in"
echo "/etc/ssh/sshd_config — otherwise reconnecting will fail with"
echo "'Address already in use' when the old socket file is still on disk."
echo ""
echo "Add the following to your ~/.ssh/config to enable socket forwarding:"
echo ""
echo "  Host ${REMOTE##*@}"
echo "      RemoteForward /tmp/$SOCKET_NAME /tmp/$SOCKET_NAME"
echo ""
echo "Or connect with:"
echo ""
echo "  ssh -R /tmp/$SOCKET_NAME:/tmp/$SOCKET_NAME $REMOTE"
echo ""

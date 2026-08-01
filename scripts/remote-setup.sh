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

if [ $# -lt 1 ]; then
    echo "Usage: $0 user@host"
    exit 1
fi

REMOTE="$1"
LOCAL_UID=$(id -u)
LOCAL_SOCKET_NAME="open-island-${LOCAL_UID}.sock"

# Deploy without forwarding: running the setup script must not steal the
# RemoteForward socket from an already-connected Open Island/Codex session.
SSH_NO_FORWARD=(-o RemoteForward=none)

# Resolve the remote UID so the forwarded socket name can be mapped when the
# two machines have different UIDs (e.g. macOS vs. Linux remote servers).
REMOTE_UID="$(ssh "${SSH_NO_FORWARD[@]}" "$REMOTE" "id -u" 2>/dev/null | tr -d '\r' | awk 'NR==1{print $1}')"
if ! [[ "$REMOTE_UID" =~ ^[0-9]+$ ]]; then
    echo "Failed to resolve numeric remote UID from '$REMOTE' (got: '$REMOTE_UID')." >&2
    exit 1
fi
REMOTE_SOCKET_NAME="open-island-${REMOTE_UID}.sock"

echo "==> Deploying open-island-hooks.py to $REMOTE ..."
ssh "${SSH_NO_FORWARD[@]}" "$REMOTE" "mkdir -p ~/$REMOTE_BIN_DIR"
scp "${SSH_NO_FORWARD[@]}" "$HOOK_SCRIPT" "$REMOTE:~/$REMOTE_BIN_DIR/open-island-hooks.py"
ssh "${SSH_NO_FORWARD[@]}" "$REMOTE" "chmod +x ~/$REMOTE_BIN_DIR/open-island-hooks.py"

echo ""
echo "==> Configuring Claude Code hooks on $REMOTE ..."
ssh "${SSH_NO_FORWARD[@]}" "$REMOTE" "OPEN_ISLAND_REMOTE_SOCKET=/tmp/$REMOTE_SOCKET_NAME python3 -" <<'PY'
import json
import os
from pathlib import Path

socket_path = os.environ["OPEN_ISLAND_REMOTE_SOCKET"]
hook_cmd = (
    f"OPEN_ISLAND_SOCKET_PATH={socket_path} "
    "python3 ~/.local/bin/open-island-hooks.py --source claude"
)

settings_path = Path.home() / ".claude" / "settings.json"
settings_path.parent.mkdir(parents=True, exist_ok=True)

existing = {}
if settings_path.exists():
    existing = json.loads(settings_path.read_text())

if "hooks" not in existing or not isinstance(existing["hooks"], dict):
    existing["hooks"] = {}


def group_has_open_island(group):
    nested = group.get("hooks")
    if not isinstance(nested, list):
        return False
    return any(
        isinstance(hook, dict)
        and "open-island-hooks.py" in (hook.get("command") or "")
        for hook in nested
    )


entry = {
    "matcher": "",
    "hooks": [{"type": "command", "command": hook_cmd}],
}
events = [
    "PreToolUse",
    "PostToolUse",
    "Notification",
    "SessionStart",
    "SessionEnd",
    "Stop",
    "UserPromptSubmit",
    "PermissionRequest",
    "SubagentStart",
    "SubagentStop",
]
for event in events:
    cur = existing["hooks"].get(event, [])
    if not isinstance(cur, list):
        cur = []
    # Remove any previously managed Open Island group (idempotent re-runs),
    # then append the current entry; user-authored hooks are preserved.
    cleaned = [g for g in cur if not (isinstance(g, dict) and group_has_open_island(g))]
    cleaned.append(entry)
    existing["hooks"][event] = cleaned

settings_path.write_text(json.dumps(existing, indent=2) + "\n")
print("Updated " + str(settings_path))
PY

echo ""
echo "==> Configuring Codex hooks on $REMOTE ..."
ssh "${SSH_NO_FORWARD[@]}" "$REMOTE" "OPEN_ISLAND_REMOTE_SOCKET=/tmp/$REMOTE_SOCKET_NAME python3 -" <<'PY'
import json
import os
from pathlib import Path

socket_path = os.environ["OPEN_ISLAND_REMOTE_SOCKET"]
hook_cmd = (
    f"OPEN_ISLAND_SOCKET_PATH={socket_path} "
    "python3 ~/.local/bin/open-island-hooks.py --source codex"
)

hooks_path = Path.home() / ".codex" / "hooks.json"
hooks_path.parent.mkdir(parents=True, exist_ok=True)

root = {}
if hooks_path.exists():
    root = json.loads(hooks_path.read_text())

hooks = root.get("hooks")
if not isinstance(hooks, dict):
    hooks = {}


def group_has_open_island(group):
    nested = group.get("hooks")
    if not isinstance(nested, list):
        return False
    return any(
        isinstance(hook, dict)
        and "open-island-hooks.py" in (hook.get("command") or "")
        for hook in nested
    )


event_specs = {
    "SessionStart": {"matcher": "startup|resume", "timeout": 45},
    "UserPromptSubmit": {"matcher": None, "timeout": 45},
    "PermissionRequest": {"matcher": None, "timeout": 3600},
    "PreToolUse": {"matcher": None, "timeout": 5, "notify": True},
    "PostToolUse": {"matcher": None, "timeout": 5, "notify": True},
    "Stop": {"matcher": None, "timeout": 45},
}
for event, spec in event_specs.items():
    cur = hooks.get(event, [])
    if not isinstance(cur, list):
        cur = []
    # Replace previously managed Open Island groups instead of duplicating
    # them on re-runs; user-authored hook groups are preserved.
    cleaned = [g for g in cur if not (isinstance(g, dict) and group_has_open_island(g))]
    if spec.get("notify"):
        hook_cmd = (
            f"OPEN_ISLAND_SOCKET_PATH={socket_path} "
            "OPEN_ISLAND_NOTIFY_ONLY=1 OPEN_ISLAND_NOTIFY_TIMEOUT=2 "
            "python3 ~/.local/bin/open-island-hooks.py --source codex"
        )
    else:
        hook_cmd = (
            f"OPEN_ISLAND_SOCKET_PATH={socket_path} "
            "python3 ~/.local/bin/open-island-hooks.py --source codex"
        )
    group = {
        "hooks": [{"type": "command", "command": hook_cmd, "timeout": spec["timeout"]}]
    }
    if spec["matcher"]:
        group["matcher"] = spec["matcher"]
    cleaned.append(group)
    hooks[event] = cleaned

root["hooks"] = hooks
hooks_path.write_text(json.dumps(root, indent=2) + "\n")
print("Updated " + str(hooks_path))
PY

echo ""
echo "==> Enabling Codex hooks feature flag on $REMOTE ..."
ssh "${SSH_NO_FORWARD[@]}" "$REMOTE" "python3 -" <<'PY'
from pathlib import Path

config_path = Path.home() / ".codex" / "config.toml"
config_path.parent.mkdir(parents=True, exist_ok=True)
text = config_path.read_text() if config_path.exists() else ""
lines = text.splitlines()
out = []
in_features = False
has_features = False
hooks_seen = False

for line in lines:
    stripped = line.strip()
    if stripped == "[features]":
        in_features = True
        has_features = True
        out.append(line)
        continue
    if in_features and stripped.startswith("[") and stripped.endswith("]"):
        if not hooks_seen:
            out.append("hooks = true")
        in_features = False
        out.append(line)
        continue
    if in_features:
        key = stripped.split("=", 1)[0].strip() if "=" in stripped else ""
        if key == "hooks":
            out.append("hooks = true")
            hooks_seen = True
            continue
    out.append(line)

if not has_features:
    if out and out[-1] != "":
        out.append("")
    out.append("[features]")
    out.append("hooks = true")
elif in_features and not hooks_seen:
    out.append("hooks = true")

config_path.write_text("\n".join(out) + "\n")
print("Updated " + str(config_path))
PY

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
echo "      RemoteForward /tmp/$REMOTE_SOCKET_NAME /tmp/$LOCAL_SOCKET_NAME"
echo ""
echo "Or connect with:"
echo ""
echo "  ssh -R /tmp/$REMOTE_SOCKET_NAME:/tmp/$LOCAL_SOCKET_NAME $REMOTE"
echo ""
if [ "$REMOTE_SOCKET_NAME" != "$LOCAL_SOCKET_NAME" ]; then
    echo "Note: local UID ($LOCAL_UID) differs from remote UID ($REMOTE_UID);"
    echo "the socket names above map the remote socket to your local Open Island socket."
    echo "If you previously configured forwarding with a non-mapped path, update it."
    echo ""
fi

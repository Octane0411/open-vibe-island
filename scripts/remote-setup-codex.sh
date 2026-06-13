#!/usr/bin/env bash
#
# Open Island — remote SSH setup for Codex CLI
#
# Deploys the portable Python hook client to a remote server and configures
# Codex CLI to use it. Also prints the SSH config snippet needed for Unix
# socket forwarding.
#
# Usage:
#   ./scripts/remote-setup-codex.sh user@host
#
# Prerequisites:
#   - SSH access to the remote host
#   - Python 3.6+ on the remote host
#   - Codex CLI installed on the remote host

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/open-island-hooks.py"
REMOTE_BIN_DIR=".local/bin"

if [ $# -lt 1 ]; then
    echo "Usage: $0 user@host"
    exit 1
fi

REMOTE="$1"
LOCAL_UID="$(id -u)"
REMOTE_UID="$(ssh "$REMOTE" "id -u" | tr -d '\r' | awk 'NR==1{print $1}')"
if ! [[ "$REMOTE_UID" =~ ^[0-9]+$ ]]; then
    echo "Failed to resolve numeric remote UID from '$REMOTE' (got: '$REMOTE_UID')." >&2
    exit 1
fi
LOCAL_SOCKET_NAME="open-island-${LOCAL_UID}.sock"
REMOTE_SOCKET_NAME="open-island-${REMOTE_UID}.sock"

echo "==> Deploying open-island-hooks.py to $REMOTE ..."
ssh "$REMOTE" "mkdir -p ~/$REMOTE_BIN_DIR"
scp "$HOOK_SCRIPT" "$REMOTE:~/$REMOTE_BIN_DIR/open-island-hooks.py"
ssh "$REMOTE" "chmod +x ~/$REMOTE_BIN_DIR/open-island-hooks.py"

echo ""
echo "==> Configuring Codex hooks on $REMOTE ..."
ssh "$REMOTE" "OPEN_ISLAND_REMOTE_SOCKET=/tmp/$REMOTE_SOCKET_NAME python3 -" <<'PY'
import json
import os
from pathlib import Path

socket_path = os.environ["OPEN_ISLAND_REMOTE_SOCKET"]
hook_cmd = (
    f"OPEN_ISLAND_SOCKET_PATH={socket_path} "
    "python3 ~/.local/bin/open-island-hooks.py --source codex"
)

event_specs = {
    "SessionStart": {"matcher": "startup|resume", "timeout": 45},
    "UserPromptSubmit": {"matcher": None, "timeout": 45},
    "PermissionRequest": {"matcher": None, "timeout": 3600},
    "Stop": {"matcher": None, "timeout": 45},
}

hooks_path = Path.home() / ".codex" / "hooks.json"
hooks_path.parent.mkdir(parents=True, exist_ok=True)

root = {}
if hooks_path.exists():
    with hooks_path.open() as f:
        root = json.load(f)

hooks = root.get("hooks")
if not isinstance(hooks, dict):
    hooks = {}


def group_for(spec):
    """Build one Codex hook matcher group for the managed Open Island command."""
    group = {
        "hooks": [{
            "type": "command",
            "command": hook_cmd,
            "timeout": spec["timeout"],
        }]
    }
    if spec["matcher"]:
        group["matcher"] = spec["matcher"]
    return group


def group_contains_command(group, command):
    """Return whether a Codex hook group already contains the given command."""
    nested = group.get("hooks")
    if not isinstance(nested, list):
        return False
    return any(isinstance(hook, dict) and hook.get("command") == command for hook in nested)


for event, spec in event_specs.items():
    existing_groups = hooks.get(event, [])
    if not isinstance(existing_groups, list):
        existing_groups = []

    cleaned_groups = [
        group
        for group in existing_groups
        if isinstance(group, dict) and not group_contains_command(group, hook_cmd)
    ]
    cleaned_groups.append(group_for(spec))
    hooks[event] = cleaned_groups

root["hooks"] = hooks
with hooks_path.open("w") as f:
    json.dump(root, f, indent=2)
    f.write("\n")

print(f"Updated {hooks_path}")
PY

echo ""
echo "==> Enabling Codex hooks feature flag on $REMOTE ..."
ssh "$REMOTE" "python3 -" <<'PY'
from pathlib import Path

config_path = Path.home() / ".codex" / "config.toml"
config_path.parent.mkdir(parents=True, exist_ok=True)
text = config_path.read_text() if config_path.exists() else ""
lines = text.splitlines()
out = []
in_features = False
has_features = False
has_hooks = False

for line in lines:
    stripped = line.strip()
    if stripped == "[features]":
        in_features = True
        has_features = True
        out.append(line)
        continue

    if in_features and stripped.startswith("[") and stripped.endswith("]"):
        if not has_hooks:
            out.append("hooks = true")
            has_hooks = True
        in_features = False
        out.append(line)
        continue

    if in_features and stripped.startswith("codex_hooks"):
        continue

    if in_features:
        key = stripped.split("=", 1)[0].strip() if "=" in stripped else ""
        if key == "hooks":
            out.append("hooks = true")
            has_hooks = True
            continue

    out.append(line)

if not has_features:
    if out and out[-1] != "":
        out.append("")
    out.extend(["[features]", "hooks = true"])
elif in_features and not has_hooks:
    out.append("hooks = true")

config_path.write_text("\n".join(out) + "\n")
print(f"Updated {config_path}")
PY

echo ""
echo "==> Done!"
echo ""
echo "IMPORTANT: Ensure the remote sshd has 'StreamLocalBindUnlink yes' in"
echo "/etc/ssh/sshd_config — otherwise reconnecting can fail with"
echo "'Address already in use' when the old socket file is still on disk."
echo ""
echo "Add the following to your local ~/.ssh/config to enable socket forwarding:"
echo ""
echo "  Host ${REMOTE##*@}"
echo "      RemoteForward /tmp/$REMOTE_SOCKET_NAME /tmp/$LOCAL_SOCKET_NAME"
echo ""
echo "Or connect directly with:"
echo ""
echo "  ssh -R /tmp/$REMOTE_SOCKET_NAME:/tmp/$LOCAL_SOCKET_NAME $REMOTE"
echo ""
echo "After connecting, run Codex on the remote. If Codex asks for hook trust,"
echo "open /hooks inside Codex CLI and approve the Open Island entries."

#!/usr/bin/env python3
"""
Agent Deck hook client — portable Python implementation.

Drop-in replacement for the Swift AgentDeckHooks binary.
Works on macOS and Linux with Python 3.6+ and zero third-party dependencies.
Designed for SSH remote scenarios where the Swift binary cannot run.

Usage (configured in Claude Code settings.json or Codex hooks.json):
    echo '{"hook_event_name":"SessionStart",...}' | python3 agent-deck-hooks.py --source claude
"""

import json
import os
import socket
import struct
import subprocess
import sys

# ---------------------------------------------------------------------------
# Socket path resolution
# ---------------------------------------------------------------------------

def socket_path():
    path = os.environ.get("AGENT_DECK_SOCKET_PATH") or \
           os.environ.get("AGENT_DECK_SOCKET_PATH")
    if path:
        return path
    return f"/tmp/agent-deck-{os.getuid()}.sock"

# ---------------------------------------------------------------------------
# Terminal inference (environment-only; no AppleScript on remote)
# ---------------------------------------------------------------------------

def infer_terminal_app(env):
    if env.get("ITERM_SESSION_ID") or env.get("LC_TERMINAL") == "iTerm2":
        return "iTerm"
    if env.get("CMUX_WORKSPACE_ID") or env.get("CMUX_SOCKET_PATH"):
        return "cmux"
    if env.get("GHOSTTY_RESOURCES_DIR"):
        return "Ghostty"
    tp = (env.get("TERM_PROGRAM") or "").lower()
    if tp == "apple_terminal":
        return "Terminal"
    if tp in ("iterm.app", "iterm2"):
        return "iTerm"
    if "ghostty" in tp:
        return "Ghostty"
    if tp == "kaku":
        return "Kaku"
    if tp == "wezterm":
        return "WezTerm"
    return None


def current_tty():
    # Try /proc (Linux) first — no subprocess needed.
    try:
        tty = os.ttyname(0)
        if tty:
            return tty
    except (OSError, AttributeError):
        pass

    # Fallback: call tty(1) via PATH (works on macOS and most Linux distros).
    import shutil
    tty_bin = shutil.which("tty")
    if tty_bin:
        try:
            result = subprocess.run(
                [tty_bin], capture_output=True, text=True, timeout=2,
            )
            tty = result.stdout.strip()
            if tty and "not a tty" not in tty:
                return tty
        except Exception:
            pass

    # Last resort: read parent process TTY via ps.
    ps_bin = shutil.which("ps") or "/bin/ps"
    try:
        ppid = os.getppid()
        result = subprocess.run(
            [ps_bin, "-p", str(ppid), "-o", "tty="],
            capture_output=True, text=True, timeout=2,
        )
        tty = result.stdout.strip()
        if tty and tty != "??":
            return f"/dev/{tty}" if not tty.startswith("/") else tty
    except Exception:
        pass

    return None

# ---------------------------------------------------------------------------
# Runtime context enrichment
# ---------------------------------------------------------------------------

def enrich_payload(payload, env):
    """Fill in terminal_app / terminal_tty / terminal_session_id from env."""
    if not payload.get("terminal_app"):
        app = infer_terminal_app(env)
        if app:
            payload["terminal_app"] = app

    # cmux: use CMUX_SURFACE_ID
    if payload.get("terminal_app") == "cmux" and not payload.get("terminal_session_id"):
        sid = env.get("CMUX_SURFACE_ID")
        if sid:
            payload["terminal_session_id"] = sid

    if not payload.get("terminal_tty"):
        tty = current_tty()
        if tty:
            payload["terminal_tty"] = tty

    # No AppleScript terminal locator — only available on macOS with the
    # native Swift binary.  Remote Python hook relies on env vars only.
    return payload

# ---------------------------------------------------------------------------
# Bridge socket communication
# ---------------------------------------------------------------------------

def send_command(envelope_json, timeout):
    """Connect to bridge socket, send JSON line, return parsed response."""
    path = socket_path()
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    try:
        sock.connect(path)
        sock.sendall(envelope_json.encode("utf-8") + b"\n")

        buf = b""
        while True:
            chunk = sock.recv(8192)
            if not chunk:
                return None
            buf += chunk
            # Look for a complete JSON line
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                if not line:
                    continue
                msg = json.loads(line)
                if msg.get("type") == "response":
                    return msg.get("response")
    finally:
        sock.close()

# ---------------------------------------------------------------------------
# stdout encoding — must match Swift ClaudeHookOutputEncoder / CodexHookOutputEncoder
# ---------------------------------------------------------------------------

def encode_claude_stdout(response):
    """Encode BridgeResponse into Claude Code hook stdout format."""
    if not response or response.get("type") != "claudeHookDirective":
        return None

    directive = response.get("directive", {})
    dtype = directive.get("type")
    inner = directive.get("directive", {})

    if dtype == "preToolUse":
        output = {
            "continue": True,
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": inner.get("permissionDecision"),
                "permissionDecisionReason": inner.get("permissionDecisionReason"),
                "updatedInput": inner.get("updatedInput"),
                "additionalContext": inner.get("additionalContext"),
            },
            "suppressOutput": True,
        }
        # Remove None values from hookSpecificOutput to match sortedKeys output
        output["hookSpecificOutput"] = {
            k: v for k, v in output["hookSpecificOutput"].items() if v is not None
        }
        return json.dumps(output, sort_keys=True) + "\n"

    if dtype == "permissionRequest":
        output = {
            "continue": True,
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": inner,
            },
            "suppressOutput": True,
        }
        return json.dumps(output, sort_keys=True) + "\n"

    return None


def encode_codex_stdout(response):
    """Encode BridgeResponse into Codex hook stdout format."""
    if not response or response.get("type") != "codexHookDirective":
        return None

    directive = response.get("directive", {})
    dtype = directive.get("type")

    if dtype == "deny":
        output = {"decision": "block", "reason": directive.get("reason", "")}
        return json.dumps(output, sort_keys=True) + "\n"

    return None


def encode_opencode_stdout(response):
    """Encode BridgeResponse into OpenCode hook stdout format."""
    if not response or response.get("type") != "openCodeHookDirective":
        return None

    directive = response.get("directive", {})
    dtype = directive.get("type")

    if dtype == "allow":
        return json.dumps({"type": "allow"}, sort_keys=True) + "\n"
    if dtype == "deny":
        output = {"type": "deny"}
        if directive.get("reason") is not None:
            output["reason"] = directive["reason"]
        return json.dumps(output, sort_keys=True) + "\n"
    if dtype == "answer":
        output = {"type": "answer", "text": directive.get("text", "")}
        return json.dumps(output, sort_keys=True) + "\n"

    return None

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def parse_source(args):
    i = 0
    while i < len(args):
        if args[i] == "--source" and i + 1 < len(args):
            return args[i + 1]
        i += 1
    return "codex"


def main():
    try:
        raw = sys.stdin.buffer.read()
        if not raw:
            return

        payload = json.loads(raw)
        source = parse_source(sys.argv[1:])
        env = os.environ

        # Enrich with runtime context
        payload = enrich_payload(payload, env)

        # Mark as remote so the UI can distinguish SSH sessions.
        payload["remote"] = True

        # Build bridge envelope
        if source == "claude":
            command = {"type": "processClaudeHook", "claudeHook": payload}
            timeout = 86400 if payload.get("hook_event_name") == "PermissionRequest" else 45
            encoder = encode_claude_stdout
        elif source == "opencode":
            command = {"type": "processOpenCodeHook", "openCodeHook": payload}
            timeout = 86400 if payload.get("hook_event_name") == "PermissionRequest" else 45
            encoder = encode_opencode_stdout
        else:
            command = {"type": "processCodexHook", "codexHook": payload}
            timeout = 45
            encoder = encode_codex_stdout

        envelope = json.dumps({"type": "command", "command": command})

        response = send_command(envelope, timeout)
        if response is None:
            return

        output = encoder(response)
        if output:
            sys.stdout.write(output)
            sys.stdout.flush()

    except Exception:
        # Hooks fail open — never block the agent.
        pass


if __name__ == "__main__":
    main()

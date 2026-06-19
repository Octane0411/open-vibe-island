#!/usr/bin/env python3
"""
Cursor AskQuestion → Open Island notch notifier.

When Cursor's AI agent calls AskQuestion, this script sends a notification
to Open Island's bridge socket so the notch pops up with the question title.
Clicking the notch jumps to Cursor. Skips notification when Cursor is already
the frontmost app (no distraction when you're already looking at it).

Usage (called by a Cursor Rule before every AskQuestion):
    python3 cursor-askquestion-notifier.py <session_id> <question_title>

Setup:
    1. Copy this script to ~/.cursor/scripts/
    2. Add the Cursor Rule from Scripts/cursor-askquestion-rule.mdc
       to ~/.cursor/rules/
"""

import json
import os
import socket
import subprocess
import sys
import uuid


def socket_path():
    path = os.environ.get("OPEN_ISLAND_SOCKET_PATH") or \
           os.environ.get("VIBE_ISLAND_SOCKET_PATH")
    if path:
        return path

    xdg = os.environ.get("XDG_RUNTIME_DIR")
    if xdg:
        candidate = os.path.join(xdg, "open-island.sock")
        if os.path.exists(candidate):
            return candidate

    home_candidate = os.path.expanduser(
        "~/Library/Application Support/OpenIsland/bridge.sock"
    )
    if os.path.exists(home_candidate):
        return home_candidate

    return "/tmp/open-island-%d.sock" % os.getuid()


def is_cursor_frontmost():
    """Return True if Cursor is the macOS frontmost application."""
    try:
        result = subprocess.run(
            [
                "osascript", "-e",
                'tell application "System Events" to get bundle identifier '
                'of first process whose frontmost is true',
            ],
            capture_output=True, text=True, timeout=2,
        )
        return result.stdout.strip() == "com.todesktop.230313mzl4w4u92"
    except Exception:
        return False


def send_question(session_id, title, sock_path):
    envelope = {
        "type": "command",
        "command": {
            "type": "requestQuestion",
            "sessionID": session_id,
            "prompt": {
                "id": str(uuid.uuid4()),
                "title": title,
                "options": [],
                "questions": [],
            },
        },
    }

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(3)
    try:
        sock.connect(sock_path)
        sock.sendall((json.dumps(envelope, ensure_ascii=False) + "\n").encode())
        resp = b""
        try:
            while True:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                resp += chunk
                if b"acknowledged" in resp:
                    break
        except socket.timeout:
            pass
        return True
    except Exception as e:
        print("error: %s" % e, file=sys.stderr)
        return False
    finally:
        sock.close()


def main():
    if len(sys.argv) < 3:
        print(
            "Usage: cursor-askquestion-notifier.py <session_id> <question_title>",
            file=sys.stderr,
        )
        sys.exit(1)

    session_id = sys.argv[1]
    title = " ".join(sys.argv[2:])

    if is_cursor_frontmost():
        return

    path = socket_path()
    if not os.path.exists(path):
        return

    send_question(session_id, title, path)


if __name__ == "__main__":
    main()

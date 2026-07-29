#!/usr/bin/env python3
"""
Setup helper for Open Island Antigravity CLI hooks on Windows / Cross-platform.

Usage:
    python scripts/setup-antigravity.py install
    python scripts/setup-antigravity.py status
    python scripts/setup-antigravity.py uninstall
"""

import json
import os
import sys
from pathlib import Path

def get_antigravity_dir() -> Path:
    home = Path.home()
    primary = home / ".antigravity"
    fallback = home / ".gemini"
    if primary.exists():
        return primary
    if fallback.exists():
        return fallback
    return primary

def get_hook_command() -> str:
    script_path = Path(__file__).parent.resolve() / "open-island-hooks.py"
    py_exec = sys.executable or "python"
    return f'"{py_exec}" "{script_path}" --source antigravity'

EVENTS = ["SessionStart", "SessionEnd", "BeforeAgent", "AfterAgent", "Notification"]

def status():
    ag_dir = get_antigravity_dir()
    settings_file = ag_dir / "settings.json"
    print(f"Antigravity dir: {ag_dir}")
    print(f"Settings file: {settings_file}")
    
    if not settings_file.exists():
        print("Managed hooks present: no (settings.json missing)")
        return False
        
    try:
        with open(settings_file, "r", encoding="utf-8") as f:
            data = json.load(f)
        hooks = data.get("hooks", {})
        cmd = get_hook_command()
        
        present = True
        for ev in EVENTS:
            groups = hooks.get(ev, [])
            found = False
            for group in groups:
                for hook in group.get("hooks", []):
                    c = hook.get("command", "")
                    if "open-island-hooks" in c or "antigravity" in c:
                        found = True
                        break
            if not found:
                present = False
                break
                
        print(f"Managed hooks present: {'yes' if present else 'no'}")
        return present
    except Exception as e:
        print(f"Error checking status: {e}")
        return False

def install():
    ag_dir = get_antigravity_dir()
    ag_dir.mkdir(parents=True, exist_ok=True)
    settings_file = ag_dir / "settings.json"
    
    data = {}
    if settings_file.exists():
        try:
            with open(settings_file, "r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            data = {}
            
    hooks = data.get("hooks", {})
    cmd = get_hook_command()
    
    for ev in EVENTS:
        groups = hooks.get(ev, [])
        # filter existing open-island hooks
        new_groups = []
        for g in groups:
            h_list = g.get("hooks", [])
            filtered_h = [h for h in h_list if "open-island" not in h.get("command", "") and "vibe-island" not in h.get("command", "")]
            if filtered_h:
                g["hooks"] = filtered_h
                new_groups.append(g)
        
        # add managed group
        new_groups.append({
            "matcher": "*",
            "hooks": [
                {
                    "type": "command",
                    "command": cmd,
                    "name": "Open Island"
                }
            ]
        })
        hooks[ev] = new_groups
        
    data["hooks"] = hooks
    
    with open(settings_file, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, sort_keys=True)
        
    print("Installed Open Island Antigravity hooks.")
    print(f"Target file: {settings_file}")
    print(f"Hook command: {cmd}")

def uninstall():
    ag_dir = get_antigravity_dir()
    settings_file = ag_dir / "settings.json"
    if not settings_file.exists():
        print("No settings.json found.")
        return
        
    try:
        with open(settings_file, "r", encoding="utf-8") as f:
            data = json.load(f)
        hooks = data.get("hooks", {})
        
        for ev in EVENTS:
            groups = hooks.get(ev, [])
            new_groups = []
            for g in groups:
                h_list = g.get("hooks", [])
                filtered_h = [h for h in h_list if "open-island" not in h.get("command", "") and "vibe-island" not in h.get("command", "")]
                if filtered_h:
                    g["hooks"] = filtered_h
                    new_groups.append(g)
            if new_groups:
                hooks[ev] = new_groups
            else:
                hooks.pop(ev, None)
                
        if hooks:
            data["hooks"] = hooks
        else:
            data.pop("hooks", None)
            
        with open(settings_file, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, sort_keys=True)
            
        print("Removed Open Island Antigravity hooks.")
    except Exception as e:
        print(f"Error during uninstall: {e}")

def main():
    args = sys.argv[1:]
    cmd = args[0] if args else "status"
    if cmd == "install":
        install()
    elif cmd == "uninstall":
        uninstall()
    else:
        status()

if __name__ == "__main__":
    main()

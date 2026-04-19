#!/bin/zsh
# clean-user-env.sh — Reset to a clean "new user" state for testing.
# Usage: zsh scripts/clean-user-env.sh [--dry-run]
#
# This removes all Open Island (and legacy Vibe Island) artifacts from the
# current user's environment, simulating a fresh install.

set -euo pipefail

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

red()    { printf '\033[31m%s\033[0m\n' "$1"; }
green()  { printf '\033[32m%s\033[0m\n' "$1"; }
yellow() { printf '\033[33m%s\033[0m\n' "$1"; }

clean_path() {
    local path="$1"
    if [[ -e "$path" || -L "$path" ]]; then
        if $DRY_RUN; then
            yellow "[dry-run] would remove: $path"
        else
            /bin/rm -rf "$path"
            green "removed: $path"
        fi
    fi
}

clean_glob() {
    local pattern="$1"
    for f in $~pattern(N); do
        clean_path "$f"
    done
}

echo "==> Quit Open Island if running"
if ! $DRY_RUN; then
    pkill -x OpenIslandApp 2>/dev/null || true
    sleep 0.5
fi

uid="$(id -u)"

echo ""
echo "==> Cleaning Open Island artifacts"

# --- Hook configurations ---
echo "--- Hook configs ---"

# Claude-style forks (.claude / .qoder / .qwen / .factory / .codebuddy / .gemini):
# each has a settings.json that may contain Open Island hook entries, plus
# sidecar manifests and backups. Strip OpenIsland references but preserve
# any user-owned hooks (including Vibe Island) so we don't trash setups
# the test isn't supposed to touch.
strip_claude_style() {
    local dir="$1"
    local settings="$dir/settings.json"
    if [[ -f "$settings" ]]; then
        if $DRY_RUN; then
            yellow "[dry-run] would strip OpenIsland hooks from: $settings"
        else
            python3 -c "
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
d = json.loads(p.read_text())
hooks = d.get('hooks', {})
changed = False
for event in list(hooks.keys()):
    original = hooks[event]
    if not isinstance(original, list): continue
    filtered = [h for h in original
                if not any('OpenIslandHooks' in (c.get('command',''))
                           for c in h.get('hooks',[]))]
    if len(filtered) != len(original):
        changed = True
        if filtered:
            hooks[event] = filtered
        else:
            del hooks[event]
sl = d.get('statusLine', {})
if 'open-island' in sl.get('command', '') or 'vibe-island' in sl.get('command', ''):
    del d['statusLine']
    changed = True
if changed:
    if not hooks and 'hooks' in d:
        del d['hooks']
    p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + '\n')
    print('stripped OpenIsland hooks/statusLine from', sys.argv[1])
" "$settings" 2>/dev/null && green "cleaned hooks in $settings" || true
        fi
    fi
    clean_path "$dir/open-island-claude-hooks-install.json"
    clean_path "$dir/vibe-island-claude-hooks-install.json"
    clean_glob "$dir/settings.json.backup.*"
}

for d in ~/.claude ~/.qoder ~/.qwen ~/.factory ~/.codebuddy ~/.gemini; do
    strip_claude_style "$d"
done

# Codex: remove Open Island entries from hooks.json
codex_hooks=~/.codex/hooks.json
if [[ -f "$codex_hooks" ]]; then
    if $DRY_RUN; then
        yellow "[dry-run] would strip OpenIsland hooks from: $codex_hooks"
    else
        python3 -c "
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
d = json.loads(p.read_text())
# Codex hooks.json nests events under a 'hooks' key
hooks = d.get('hooks', d)
changed = False
for event in list(hooks.keys()):
    original = hooks[event]
    if not isinstance(original, list): continue
    filtered = [h for h in original
                if not any('OpenIslandHooks' in c.get('command','')
                           for c in h.get('hooks',[]))]
    if len(filtered) != len(original):
        changed = True
        if filtered:
            hooks[event] = filtered
        else:
            del hooks[event]
if changed:
    p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + '\n')
    print('stripped OpenIsland hooks from', sys.argv[1])
" "$codex_hooks" 2>/dev/null && green "cleaned hooks in $codex_hooks" || true
    fi
fi
clean_path ~/.codex/open-island-codex-hooks-install.json
clean_path ~/.codex/open-island-install.json
clean_glob ~/.codex/'config.toml.backup.*'
clean_glob ~/.codex/'hooks.json.backup.*'

# Cursor: hooks.json uses a flat `[{command: "..."}]` shape (NOT the
# nested `[{hooks:[{command:...}]}]` shape Claude/Codex use). Match the
# command field directly.
cursor_hooks=~/.cursor/hooks.json
if [[ -f "$cursor_hooks" ]]; then
    if $DRY_RUN; then
        yellow "[dry-run] would strip OpenIsland hooks from: $cursor_hooks"
    else
        python3 -c "
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
d = json.loads(p.read_text())
hooks = d.get('hooks', {})
changed = False
for event in list(hooks.keys()):
    original = hooks[event]
    if not isinstance(original, list): continue
    filtered = [h for h in original
                if 'OpenIslandHooks' not in h.get('command','')]
    if len(filtered) != len(original):
        changed = True
        if filtered:
            hooks[event] = filtered
        else:
            del hooks[event]
if changed:
    if not hooks and 'hooks' in d:
        del d['hooks']
    p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + '\n')
    print('stripped OpenIsland hooks from', sys.argv[1])
" "$cursor_hooks" 2>/dev/null && green "cleaned hooks in $cursor_hooks" || true
    fi
fi
clean_path ~/.cursor/open-island-cursor-hooks-install.json
clean_glob ~/.cursor/'hooks.json.backup.*'

# OpenCode: bundled plugin file is `open-island.js` (not the install
# manifest name). Strip the matching plugin reference from config.json
# too so OpenCode doesn't keep trying to load a missing file.
clean_path ~/.config/opencode/plugins/open-island.js
clean_path ~/.config/opencode/open-island-opencode-plugin-install.json
opencode_config=~/.config/opencode/config.json
if [[ -f "$opencode_config" ]]; then
    if $DRY_RUN; then
        yellow "[dry-run] would strip open-island plugin from: $opencode_config"
    else
        python3 -c "
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
d = json.loads(p.read_text())
plugins = d.get('plugin', [])
filtered = [x for x in plugins if 'open-island' not in x]
if len(filtered) != len(plugins):
    if filtered:
        d['plugin'] = filtered
    else:
        d.pop('plugin', None)
    p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + '\n')
    print('stripped open-island plugin from', sys.argv[1])
" "$opencode_config" 2>/dev/null && green "cleaned plugins in $opencode_config" || true
    fi
fi

# --- Installed hooks binary ---
echo "--- Hooks binary ---"
clean_path ~/Library/Application\ Support/OpenIsland
clean_path ~/Library/Application\ Support/VibeIsland

# --- Status line scripts ---
echo "--- Status line ---"
clean_path ~/.open-island
clean_path ~/.vibe-island

# --- Session registry & app data ---
echo "--- App data ---"
clean_path ~/Library/Application\ Support/open-island

# --- Temp / socket files ---
echo "--- Temp files ---"
clean_path "/tmp/open-island-${uid}.sock"
clean_path /tmp/open-island-rl.json
clean_path /tmp/vibe-island-rl.json

# --- Installed app ---
echo "--- App bundle ---"
clean_path /Applications/Open\ Island.app
clean_path ~/Applications/Open\ Island.app
clean_path ~/Applications/Open\ Island\ Dev.app

# --- UserDefaults ---
echo "--- UserDefaults ---"
# Find the bundle ID used by the app
for bid in app.openisland.dev app.vibeisland.dev; do
    plist=~/Library/Preferences/${bid}.plist
    if [[ -e "$plist" ]]; then
        if $DRY_RUN; then
            yellow "[dry-run] would remove defaults for: $bid"
        else
            defaults delete "$bid" 2>/dev/null || true
            green "removed defaults: $bid"
        fi
    fi
done

echo ""
if $DRY_RUN; then
    yellow "Dry run complete. Re-run without --dry-run to actually clean."
else
    green "Done! Environment is clean."
    echo ""
    echo "Next steps:"
    echo "  1. Install Open Island.dmg from the latest release"
    echo "  2. Launch the app — you are now a fresh user"
fi

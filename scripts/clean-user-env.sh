#!/bin/zsh
# clean-user-env.sh — Reset to a clean "new user" state for testing.
# Usage: zsh scripts/clean-user-env.sh [--dry-run]
#
# This removes all Agent Deck (and legacy Agent Deck) artifacts from the
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

echo "==> Quit Agent Deck if running"
if ! $DRY_RUN; then
    pkill -x AgentDeckApp 2>/dev/null || true
    sleep 0.5
fi

uid="$(id -u)"

echo ""
echo "==> Cleaning Agent Deck artifacts"

# --- Hook configurations ---
echo "--- Hook configs ---"

# Claude-style forks (.claude / .qoder / .qwen / .factory / .codebuddy / .gemini):
# each has a settings.json that may contain Agent Deck hook entries, plus
# sidecar manifests and backups. Strip AgentDeck references but preserve
# any user-owned hooks (including Agent Deck) so we don't trash setups
# the test isn't supposed to touch.
strip_claude_style() {
    local dir="$1"
    local settings="$dir/settings.json"
    if [[ -f "$settings" ]]; then
        if $DRY_RUN; then
            yellow "[dry-run] would strip AgentDeck hooks from: $settings"
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
                if not any('AgentDeckHooks' in (c.get('command',''))
                           for c in h.get('hooks',[]))]
    if len(filtered) != len(original):
        changed = True
        if filtered:
            hooks[event] = filtered
        else:
            del hooks[event]
sl = d.get('statusLine', {})
if 'agent-deck' in sl.get('command', '') or 'agent-deck' in sl.get('command', ''):
    del d['statusLine']
    changed = True
if changed:
    if not hooks and 'hooks' in d:
        del d['hooks']
    p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + '\n')
    print('stripped AgentDeck hooks/statusLine from', sys.argv[1])
" "$settings" 2>/dev/null && green "cleaned hooks in $settings" || true
        fi
    fi
    clean_path "$dir/agent-deck-claude-hooks-install.json"
    clean_path "$dir/agent-deck-claude-hooks-install.json"
    clean_glob "$dir/settings.json.backup.*"
}

for d in ~/.claude ~/.qoder ~/.qwen ~/.factory ~/.codebuddy ~/.gemini; do
    strip_claude_style "$d"
done

# Codex: remove Agent Deck entries from hooks.json
codex_hooks=~/.codex/hooks.json
if [[ -f "$codex_hooks" ]]; then
    if $DRY_RUN; then
        yellow "[dry-run] would strip AgentDeck hooks from: $codex_hooks"
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
                if not any('AgentDeckHooks' in c.get('command','')
                           for c in h.get('hooks',[]))]
    if len(filtered) != len(original):
        changed = True
        if filtered:
            hooks[event] = filtered
        else:
            del hooks[event]
if changed:
    p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + '\n')
    print('stripped AgentDeck hooks from', sys.argv[1])
" "$codex_hooks" 2>/dev/null && green "cleaned hooks in $codex_hooks" || true
    fi
fi
clean_path ~/.codex/agent-deck-codex-hooks-install.json
clean_path ~/.codex/agent-deck-install.json
clean_glob ~/.codex/'config.toml.backup.*'
clean_glob ~/.codex/'hooks.json.backup.*'

# Cursor: hooks.json uses a flat `[{command: "..."}]` shape (NOT the
# nested `[{hooks:[{command:...}]}]` shape Claude/Codex use). Match the
# command field directly.
cursor_hooks=~/.cursor/hooks.json
if [[ -f "$cursor_hooks" ]]; then
    if $DRY_RUN; then
        yellow "[dry-run] would strip AgentDeck hooks from: $cursor_hooks"
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
                if 'AgentDeckHooks' not in h.get('command','')]
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
    print('stripped AgentDeck hooks from', sys.argv[1])
" "$cursor_hooks" 2>/dev/null && green "cleaned hooks in $cursor_hooks" || true
    fi
fi
clean_path ~/.cursor/agent-deck-cursor-hooks-install.json
clean_glob ~/.cursor/'hooks.json.backup.*'

# OpenCode: bundled plugin file is `agent-deck.js` (not the install
# manifest name). Strip the matching plugin reference from config.json
# too so OpenCode doesn't keep trying to load a missing file.
clean_path ~/.config/opencode/plugins/agent-deck.js
clean_path ~/.config/opencode/agent-deck-opencode-plugin-install.json
opencode_config=~/.config/opencode/config.json
if [[ -f "$opencode_config" ]]; then
    if $DRY_RUN; then
        yellow "[dry-run] would strip agent-deck plugin from: $opencode_config"
    else
        python3 -c "
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
d = json.loads(p.read_text())
plugins = d.get('plugin', [])
filtered = [x for x in plugins if 'agent-deck' not in x]
if len(filtered) != len(plugins):
    if filtered:
        d['plugin'] = filtered
    else:
        d.pop('plugin', None)
    p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + '\n')
    print('stripped agent-deck plugin from', sys.argv[1])
" "$opencode_config" 2>/dev/null && green "cleaned plugins in $opencode_config" || true
    fi
fi

# --- Installed hooks binary ---
echo "--- Hooks binary ---"
clean_path ~/Library/Application\ Support/AgentDeck
clean_path ~/Library/Application\ Support/AgentDeck

# --- Status line scripts ---
echo "--- Status line ---"
clean_path ~/.agent-deck
clean_path ~/.agent-deck

# --- Session registry & app data ---
echo "--- App data ---"
clean_path ~/Library/Application\ Support/agent-deck

# --- Temp / socket files ---
echo "--- Temp files ---"
clean_path "/tmp/agent-deck-${uid}.sock"
clean_path /tmp/agent-deck-rl.json
clean_path /tmp/agent-deck-rl.json

# --- Installed app ---
echo "--- App bundle ---"
clean_path /Applications/Open\ Island.app
clean_path ~/Applications/Open\ Island.app
clean_path ~/Applications/Open\ Island\ Dev.app

# --- UserDefaults ---
echo "--- UserDefaults ---"
# Find the bundle ID used by the app
for bid in app.agentdeck.dev app.agentdeck.dev; do
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
    echo "  1. Install Agent Deck.dmg from the latest release"
    echo "  2. Launch the app — you are now a fresh user"
fi

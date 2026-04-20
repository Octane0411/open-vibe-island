#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

cd "$repo_root"

export AGENT_DECK_RUN_GHOSTTY_JUMP_INTEGRATION=1
swift test --filter TerminalJumpServiceTests

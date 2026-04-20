#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

timestamp="$(date +%Y%m%d-%H%M%S)"
base_dir="${AGENT_DECK_HARNESS_ARTIFACT_DIR:-$repo_root/output/harness/smoke-all-$timestamp}"
scenarios=(closed sessionList approvalCard questionCard completionCard longCompletionCard)

mkdir -p "$base_dir"

for scenario in "${scenarios[@]}"; do
    scenario_dir="$base_dir/$scenario"
    echo "Running smoke scenario '$scenario'"
    AGENT_DECK_HARNESS_SCENARIO="$scenario" \
    AGENT_DECK_HARNESS_ARTIFACT_DIR="$scenario_dir" \
    zsh "$repo_root/scripts/smoke-dev-app.sh"
done

echo "All smoke scenarios passed"
echo "Artifacts written to $base_dir"

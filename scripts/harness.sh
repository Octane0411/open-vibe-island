#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

if (( $# == 0 )); then
    steps=(docs test build)
else
    steps=("$@")
fi

run_step() {
    local step="$1"

    case "$step" in
        docs)
            echo "==> docs"
            zsh "$repo_root/scripts/check-docs.sh"
            ;;
        test)
            echo "==> test"
            zsh "$repo_root/scripts/test-clt.sh"
            ;;
        lint)
            echo "==> lint"
            zsh "$repo_root/scripts/lint-strings.sh"
            ;;
        build)
            echo "==> build"
            swift build --disable-automatic-resolution
            ;;
        smoke)
            echo "==> smoke"
            zsh "$repo_root/scripts/smoke-dev-app.sh"
            ;;
        smoke-all)
            echo "==> smoke-all"
            zsh "$repo_root/scripts/smoke-all-scenarios.sh"
            ;;
        ci)
            run_step lint
            run_step docs
            run_step test
            run_step build
            ;;
        all)
            run_step docs
            run_step test
            run_step build
            run_step smoke-all
            ;;
        *)
            echo "usage: scripts/harness.sh [docs|test|build|smoke|smoke-all|ci|all] ..." >&2
            exit 64
            ;;
    esac
}

for step in "${steps[@]}"; do
    run_step "$step"
done

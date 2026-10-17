#!/bin/zsh

# Runs the test suite with Swift Testing on Command Line Tools-only setups,
# where plain `swift test` fails with "no such module 'Testing'". Full Xcode
# toolchains provide Testing natively, so they use plain `swift test`.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
developer_dir="$(xcode-select -p 2>/dev/null || true)"
testing_frameworks="$developer_dir/Library/Developer/Frameworks"

cd "$repo_root"

if [[ -z "$developer_dir" || ! -d "$testing_frameworks/Testing.framework" ]]; then
    # Xcode toolchains bundle Swift Testing into the toolchain itself.
    exec swift test --disable-automatic-resolution "$@"
fi

swift test --disable-automatic-resolution \
    --enable-swift-testing \
    -Xswiftc -F \
    -Xswiftc "$testing_frameworks" \
    -Xlinker "-F$testing_frameworks" \
    -Xlinker -rpath \
    -Xlinker "$testing_frameworks" \
    -Xlinker -rpath \
    -Xlinker "$developer_dir/Library/Developer/usr/lib" \
    "$@"

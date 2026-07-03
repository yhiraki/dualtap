#!/bin/bash
# Build the dualtap binary, stamping the version from the current git tag.
# usage: ./build.sh   → .build/release/dualtap
set -euo pipefail
cd "$(dirname "$0")"

VERSION_FILE="Sources/dualtap/Version.swift"
V=$(git describe --tags --always --dirty 2>/dev/null | sed 's/^v//' || echo dev)
trap 'git checkout -- "$VERSION_FILE" 2>/dev/null || true' EXIT
printf '// Version.swift — release version. build.sh and CI stamp this from the git tag at build time.\nlet version = "%s"\n' "$V" > "$VERSION_FILE"

swift build -c release
echo "built: $(pwd)/.build/release/dualtap  (version $V)"

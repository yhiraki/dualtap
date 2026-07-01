#!/bin/bash
# Build the dualtap binary.
# usage: ./build.sh   → .build/release/dualtap
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
echo "built: $(pwd)/.build/release/dualtap"

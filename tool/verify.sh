#!/usr/bin/env sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
dart_bin=${DART_BIN:-dart}

cd "$repo_root"

export DASH__SUPPRESS_ANALYTICS=true

"$dart_bin" format --output=none --set-exit-if-changed bin lib test
"$dart_bin" analyze
"$dart_bin" test

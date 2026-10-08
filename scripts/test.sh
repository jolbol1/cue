#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/cue-clang-cache"
swift run --disable-sandbox -Xswiftc -module-cache-path -Xswiftc "${TMPDIR:-/tmp}/cue-swift-cache" CueChecks

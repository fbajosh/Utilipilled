#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
swift run --disable-sandbox --scratch-path .build --cache-path .build/cache --config-path .build/config --security-path .build/security CameraQuietTests

swiftc -module-cache-path .build/module-cache Sources/Utilipilled/Modules/KeepAwake/KeepAwake.swift Support/check_keep_awake.swift -framework IOKit -o .build/KeepAwakeChecks
.build/KeepAwakeChecks

swiftc -module-cache-path .build/module-cache Sources/Utilipilled/Modules/PercentageHider/PercentageHider.swift Support/check_percentage_hider.swift -framework IOKit -o .build/PercentageHiderChecks
.build/PercentageHiderChecks

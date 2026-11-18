#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
swift run --disable-sandbox --scratch-path .build --cache-path .build/cache --config-path .build/config --security-path .build/security CameraQuietTests

swiftc -module-cache-path .build/module-cache Sources/Utilipilled/Pills/KeepAwake/KeepAwake.swift Support/check_keep_awake.swift -framework IOKit -o .build/KeepAwakeChecks
.build/KeepAwakeChecks

swiftc -module-cache-path .build/module-cache Sources/Utilipilled/Pills/PercentageHider/PercentageHider.swift Support/check_percentage_hider.swift -framework IOKit -o .build/PercentageHiderChecks
.build/PercentageHiderChecks

swiftc -module-cache-path .build/module-cache Sources/Utilipilled/Pills/ClaudeTarget/ClaudeTarget.swift Support/check_claude_target.swift -o .build/ClaudeTargetChecks
.build/ClaudeTargetChecks

swiftc -module-cache-path .build/module-cache Sources/Utilipilled/Pills/SwitcherHider/SwitcherLayout.swift Sources/Utilipilled/Pills/SwitcherHider/ApplicationHistory.swift Sources/Utilipilled/Pills/SwitcherHider/ExclusionStore.swift Sources/Utilipilled/Pills/SwitcherHider/KeyboardInterceptor.swift Support/check_switcher_hider.swift -framework AppKit -framework ApplicationServices -o .build/SwitcherHiderChecks
.build/SwitcherHiderChecks

python3 Support/test_switcher_measurements.py

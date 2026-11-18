#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .build/module-cache
swiftc -module-cache-path .build/module-cache Sources/Utilipilled/Pills/SwitcherHider/*.swift \
  Support/check_switcher_integration.swift -framework AppKit -framework ApplicationServices -o .build/SwitcherIntegrationChecks
.build/SwitcherIntegrationChecks

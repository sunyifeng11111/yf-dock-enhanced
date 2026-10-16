#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
swift build --build-system native --product DockEnhanced
binary_dir="$(swift build --build-system native --show-bin-path)"
source "$project_dir/scripts/lib/switcher-fixtures.sh"
build_switcher_fixtures "$project_dir" "$binary_dir"
check_mode=--check-command-tab
if [[ "${1:-}" == --review ]]; then check_mode=--check-switcher-review; shift; fi
if [[ "${1:-}" == --recovery ]]; then check_mode=--check-switcher-recovery; shift; fi
if [[ "${1:-}" == --visual ]]; then check_mode=--check-switcher-visual; shift; fi
"$binary_dir/DockEnhanced" "$check_mode" "$project_dir/.build/Switcher Fixture A.app" "$project_dir/.build/Switcher Fixture B.app" "$@"

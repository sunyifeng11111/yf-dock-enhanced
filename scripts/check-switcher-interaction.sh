#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
swift build --build-system native --product DockEnhanced
binary_dir="$(swift build --build-system native --show-bin-path)"
source "$project_dir/scripts/lib/switcher-fixtures.sh"
build_switcher_fixtures "$project_dir" "$binary_dir"
"$binary_dir/DockEnhanced" --check-switcher-interaction "$project_dir/.build/Switcher Fixture A.app" "$project_dir/.build/Switcher Fixture B.app" "$@"

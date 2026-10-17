#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
swift build --build-system native --product DockEnhanced
binary_dir="$(swift build --build-system native --show-bin-path)"
source "$project_dir/scripts/lib/switcher-fixtures.sh"
check_mode=--check-command-tab
if [[ "${1:-}" == --thumbnails ]]; then check_mode=--check-thumbnail-recovery; shift; fi
if [[ "${1:-}" == --review ]]; then check_mode=--check-switcher-review; shift; fi
if [[ "${1:-}" == --recovery ]]; then check_mode=--check-switcher-recovery; shift; fi
if [[ "${1:-}" == --visual ]]; then check_mode=--check-switcher-visual; shift; fi
fixture_names=(A B)
if [[ "$check_mode" == --check-thumbnail-recovery ]]; then fixture_names+=(C); fi
build_switcher_fixtures "$project_dir" "$binary_dir" "${fixture_names[@]}"
fixture_paths=()
for name in "${fixture_names[@]}"; do fixture_paths+=("$project_dir/.build/Switcher Fixture $name.app"); done
"$binary_dir/DockEnhanced" "$check_mode" "${fixture_paths[@]}" "$@"

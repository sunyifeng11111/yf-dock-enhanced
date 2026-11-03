#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
swift build --build-system native --product DockEnhanced
binary_dir="$(swift build --build-system native --show-bin-path)"
fixture_dir="$project_dir/.build/Dock Enhanced Test.app"
source "$project_dir/scripts/lib/native-fixtures.sh"
build_native_fixture "$binary_dir" "$fixture_dir" dev.yifeng.DockEnhancedFixture "Dock Enhanced Test"
source_fixture_dir="$project_dir/.build/Dock Enhanced Source.app"
build_native_fixture "$binary_dir" "$source_fixture_dir" dev.yifeng.DockEnhancedSourceFixture "Dock Enhanced Source"
if [[ "${1:-}" == --fixtures-only ]]; then
    "$fixture_dir/Contents/MacOS/DockEnhanced" --diagnose
    "$source_fixture_dir/Contents/MacOS/DockEnhanced" --diagnose
    exit 0
fi
"$binary_dir/DockEnhanced" --integration-check "$fixture_dir" "$source_fixture_dir"

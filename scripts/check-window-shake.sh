#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
swift build --build-system native --product DockEnhanced
binary_dir="$(swift build --build-system native --show-bin-path)"
source "$project_dir/scripts/lib/native-fixtures.sh"
fixture_dir="$project_dir/.build/Dock Enhanced Shake Test.app"
hidden_dir="$project_dir/.build/Dock Enhanced Shake Hidden.app"
build_native_fixture "$binary_dir" "$fixture_dir" dev.yifeng.DockEnhancedShakeFixture "Dock Enhanced Shake Test"
build_native_fixture "$binary_dir" "$hidden_dir" dev.yifeng.DockEnhancedShakeHiddenFixture "Dock Enhanced Shake Hidden"
"$binary_dir/DockEnhanced" --check-window-shake "$fixture_dir" "$hidden_dir"

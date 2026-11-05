#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
swift build --build-system native --product DockEnhanced
binary_dir="$(swift build --build-system native --show-bin-path)"
source "$project_dir/scripts/lib/native-fixtures.sh"
fixture_dir="$project_dir/.build/Dock Enhanced Self Shake Fixture.app"
build_native_fixture "$binary_dir" "$fixture_dir" dev.yifeng.DockEnhancedSelfShakeFixture "Dock Enhanced Self Shake Fixture"
"$fixture_dir/Contents/MacOS/DockEnhanced" --shake-fixture &
fixture_pid=$!
cleanup() { kill -CONT "$fixture_pid" 2>/dev/null || true; kill -TERM "$fixture_pid" 2>/dev/null || true; }
trap cleanup EXIT
"$binary_dir/DockEnhanced" --check-self-window-shake "$fixture_pid"

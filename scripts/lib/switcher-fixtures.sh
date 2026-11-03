#!/bin/zsh
# Shared disposable fixture packaging for the native switcher checks.
build_switcher_fixtures() {
    local project_dir="$1"
    local binary_dir="$2"
    source "$project_dir/scripts/lib/native-fixtures.sh"
    local name fixture_dir
    local -a fixture_names
    fixture_names=(A B)
    if [[ $# -gt 2 ]]; then fixture_names=("${@:3}"); fi
    for name in "${fixture_names[@]}"; do
        fixture_dir="$project_dir/.build/Switcher Fixture $name.app"
        build_native_fixture "$binary_dir" "$fixture_dir" "dev.yifeng.DockEnhancedSwitcherFixture$name" "Switcher Fixture $name"
    done
}

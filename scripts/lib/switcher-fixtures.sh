#!/bin/zsh
# Shared disposable fixture packaging for the native switcher checks.
build_switcher_fixtures() {
    local project_dir="$1"
    local binary_dir="$2"
    local name fixture_dir
    local -a fixture_names
    fixture_names=(A B)
    if [[ $# -gt 2 ]]; then fixture_names=("${@:3}"); fi
    for name in "${fixture_names[@]}"; do
        fixture_dir="$project_dir/.build/Switcher Fixture $name.app"
        mkdir -p "$fixture_dir/Contents/MacOS"
        cp "$binary_dir/DockEnhanced" "$fixture_dir/Contents/MacOS/DockEnhanced"
        mkdir -p "$fixture_dir/Contents/Frameworks"
        if [[ -d "$fixture_dir/Contents/Frameworks/Sparkle.framework" ]]; then
            rm -rf "$fixture_dir/Contents/Frameworks/Sparkle.framework"
        fi
        ditto "$binary_dir/Sparkle.framework" "$fixture_dir/Contents/Frameworks/Sparkle.framework"
        python3 - "$fixture_dir/Contents/Info.plist" "$name" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({
        'CFBundleExecutable': 'DockEnhanced',
        'CFBundleIdentifier': 'dev.yifeng.DockEnhancedSwitcherFixture' + sys.argv[2],
        'CFBundleName': 'Switcher Fixture ' + sys.argv[2],
        'CFBundlePackageType': 'APPL',
        'LSMinimumSystemVersion': '14.0',
        'NSHighResolutionCapable': True
    }, f)
PY
        codesign --force --sign - --identifier "dev.yifeng.DockEnhancedSwitcherFixture$name" "$fixture_dir"
    done
}

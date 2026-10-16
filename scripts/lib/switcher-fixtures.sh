#!/bin/zsh
# Shared disposable fixture packaging for the native switcher checks.
build_switcher_fixtures() {
    local project_dir="$1"
    local binary_dir="$2"
    local name fixture_dir
    for name in A B; do
        fixture_dir="$project_dir/.build/Switcher Fixture $name.app"
        mkdir -p "$fixture_dir/Contents/MacOS"
        cp "$binary_dir/DockEnhanced" "$fixture_dir/Contents/MacOS/DockEnhanced"
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

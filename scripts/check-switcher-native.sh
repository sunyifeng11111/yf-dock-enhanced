#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
swift build --build-system native --product DockEnhanced
binary_dir="$(swift build --build-system native --show-bin-path)"
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
"$binary_dir/DockEnhanced" --check-command-tab "$project_dir/.build/Switcher Fixture A.app" "$project_dir/.build/Switcher Fixture B.app" "$@"

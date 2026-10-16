#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
swift build --build-system native --product DockEnhanced
binary_dir="$(swift build --build-system native --show-bin-path)"
fixture_dir="$project_dir/.build/Dock Enhanced Test.app"
mkdir -p "$fixture_dir/Contents/MacOS"
cp "$binary_dir/DockEnhanced" "$fixture_dir/Contents/MacOS/DockEnhanced"
python3 - "$fixture_dir/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({
        'CFBundleExecutable': 'DockEnhanced',
        'CFBundleIdentifier': 'dev.yifeng.DockEnhancedFixture',
        'CFBundleName': 'Dock Enhanced Test',
        'CFBundlePackageType': 'APPL',
        'LSMinimumSystemVersion': '14.0',
        'NSHighResolutionCapable': True
    }, f)
PY
codesign --force --sign - --identifier dev.yifeng.DockEnhancedFixture "$fixture_dir"
source_fixture_dir="$project_dir/.build/Dock Enhanced Source.app"
mkdir -p "$source_fixture_dir/Contents/MacOS"
cp "$binary_dir/DockEnhanced" "$source_fixture_dir/Contents/MacOS/DockEnhanced"
python3 - "$fixture_dir/Contents/Info.plist" "$source_fixture_dir/Contents/Info.plist" <<'PYPLIST'
import plistlib, sys
with open(sys.argv[1], 'rb') as f: source = plistlib.load(f)
source['CFBundleIdentifier'] = 'dev.yifeng.DockEnhancedSourceFixture'
source['CFBundleName'] = 'Dock Enhanced Source'
with open(sys.argv[2], 'wb') as f: plistlib.dump(source, f)
PYPLIST
codesign --force --sign - --identifier dev.yifeng.DockEnhancedSourceFixture "$source_fixture_dir"
"$binary_dir/DockEnhanced" --integration-check "$fixture_dir" "$source_fixture_dir"

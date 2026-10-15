#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
build_mode="${1:-release}"
swift build --build-system native --configuration "$build_mode" --product DockEnhanced
binary_dir="$(swift build --build-system native --configuration "$build_mode" --show-bin-path)"
app_dir="$project_dir/dist/Dock Enhanced.app"
mkdir -p "$app_dir/Contents/MacOS"
cp "$binary_dir/DockEnhanced" "$app_dir/Contents/MacOS/DockEnhanced"
python3 - "$app_dir/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({
        'CFBundleExecutable': 'DockEnhanced',
        'CFBundleIdentifier': 'dev.yifeng.DockEnhanced',
        'CFBundleName': 'Dock Enhanced',
        'CFBundleDisplayName': 'Dock Enhanced',
        'CFBundlePackageType': 'APPL',
        'CFBundleShortVersionString': '0.2.0',
        'CFBundleVersion': '2',
        'LSMinimumSystemVersion': '14.0',
        'LSUIElement': True,
        'NSHighResolutionCapable': True
    }, f)
PY
codesign --force --sign - --identifier dev.yifeng.DockEnhanced "$app_dir"
print -r -- "$app_dir"

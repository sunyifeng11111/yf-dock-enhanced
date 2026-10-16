#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
build_mode="${1:-release}"
swift build --build-system native --configuration "$build_mode" --product DockEnhanced
binary_dir="$(swift build --build-system native --configuration "$build_mode" --show-bin-path)"
app_dir="$project_dir/dist/Dock Enhanced.app"
mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Resources"
cp "$binary_dir/DockEnhanced" "$app_dir/Contents/MacOS/DockEnhanced"
cp "$project_dir/assets/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
python3 - "$app_dir/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({
        'CFBundleExecutable': 'DockEnhanced',
        'CFBundleIdentifier': 'dev.yifeng.DockEnhanced',
        'CFBundleName': 'Dock Enhanced',
        'CFBundleDisplayName': 'Dock Enhanced',
        'CFBundlePackageType': 'APPL',
        'CFBundleShortVersionString': '0.6.6',
        'CFBundleVersion': '17',
        'CFBundleIconFile': 'AppIcon',
        'LSMinimumSystemVersion': '14.0',
        'LSUIElement': True,
        'CFBundleDevelopmentRegion': 'en',
        'CFBundleLocalizations': ['en', 'zh-Hans'],
        'NSHighResolutionCapable': True
    }, f)
PY
python3 scripts/sign-app.py "$app_dir"
print -r -- "$app_dir"

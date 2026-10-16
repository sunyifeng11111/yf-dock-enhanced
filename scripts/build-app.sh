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
mkdir -p "$app_dir/Contents/Frameworks"
# Preserve Sparkle's upstream nested signatures and symlinks. The host does not
# enable Hardened Runtime/library validation, so no re-signing workaround is needed.
codesign --verify --deep --strict "$binary_dir/Sparkle.framework"
rm -rf "$app_dir/Contents/Frameworks/Sparkle.framework"
ditto "$binary_dir/Sparkle.framework" "$app_dir/Contents/Frameworks/Sparkle.framework"
cp "$project_dir/.build/artifacts/sparkle/Sparkle/LICENSE" "$app_dir/Contents/Resources/Sparkle-LICENSE"
python3 - "$app_dir/Contents/Info.plist" <<'PY'
import plistlib, sys, json
with open("updates/config.json") as f:
    update_config = json.load(f)
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({
        'CFBundleExecutable': 'DockEnhanced',
        'CFBundleIdentifier': 'dev.yifeng.DockEnhanced',
        'CFBundleName': 'Dock Enhanced',
        'CFBundleDisplayName': 'Dock Enhanced',
        'CFBundlePackageType': 'APPL',
        'CFBundleShortVersionString': '0.6.7',
        'CFBundleVersion': '18',
        'CFBundleIconFile': 'AppIcon',
        'LSMinimumSystemVersion': '14.0',
        'LSUIElement': True,
        'CFBundleDevelopmentRegion': 'en',
        'CFBundleLocalizations': ['en', 'zh-Hans'],
        'NSHighResolutionCapable': True,
        'SUFeedURL': update_config['feedURL'],
        'SUPublicEDKey': update_config['publicEDKey'],
        'SURequireSignedFeed': True,
        'SUVerifyUpdateBeforeExtraction': True,
        'SUEnableAutomaticChecks': True,
        'SUAutomaticallyUpdate': False,
        'SUAllowsAutomaticUpdates': False,
        'SUSendProfileInfo': False,
        'SUScheduledCheckInterval': 86400
    }, f)
PY
python3 scripts/sign-app.py "$app_dir"
print -r -- "$app_dir"

#!/bin/zsh
# Package every native fixture with the executable's runtime dependencies.
build_native_fixture() {
    local binary_dir="$1" fixture_dir="$2" bundle_id="$3" display_name="$4"
    mkdir -p "$fixture_dir/Contents/MacOS" "$fixture_dir/Contents/Frameworks"
    cp "$binary_dir/DockEnhanced" "$fixture_dir/Contents/MacOS/DockEnhanced"
    rm -rf "$fixture_dir/Contents/Frameworks/Sparkle.framework"
    ditto "$binary_dir/Sparkle.framework" "$fixture_dir/Contents/Frameworks/Sparkle.framework"
    python3 - "$fixture_dir/Contents/Info.plist" "$bundle_id" "$display_name" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as stream:
    plistlib.dump({
        'CFBundleExecutable': 'DockEnhanced',
        'CFBundleIdentifier': sys.argv[2],
        'CFBundleName': sys.argv[3],
        'CFBundlePackageType': 'APPL',
        'LSMinimumSystemVersion': '14.0',
        'NSHighResolutionCapable': True
    }, stream)
PY
    codesign --force --sign - --identifier "$bundle_id" "$fixture_dir"
}

#!/bin/zsh
# Build a compressed disk image for the current machine's architecture.
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"

scripts/build-app.sh release
app_dir="$project_dir/dist/Dock Enhanced.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Contents/Info.plist")
architecture=$(uname -m)
image_name="Dock-Enhanced-${version}-macOS-${architecture}"
image_path="$project_dir/dist/${image_name}.dmg"
if [[ -e "$image_path" ]]; then
    print -u2 -- "Already exists: $image_path. Move it aside before rebuilding."
    exit 1
fi

staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/dock-enhanced-dmg.XXXXXX")
trap 'rm -rf -- "$staging_dir"' EXIT
ditto "$app_dir" "$staging_dir/Dock Enhanced.app"
ln -s /Applications "$staging_dir/Applications"
codesign --verify --deep --strict "$staging_dir/Dock Enhanced.app"
hdiutil create -volname "Dock Enhanced" -srcfolder "$staging_dir" \
    -format UDZO -fs HFS+ "$image_path"
hdiutil verify "$image_path"
(cd "$project_dir/dist" && shasum -a 256 "${image_name}.dmg" > "${image_name}.dmg.sha256")
print -r -- "$image_path"
print -r -- "This image uses the persistent self-signed identity and is not notarized."

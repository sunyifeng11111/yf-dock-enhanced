#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
# Keep production optimization while including the dedicated diagnostic entry.
scratch_dir="$project_dir/.build/thumbnail-delivery"
swift build --build-system native --scratch-path "$scratch_dir" --configuration release -Xswiftc -DDEBUG --product DockEnhanced
binary_dir="$(swift build --build-system native --scratch-path "$scratch_dir" --configuration release --show-bin-path)"
"$binary_dir/DockEnhanced" --check-thumbnail-delivery "$@"

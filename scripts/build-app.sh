#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
if [[ "$configuration" != debug && "$configuration" != release ]]; then
  echo 'Usage: scripts/build-app.sh [debug|release]' >&2
  exit 2
fi
build_args=()
if [[ -n "${ACC_BUILD_PATH:-}" ]]; then build_args+=(--scratch-path "$ACC_BUILD_PATH"); fi
if [[ -n "${ACC_BUILD_SYSTEM:-}" ]]; then build_args+=(--build-system "$ACC_BUILD_SYSTEM"); fi
if [[ -n "${ACC_PLUGIN_PATH:-}" ]]; then build_args+=(-Xswiftc -plugin-path -Xswiftc "$ACC_PLUGIN_PATH"); fi
swift build "${build_args[@]}" -c "$configuration"
bin_dir="$(swift build "${build_args[@]}" -c "$configuration" --show-bin-path)"
app="$PWD/build/USS ACC.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/USSACC" "$app/Contents/MacOS/USSACC"
cp Info.plist "$app/Contents/Info.plist"
cp -f docs/SwiftTerm-LICENSE "$app/Contents/Resources/SwiftTerm-LICENSE"
# SwiftTerm probes Contents/Resources for its packaged Metal shader bundle.
shopt -s nullglob
for bundle in "$bin_dir"/*.bundle; do
  cp -Rf "$bundle" "$app/Contents/Resources/"
done
/usr/bin/plutil -lint "$app/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$app"
echo "Built: $app"

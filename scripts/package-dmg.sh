#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <version>" >&2
  exit 64
fi

version="$1"
version="${version#v}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid version: $version" >&2
  exit 64
fi

architecture="$(uname -m)"
product_name="OMP API Manager"
bundle_name="OMP API Manager.app"
bundle_identifier="com.omp-api-manager"
dist_dir="$root_dir/dist"
dmg_name="OMP-API-Manager-${version}-macos-${architecture}.dmg"
dmg_path="$dist_dir/$dmg_name"
work_dir="$(mktemp -d "${TMPDIR:-/private/tmp}/omp-api-manager.XXXXXX")"
app_dir="$work_dir/$bundle_name"
staging_dir="$work_dir/dmg-staging"
iconset_dir="$work_dir/AppIcon.iconset"
smoke_pid=""

cleanup() {
  if [[ -n "$smoke_pid" ]] && kill -0 "$smoke_pid" >/dev/null 2>&1; then
    kill "$smoke_pid" >/dev/null 2>&1 || true
    wait "$smoke_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$work_dir"
}
trap cleanup EXIT

if [[ "$architecture" != "arm64" && "$architecture" != "x86_64" ]]; then
  echo "Unsupported macOS architecture: $architecture" >&2
  exit 1
fi

mkdir -p "$dist_dir"
rm -f "$dmg_path" "$dmg_path.sha256"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$iconset_dir"

swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
resource_bundle="$bin_dir/OMPAPIManager_OMPAPIManagerApp.bundle"

if [[ ! -x "$bin_dir/OMPAPIManager" ]]; then
  echo "Release executable was not produced at $bin_dir/OMPAPIManager" >&2
  exit 1
fi

if [[ ! -d "$resource_bundle" ]]; then
  echo "SwiftPM resource bundle was not produced at $resource_bundle" >&2
  exit 1
fi

install -m 755 "$bin_dir/OMPAPIManager" "$app_dir/Contents/MacOS/OMPAPIManager"
ditto "$resource_bundle" "$app_dir/Contents/Resources/$(basename "$resource_bundle")"

source_icon="Sources/OMPAPIManagerApp/Resources/AppIcon-master.png"
install -m 644 "$source_icon" "$app_dir/Contents/Resources/AppIcon-master.png"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$source_icon" --out "$iconset_dir/icon_${size}x${size}.png" >/dev/null
done
sips -z 32 32 "$source_icon" --out "$iconset_dir/icon_16x16@2x.png" >/dev/null
sips -z 64 64 "$source_icon" --out "$iconset_dir/icon_32x32@2x.png" >/dev/null
sips -z 256 256 "$source_icon" --out "$iconset_dir/icon_128x128@2x.png" >/dev/null
sips -z 512 512 "$source_icon" --out "$iconset_dir/icon_256x256@2x.png" >/dev/null
sips -z 1024 1024 "$source_icon" --out "$iconset_dir/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$iconset_dir" -o "$app_dir/Contents/Resources/AppIcon.icns"

cat > "$app_dir/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>${product_name}</string>
  <key>CFBundleExecutable</key>
  <string>OMPAPIManager</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>${bundle_identifier}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${product_name}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${version}</string>
  <key>CFBundleVersion</key>
  <string>${version}</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.developer-tools</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright 2026 OMP API Manager contributors</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$app_dir/Contents/PkgInfo"
plutil -lint "$app_dir/Contents/Info.plist"
xattr -cr "$app_dir"
codesign --force --deep --sign - --timestamp=none "$app_dir"
codesign --verify --deep --strict "$app_dir"

smoke_home="$work_dir/smoke-home"
smoke_log="$work_dir/smoke.log"
mkdir -p "$smoke_home"
HOME="$smoke_home" "$app_dir/Contents/MacOS/OMPAPIManager" >"$smoke_log" 2>&1 &
smoke_pid=$!
sleep 2
if ! kill -0 "$smoke_pid" >/dev/null 2>&1; then
  status=0
  wait "$smoke_pid" || status=$?
  echo "Packaged app exited during launch smoke test (status $status)." >&2
  cat "$smoke_log" >&2
  exit 1
fi
kill "$smoke_pid"
wait "$smoke_pid" >/dev/null 2>&1 || true
smoke_pid=""

mkdir -p "$staging_dir"
ditto "$app_dir" "$staging_dir/$bundle_name"
xattr -cr "$staging_dir/$bundle_name"
ln -s /Applications "$staging_dir/Applications"
hdiutil create -volname "$product_name" -srcfolder "$staging_dir" -ov -format UDZO "$dmg_path" >/dev/null
(cd "$dist_dir" && shasum -a 256 "$dmg_name" > "$dmg_name.sha256")

echo "Created: $dmg_path"
cat "$dmg_path.sha256"

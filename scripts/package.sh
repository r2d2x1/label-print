#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh -c release
app="$PWD/docs/releases/LabelPrint.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/LabelPrint "$app/Contents/MacOS/LabelPrint"
python3 scripts/third-party-notices.py
cp LICENSE NOTICE "$app/Contents/Resources/"
mkdir -p "$app/Contents/Resources/ThirdPartyNotices"
cp -R ThirdPartyNotices/. "$app/Contents/Resources/ThirdPartyNotices/"
cp docs/third-party-licenses.md "$app/Contents/Resources/ThirdPartyNotices/README.md"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LabelPrint</string>
<key>CFBundleIdentifier</key><string>local.labelprint.app</string>
<key>CFBundleName</key><string>LabelPrint</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
echo "Built $app"

#!/bin/bash
set -e

APP_NAME="Spoted"
APP_DIR="$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Building $APP_NAME..."
swift build

echo "Packaging into $APP_DIR..."
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Copy binary
cp .build/debug/$APP_NAME "$MACOS_DIR/$APP_NAME"

# Copy resources bundle if exists
if [ -d ".build/debug/Spoted_Spoted.bundle" ]; then
    cp -R ".build/debug/Spoted_Spoted.bundle" "$RESOURCES_DIR/"
fi

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>Spoted</string>
	<key>CFBundleIdentifier</key>
	<string>com.ghostwan.Spoted</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Spoted</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLName</key>
			<string>com.ghostwan.Spoted</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>spoted</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
EOF

echo "Done! Run with: open $APP_DIR"

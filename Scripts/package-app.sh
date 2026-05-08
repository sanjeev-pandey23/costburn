#!/usr/bin/env bash
# Builds a universal .app bundle from the SwiftPM package.
# Usage: ./Scripts/package-app.sh [version]
# Output: .build/CostBurn.app  and  .build/CostBurn-<version>.zip

set -euo pipefail

VERSION="${1:-0.1.0}"
APP_NAME="CostBurn"
BINARY_NAME="costburn"
BUNDLE_ID="com.sanjeevpandey.costburn"
BUILD_DIR=".build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app/Contents"

echo "==> Building for arm64..."
swift build -c release --arch arm64

echo "==> Building for x86_64..."
swift build -c release --arch x86_64

echo "==> Creating universal binary..."
mkdir -p "${APP_DIR}/MacOS"
lipo -create \
    ".build/arm64-apple-macosx/release/${BINARY_NAME}" \
    ".build/x86_64-apple-macosx/release/${BINARY_NAME}" \
    -output "${APP_DIR}/MacOS/${BINARY_NAME}"

echo "==> Copying Info.plist..."
mkdir -p "${APP_DIR}"
cp Resources/Info.plist "${APP_DIR}/Info.plist"

# Patch version into Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP_DIR}/Info.plist"

echo "==> Ad-hoc code signing..."
codesign --force --deep --sign - "${BUILD_DIR}/${APP_NAME}.app"

echo "==> Creating ZIP archive..."
ZIP_NAME="${APP_NAME}-${VERSION}.zip"
cd "${BUILD_DIR}"
ditto -c -k --sequesterRsrc --keepParent "${APP_NAME}.app" "${ZIP_NAME}"
cd ..

echo "==> Computing SHA256..."
shasum -a 256 "${BUILD_DIR}/${ZIP_NAME}" | awk '{print $1}' > "${BUILD_DIR}/${ZIP_NAME}.sha256"

echo ""
echo "Done!"
echo "  App:      ${BUILD_DIR}/${APP_NAME}.app"
echo "  ZIP:      ${BUILD_DIR}/${ZIP_NAME}"
echo "  SHA256:   $(cat "${BUILD_DIR}/${ZIP_NAME}.sha256")"

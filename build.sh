#!/bin/bash
set -e

APP_NAME="FusionNotch"
BUNDLE="${APP_NAME}.app"
BUILD_DIR="build"
CONTENTS="${BUILD_DIR}/${BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

echo "==> Cleaning build dir..."
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS" "$RESOURCES"

echo "==> Compiling Swift sources..."
swiftc \
    -framework Cocoa \
    -framework IOKit \
    -framework SwiftUI \
    -framework ServiceManagement \
    -framework ApplicationServices \
    -swift-version 5 \
    -O \
    FusionNotch/main.swift \
    FusionNotch/AppDelegate.swift \
    FusionNotch/NotchTracker.swift \
    FusionNotch/OverlayWindowController.swift \
    FusionNotch/NotchPanelView.swift \
    FusionNotch/MetricsEngine.swift \
    -o "${MACOS}/${APP_NAME}"

echo "==> Copying resources..."
cp FusionNotch/Info.plist "${CONTENTS}/Info.plist"
# Minimal asset catalog not required for a background app — skip xcassets compilation
printf 'APPL????' > "${CONTENTS}/PkgInfo"

echo "==> Ad-hoc code signing..."
codesign --force --deep --sign - \
    --entitlements FusionNotch/FusionNotch.entitlements \
    "${BUILD_DIR}/${BUNDLE}"

echo ""
echo "Build complete: ${BUILD_DIR}/${BUNDLE}"

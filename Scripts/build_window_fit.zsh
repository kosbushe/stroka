#!/bin/zsh
set -euo pipefail
STROKA_ROOT="${0:A:h:h}"
STROKA_HELPER="${1:?Helper output folder}/Stroka Windows.app"
mkdir -p "$STROKA_HELPER/Contents/MacOS" "$STROKA_ROOT/.build/window-fit-cache"
STROKA_HELPER_BINARIES=()
for STROKA_HELPER_ARCH in ${=STROKA_ARCHS:-arm64 x86_64}; do
  STROKA_HELPER_BINARY="$STROKA_ROOT/.build/WindowFit.$STROKA_HELPER_ARCH"
  xcrun swiftc -O -swift-version 5 -module-cache-path "$STROKA_ROOT/.build/window-fit-cache" -target "$STROKA_HELPER_ARCH-apple-macosx14.0" "$STROKA_ROOT/Sources/WindowFitGeometry.swift" "$STROKA_ROOT/Helpers/WindowFit/main.swift" -framework AppKit -framework ApplicationServices -o "$STROKA_HELPER_BINARY"
  STROKA_HELPER_BINARIES+=("$STROKA_HELPER_BINARY")
done
xcrun lipo -create "${STROKA_HELPER_BINARIES[@]}" -output "$STROKA_HELPER/Contents/MacOS/StrokaWindows"
cp "$STROKA_ROOT/Helpers/WindowFit/Info.plist" "$STROKA_HELPER/Contents/Info.plist"
codesign --force --options runtime --sign "${STROKA_SIGN_IDENTITY:--}" "$STROKA_HELPER"

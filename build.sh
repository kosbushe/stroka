#!/bin/zsh
set -euo pipefail
STROKA_ROOT="${0:A:h}"
STROKA_OUT="${1:-$STROKA_ROOT/dist}"
STROKA_APP="$STROKA_OUT/Stroka.app"
mkdir -p "$STROKA_APP/Contents/MacOS" "$STROKA_APP/Contents/Resources" "$STROKA_ROOT/.build/module-cache"
python3 "$STROKA_ROOT/Scripts/generate_localizations.py"
STROKA_ARCHS="${STROKA_ARCHS:-arm64 x86_64}"
STROKA_BINARIES=()
STROKA_EXTRAS=()
if [[ "${STROKA_DIAGNOSTICS:-0}" == "1" ]]; then STROKA_EXTRAS=(-D STROKA_DIAGNOSTICS "$STROKA_ROOT/Tests/Diagnostics.swift"); fi
for STROKA_ARCH in ${=STROKA_ARCHS}; do
  STROKA_BINARY="$STROKA_ROOT/.build/Stroka.$STROKA_ARCH"
  xcrun swiftc -swift-version 5 -O -module-cache-path "$STROKA_ROOT/.build/module-cache" -target "$STROKA_ARCH-apple-macosx14.0" "$STROKA_ROOT"/Sources/*.swift "${STROKA_EXTRAS[@]}" -o "$STROKA_BINARY" -framework AppKit -framework SwiftUI -framework Network -framework Security -framework NaturalLanguage -framework QuartzCore -Xlinker -weak_framework -Xlinker Translation
  STROKA_BINARIES+=("$STROKA_BINARY")
done
xcrun lipo -create "${STROKA_BINARIES[@]}" -output "$STROKA_APP/Contents/MacOS/Stroka"
cp "$STROKA_ROOT/Info.plist" "$STROKA_APP/Contents/Info.plist"
if [[ "${STROKA_DIAGNOSTICS:-0}" == "1" ]]; then /usr/libexec/PlistBuddy -c "Add :StrokaDiagnostics bool true" "$STROKA_APP/Contents/Info.plist"; fi
if [[ -f "$STROKA_ROOT/AppIcon.icns" ]]; then cp "$STROKA_ROOT/AppIcon.icns" "$STROKA_APP/Contents/Resources/AppIcon.icns"; fi
cp "$STROKA_ROOT/PrivacyInfo.xcprivacy" "$STROKA_APP/Contents/Resources/PrivacyInfo.xcprivacy"
cp "$STROKA_ROOT/Resources/Collections.json" "$STROKA_ROOT/Resources/NewsCatalog.json" "$STROKA_ROOT/Resources/MarketCatalog.json" "$STROKA_APP/Contents/Resources/"
cp -R "$STROKA_ROOT/Resources/en.lproj" "$STROKA_ROOT/Resources/ru.lproj" "$STROKA_APP/Contents/Resources/"
if [[ "${STROKA_WINDOW_FIT:-1}" == "1" ]]; then
  STROKA_ARCHS="$STROKA_ARCHS" zsh "$STROKA_ROOT/Scripts/build_window_fit.zsh" "$STROKA_APP/Contents/Helpers"
fi
codesign --force --options runtime --entitlements "$STROKA_ROOT/Stroka.entitlements" --sign "${STROKA_SIGN_IDENTITY:--}" "$STROKA_APP"
echo "$STROKA_APP"

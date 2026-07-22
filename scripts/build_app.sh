#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ChatPulse.app можно собрать только на macOS." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ChatPulse"
BUNDLE_ID="com.mishkacher.ChatPulse"
VERSION_FILE="$ROOT_DIR/VERSION"
BUILD_NUMBER_FILE="$ROOT_DIR/BUILD_NUMBER"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$ROOT_DIR/Resources/ChatPulseIcon.svg"
ICON_WORK_DIR="$DIST_DIR/.icon-work"
ICON_PNG="$ICON_WORK_DIR/ChatPulseIcon-1024.png"
ICONSET_DIR="$ICON_WORK_DIR/ChatPulse.iconset"
SIGN_IDENTITY="${CHATPULSE_CODESIGN_IDENTITY:--}"
ARCHITECTURE_LIST="${CHATPULSE_ARCHITECTURES:-arm64 x86_64}"

read_trimmed() {
  tr -d '[:space:]' < "$1"
}

[[ -f "$VERSION_FILE" ]] || { echo "Не найден VERSION" >&2; exit 1; }
[[ -f "$BUILD_NUMBER_FILE" ]] || { echo "Не найден BUILD_NUMBER" >&2; exit 1; }

APP_VERSION="$(read_trimmed "$VERSION_FILE")"
BUILD_NUMBER="$(read_trimmed "$BUILD_NUMBER_FILE")"

[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Некорректная версия приложения: $APP_VERSION" >&2
  exit 1
}
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || {
  echo "Некорректный номер сборки: $BUILD_NUMBER" >&2
  exit 1
}

read -r -a ARCHITECTURES <<< "$ARCHITECTURE_LIST"
[[ ${#ARCHITECTURES[@]} -gt 0 ]] || {
  echo "Не указаны архитектуры сборки" >&2
  exit 1
}

SWIFT_ARCH_ARGS=()
for architecture in "${ARCHITECTURES[@]}"; do
  case "$architecture" in
    arm64|x86_64)
      SWIFT_ARCH_ARGS+=(--arch "$architecture")
      ;;
    *)
      echo "Неподдерживаемая архитектура: $architecture" >&2
      exit 1
      ;;
  esac
done

cd "$ROOT_DIR"
rm -rf "$APP_DIR" "$ICON_WORK_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR"

swift build -c release "${SWIFT_ARCH_ARGS[@]}"
BIN_DIR="$(swift build -c release "${SWIFT_ARCH_ARGS[@]}" --show-bin-path)"
cp "$BIN_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

ACTUAL_ARCHITECTURES="$(lipo -archs "$MACOS_DIR/$APP_NAME")"
for architecture in "${ARCHITECTURES[@]}"; do
  grep -qw "$architecture" <<< "$ACTUAL_ARCHITECTURES" || {
    echo "В бинарнике отсутствует архитектура $architecture: $ACTUAL_ARCHITECTURES" >&2
    exit 1
  }
done

if [[ -f "$ICON_SOURCE" ]]; then
  # AppKit сохраняет векторный SVG в исходный PNG 1024×1024,
  # после чего стандартные утилиты macOS формируют полноценный .icns.
  swift - "$ICON_SOURCE" "$ICON_PNG" <<'SWIFT'
import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Не переданы пути иконки.\n", stderr)
    exit(1)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let image = NSImage(contentsOf: sourceURL),
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 1024,
        pixelsHigh: 1024,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      ) else {
    fputs("Не удалось открыть или подготовить иконку.\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
image.draw(
    in: NSRect(x: 0, y: 0, width: 1024, height: 1024),
    from: .zero,
    operation: .copy,
    fraction: 1
)
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Не удалось создать PNG иконки.\n", stderr)
    exit(1)
}
try data.write(to: outputURL, options: .atomic)
SWIFT

  sips -z 16 16     "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32     "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32     "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64     "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128   "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256   "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256   "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512   "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512   "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  cp "$ICON_PNG" "$ICONSET_DIR/icon_512x512@2x.png"
  iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/ChatPulse.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>ru</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>CFBundleGetInfoString</key>
  <string>ChatPulse $APP_VERSION</string>
  <key>CFBundleIconFile</key>
  <string>ChatPulse</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSMultipleInstancesProhibited</key>
  <true/>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 mishkacher. MIT License.</string>
</dict>
</plist>
PLIST

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --options runtime --timestamp=none --sign - "$APP_DIR"
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR"
fi

codesign --verify --deep --strict "$APP_DIR"
rm -rf "$ICON_WORK_DIR"

echo "Собрано: $APP_DIR"
echo "Версия: $APP_VERSION (build $BUILD_NUMBER)"
echo "Архитектуры: $ACTUAL_ARCHITECTURES"

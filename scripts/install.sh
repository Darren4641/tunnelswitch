#!/bin/bash
# 빌드 → ~/Applications/TunnelSwitch.app 설치 → tunsw CLI 링크 → 앱 실행
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="$HOME/Applications/TunnelSwitch.app"
LEGACY_APP="$HOME/Applications/DBTunnel.app"  # 예전 이름
STAGE="$ROOT/.build/TunnelSwitch.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/TunnelSwitch"

rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BIN" "$STAGE/Contents/MacOS/TunnelSwitch"
cp "$ROOT/engine/tunsw" "$STAGE/Contents/Resources/tunsw"
chmod +x "$STAGE/Contents/Resources/tunsw"

# 아이콘: scripts/make-icon.swift 로 그린 1024px 원본에서 .icns 생성
ICONSET="$ROOT/.build/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
swift "$ROOT/scripts/make-icon.swift" "$ROOT/.build/icon-1024.png" >/dev/null
for px in 16 32 128 256 512; do
  sips -z $px $px "$ROOT/.build/icon-1024.png" --out "$ICONSET/icon_${px}x${px}.png" >/dev/null
  sips -z $((px * 2)) $((px * 2)) "$ROOT/.build/icon-1024.png" --out "$ICONSET/icon_${px}x${px}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$STAGE/Contents/Resources/AppIcon.icns"

cat > "$STAGE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>TunnelSwitch</string>
  <key>CFBundleDisplayName</key><string>터널 스위처</string>
  <key>CFBundleIdentifier</key><string>dev.artinus.tunnelswitch</string>
  <key>CFBundleExecutable</key><string>TunnelSwitch</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$STAGE" >/dev/null

pkill -x TunnelSwitch 2>/dev/null && sleep 0.5 || true
pkill -x DBTunnel 2>/dev/null && sleep 0.5 || true  # 예전 이름
mkdir -p "$HOME/Applications"
rm -rf "$APP" "$LEGACY_APP"
cp -R "$STAGE" "$APP"
touch "$APP"  # Finder·Dock 의 아이콘 캐시 갱신

# 터미널용 CLI 는 레포의 엔진을 직접 가리킨다
mkdir -p "$HOME/.local/bin"
ln -sf "$ROOT/engine/tunsw" "$HOME/.local/bin/tunsw"
ln -sf "$ROOT/engine/tunsw" "$HOME/.local/bin/dbtun"  # 예전 명령 이름도 그대로 쓸 수 있게

echo "설치됨: $APP"
open "$APP"

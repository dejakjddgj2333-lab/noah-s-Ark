#!/bin/bash
# 明策 macOS 一键打包: 构建 → Developer ID 重签名 → 公证 → DMG
# 前置: 本机钥匙串已装 "Developer ID Application" 证书 (Team C4Y8S5CHFT)
# 用法:
#   ./打包公证mac.sh                 # 构建+签名+公证+DMG 全流程
#   SKIP_NOTARIZE=1 ./打包公证mac.sh  # 只构建+签名+DMG, 跳过公证 (临时测试)
set -e

DESKTOP_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DESKTOP_DIR"

APP_NAME="明策"
BUNDLE_ID="com.hkmc.noahsark.desktop"
TEAM_ID="C4Y8S5CHFT"
SIGN_IDENTITY="Developer ID Application"
DMG_NAME="mingce-mac.dmg"
APP_PATH="build/macos/Build/Products/Release/${APP_NAME}.app"

# 公证凭据: 复用 App Store Connect API key (与 iOS 上传同一把)
ASC_KEY_ID="553U88DHNG"
ASC_ISSUER="179ed838-15a7-4b56-82d0-a4d9f65eaeb9"
ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"

IDENTITY_FULL=$(security find-identity -v -p codesigning | grep "$SIGN_IDENTITY" | grep "$TEAM_ID" | head -1 | sed -E 's/.*"(.*)"/\1/')
if [ -z "$IDENTITY_FULL" ]; then
  echo "❌ 未找到 $SIGN_IDENTITY ($TEAM_ID) 证书。"
  echo "   请先到 Apple Developer 后台为 Team $TEAM_ID 签发 Developer ID Application 证书并双击安装进钥匙串。"
  exit 1
fi
echo "==> 签名身份: $IDENTITY_FULL"

echo "==> flutter build macos --release"
flutter build macos --release

if [ ! -d "$APP_PATH" ]; then
  echo "❌ 未找到产物 $APP_PATH"; exit 1
fi

echo "==> Developer ID 重签名 (含嵌套, hardened runtime)"
codesign --deep --force --options runtime --timestamp \
  --entitlements macos/Runner/Release.entitlements \
  --sign "$IDENTITY_FULL" "$APP_PATH"

echo "==> 校验签名"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type exec --verbose=2 "$APP_PATH" || echo "(公证前 spctl 可能仍拦, 属正常)"

echo "==> 打 DMG"
rm -f "$DMG_NAME"
create-dmg \
  --volname "$APP_NAME" \
  --window-pos 200 120 --window-size 660 400 \
  --icon-size 100 --app-drop-link 480 170 \
  --hide-extension "${APP_NAME}.app" \
  "$DMG_NAME" "$APP_PATH" >/dev/null
echo "   生成 $DMG_NAME"

if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
  echo "==> SKIP_NOTARIZE=1, 跳过公证 (仅本地测试)"
  echo "==> ✅ 完成(未公证): $DESKTOP_DIR/$DMG_NAME"
  exit 0
fi

if [ ! -f "$ASC_KEY_PATH" ]; then
  echo "❌ 未找到公证私钥 $ASC_KEY_PATH"; exit 1
fi

echo "==> 提交公证 (notarytool, 等待结果)"
xcrun notarytool submit "$DMG_NAME" \
  --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER" \
  --wait

echo "==> 贴票 stapler"
xcrun stapler staple "$DMG_NAME"

echo "==> 公证后校验"
spctl --assess --type open --verbose=2 "$DMG_NAME" && echo "   Gatekeeper 通过"

echo "==> ✅ 完成: $DESKTOP_DIR/$DMG_NAME"
echo "    上传到落地页站点根 /www/wwwroot/app.mingcevip.com/ 即可通过 https://app.mingcevip.com/$DMG_NAME 下载"

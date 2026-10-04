#!/bin/bash
# 明策 iOS 一键打包并上传 App Store Connect / TestFlight
# 用法:
#   ./打包上传ios.sh            # build 号自动 +1
#   ./打包上传ios.sh 5          # 指定 build 号为 5
set -e

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$APP_DIR"

VERSION="1.0.0"
API_KEY="553U88DHNG"
API_ISSUER="179ed838-15a7-4b56-82d0-a4d9f65eaeb9"
PROXY="http://127.0.0.1:7890"
COUNTER_FILE="$APP_DIR/ios/.build_number"

# ---- 计算 build 号 ----
if [ -n "$1" ]; then
  BUILD="$1"
else
  LAST=$(cat "$COUNTER_FILE" 2>/dev/null || echo 1)
  BUILD=$((LAST + 1))
fi
echo "$BUILD" > "$COUNTER_FILE"
echo "==> 版本 $VERSION  build $BUILD"

# ---- 代理(pod 下载 WebRTC 需要) ----
export http_proxy="$PROXY" https_proxy="$PROXY" all_proxy="socks5://127.0.0.1:7890"

# ---- 打包 ----
echo "==> 构建 IPA ..."
flutter build ipa --release \
  --build-name="$VERSION" --build-number="$BUILD" \
  --export-options-plist=ios/ExportOptions.plist

IPA=$(ls "$APP_DIR"/build/ios/ipa/*.ipa)
echo "==> 构建完成: $IPA"

# ---- 上传 ----
echo "==> 上传到 App Store Connect ..."
xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$API_KEY" --apiIssuer "$API_ISSUER"

echo "==> ✅ 上传成功: 版本 $VERSION (build $BUILD)"
echo "    几分钟后到 App Store Connect > TestFlight 查看构建版本"

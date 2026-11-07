#!/bin/bash
# 明策 iOS 一键打包并上传 App Store Connect / TestFlight
# 用法:
#   ./打包上传ios.sh            # 完整功能包 (含交易/充值/理财), build 号自动 +1
#   ./打包上传ios.sh review     # 审核包 (隐藏交易/充值/理财, 苹果 2.3.1), build 号自动 +1
#   ./打包上传ios.sh 5          # 完整包, 指定 build 号为 5
#   ./打包上传ios.sh review 5   # 审核包, 指定 build 号
set -e

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$APP_DIR"

VERSION="1.0.0"
API_KEY="553U88DHNG"
API_ISSUER="179ed838-15a7-4b56-82d0-a4d9f65eaeb9"
PROXY="http://127.0.0.1:7890"
COUNTER_FILE="$APP_DIR/ios/.build_number"

# ---- 解析参数: review 开关 + 可选 build 号 ----
MODE="full"
for arg in "$@"; do
  if [ "$arg" = "review" ]; then MODE="review"; fi
done
BUILD_ARG="$(echo "$@" | tr ' ' '\n' | grep -E '^[0-9]+$' | head -1)"

# ---- 计算 build 号 ----
if [ -n "$BUILD_ARG" ]; then
  BUILD="$BUILD_ARG"
else
  LAST=$(cat "$COUNTER_FILE" 2>/dev/null || echo 1)
  BUILD=$((LAST + 1))
fi
echo "$BUILD" > "$COUNTER_FILE"

# ---- FeatureFlag dart-define (编译进包) ----
if [ "$MODE" = "review" ]; then
  DEFINES=""
  echo "==> 版本 $VERSION  build $BUILD  [审核包: 隐藏交易/充值/理财]"
else
  DEFINES="--dart-define=WALLET_ENABLED=true --dart-define=FINANCE_ENABLED=true"
  echo "==> 版本 $VERSION  build $BUILD  [完整包: 含交易/充值/理财]"
fi

# ---- 代理(pod 下载 WebRTC 需要) ----
export http_proxy="$PROXY" https_proxy="$PROXY" all_proxy="socks5://127.0.0.1:7890"

# ---- 打包 ----
echo "==> 构建 IPA ..."
flutter build ipa --release \
  --build-name="$VERSION" --build-number="$BUILD" \
  $DEFINES \
  --export-options-plist=ios/ExportOptions.plist

IPA=$(ls "$APP_DIR"/build/ios/ipa/*.ipa)
echo "==> 构建完成: $IPA"

# ---- 上传 ----
echo "==> 上传到 App Store Connect ..."
xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$API_KEY" --apiIssuer "$API_ISSUER"

echo "==> ✅ 上传成功: 版本 $VERSION (build $BUILD)"
echo "    几分钟后到 App Store Connect > TestFlight 查看构建版本"

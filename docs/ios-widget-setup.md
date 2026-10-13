# iOS Widget Extension + Live Activities 接线 (已自动化)

代码全部就绪 (`app/ios/MingceWidget/`). target 接入 Xcode 工程已**脚本化**:
`app/ios/inject_widget_target.rb` (xcodeproj gem, 幂等).

## 已完成 (脚本)

1. `inject_widget_target.rb`: 把 `MingceWidget` app-extension target 注入
   `Runner.xcodeproj` — 5 个 Swift 文件入 Sources、entitlements/Info.plist 引用、
   bundle id `com.hkmc.noahsark.MingceWidget`、deployment 15.0、Runner 加
   Embed App Extensions phase + target 依赖。
   - **坑**: Xcode 15/16 新构建系统报 `Cycle inside Runner`, 解法是 Embed App
     Extensions phase 必须排在 `Run Script`/`Thin Binary` **之前** (脚本已处理)。
2. ASC API: 注册 widget bundle id (`SHA3ZNMFM8`) + 主/ widget 均开
   `APP_GROUPS` capability。
3. `pod install` 装 `home_widget` pod (需代理 `127.0.0.1:7890`, WebRTC 走 GitHub)。
4. `xcodebuild -configuration Debug CODE_SIGNING_ALLOWED=NO` 编译验证 **BUILD SUCCEEDED**,
   `MingceWidget.appex` 正确嵌入 `Runner.app/PlugIns/`。

## 修的编译 bug (iOS 15/16 兼容)

- `SharedStore.isZh`: `Locale.language.languageCode` 是 iOS16 API → 加 `#available` 回退 `Locale.languageCode`。
- 两 widget 的 `.containerBackground(_:for:)` 是 iOS17 API → `#available(iOS 17)` 包, 旧版回退 `.padding().background()`。

## 仍需手动 (Apple 不开放 API)

**App Group 创建 + 分配** (developer.apple.com → Certificates, Identifiers & Profiles → Identifiers):

1. 左上加号 **＋** → **App Groups** → Continue
   - Description: `Mingce Shared`, Identifier: `group.com.hkmc.noahsark.shared` → Register
2. Identifiers 列表点 **`com.hkmc.noahsark`** → 勾 **App Groups** → Configure → 勾
   `group.com.hkmc.noahsark.shared` → Save
3. 同样处理 **`com.hkmc.noahsark.MingceWidget`** → 勾 App Groups → assign 同一 group → Save

## App Group 建好后 (脚本继续)

4. ASC API 重建 2 个 App Store profile (含 application-groups entitlement) + 下载安装:
   - 主 App `com.hkmc.noahsark` (cert `223JTY52C4`)
   - widget `com.hkmc.noahsark.MingceWidget`
   - 取新 UUID 填 Runner/MingceWidget Release 的 `PROVISIONING_PROFILE_SPECIFIER`
     + `ExportOptions.plist` provisioningProfiles dict。
5. `cd app && flutter build ipa --release --export-options-plist=ios/ExportOptions.plist`

## 真机自验清单

- 桌面长按加小组件: 「明策行情」「巨鲸异动」两个出现, 打开过 App 后有数据
- App 内行情详情页 → 心跳图标 (盯盘): 锁屏出现实时价横幅, 服务端 60s 一轮 APNs 更新; 灵动岛长按展开
- 盯盘需登录 (activity push token 绑账号); 未登录点按会提示
- 分享按钮 → 生成 K线卡片 PNG → 系统分享面板

## 故障排查

- 小组件无数据: 数据是 App 前台时写入 App Group 的, 至少开一次 App 且等 30s
  (五币首帧齐了才写, 见 `widget_bridge.dart`)
- Live Activity 不更新: 盯盘开启后等 ~10s 拿 push token, 之后服务端 60s 一轮;
  服务端日志看 `live_activity_error` / `apns_live_activity_failed`
- `Cycle inside Runner`: embed phase 顺序被改回, 重跑 `inject_widget_target.rb`

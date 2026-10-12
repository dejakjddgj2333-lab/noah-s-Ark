# iOS Widget Extension + Live Activities 接线步骤 (Mac/Xcode)

代码已全部备好 (`app/ios/MingceWidget/`), 需在 Mac 上把 target 接进 Xcode 工程。

## 步骤

1. `cd app && flutter pub get && cd ios && pod install`
2. Xcode 打开 `app/ios/Runner.xcworkspace` (不是 .xcodeproj)
3. File → New → Target → **Widget Extension**
   - Product Name: `MingceWidget`
   - Bundle ID: `com.hkmc.noahsark.MingceWidget`
   - 不勾 "Include Live Activity" / "Include Configuration App Intent" (我们都已手写)
   - Activate scheme 弹窗: 选 Activate
   - Xcode 会在 `ios/MingceWidget/` 生成模板文件, 与我们的文件同目录; 删掉生成的 `MingceWidget.swift` / `MingceWidgetBundle.swift` / `AppIntent.swift` 等模板, 把仓库里这 5 个文件加入 target (右键 MingceWidget 组 → Add Files):
     - `MingceWidgetBundle.swift` (@main 入口, 若与模板冲突保留仓库版)
     - `SharedStore.swift`
     - `MingcePriceWidget.swift`
     - `MingceWhaleWidget.swift`
     - `WatchLiveActivity.swift`
4. MingceWidget target → Signing & Capabilities:
   - Team 选与主 App 相同的 `C4Y8S5CHFT`
   - + Capability → **App Groups** → 勾 `group.com.hkmc.noahsark.shared`
     (entitlements 文件已在仓库, Xcode 会自动关联)
5. Runner target → Signing & Capabilities: 确认 App Groups 里已有
   `group.com.hkmc.noahsark.shared` (Runner.entitlements 已改好, Xcode 打开自动识别)
6. MingceWidget target → General → Minimum Deployments: iOS 15.0
   (Live Activity 代码已 @available(iOS 16.1) 门控)
7. `flutter build ios --release --dart-define=API_BASE=https://shipapi.bdxapi.com` 验证编译

## 真机自验清单

- 桌面长按加小组件: 「明策行情」「巨鲸异动」两个出现, 打开过 App 后有数据
- App 内行情详情页 → 心跳图标 (盯盘): 锁屏出现实时价横幅, 服务端 60s 一轮 APNs 更新; 灵动岛长按展开
- 盯盘需登录 (activity push token 绑账号); 未登录点按会提示
- 分享按钮 → 生成 K线卡片 PNG → 系统分享面板

## 故障排查

- 小组件无数据: 设置 → 通用 → 后台 App 刷新 无需开; 数据是 App 前台时写入
  App Group 的, 至少开一次 App 且等 30s (五币首帧齐了才写)
- Live Activity 不更新: 盯盘开启后等 ~10s 拿 push token, 之后服务端 60s 一轮;
  服务端日志看 `live_activity_error` / `apns_live_activity_failed`
- 编译报 `WatchActivityAttributes` 重定义: 模板 Swift 文件没删干净

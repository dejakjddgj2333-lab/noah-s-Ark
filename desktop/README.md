# Noah's Ark 桌面终端 (desktop/)

Flutter 桌面版市场情报终端，视觉对齐 `web-terminal`（Obsidian Precision 设计规范，见 `../stitch_ref/web_terminal/DESIGN.md`）。平台：Windows + macOS。

## 开发

```bash
flutter pub get
flutter run -d windows    # 本机调试
```

后端直连 `https://shipapi.bdxapi.com/api`（唯一线上后端，无本地服务）。测试账号 test01 / Test123456。

## 打包

- Windows：`flutter build windows --release` → `build/windows/x64/runner/Release/`
- macOS：需在 Mac 上执行 `flutter build macos --release`（本仓库仅保留 macos/ 工程文件；签名与公证走 Xcode）

## 结构

- `lib/theme.dart` — 设计令牌（颜色/字体/metrics，唯一来源）
- `lib/api/api_client.dart` — Dio 客户端，端点与 web-terminal `src/api/index.js` 一一对应
- `lib/state/auth_store.dart` — token/用户持久化（shared_preferences）
- `lib/widgets/kit.dart` — 共享组件（McCard/McButton/McInput/McBadge/McStat…）
- `lib/widgets/shell.dart` — 240px 侧栏 + 56px 顶栏外壳
- `lib/pages/` — login + overview/market/news/chat/assets 五个核心页
- 字体内置 assets/fonts（Inter/SpaceGrotesk/JetBrainsMono），不用 google_fonts

约定：数字一律 JetBrains Mono + 右对齐；publish_at 等后端时间为北京时间裸字符串，用 `Fmt.parseServerTime`；禁 emoji/纯黑/紫渐变；禁「交易/合约/杠杆」字样。

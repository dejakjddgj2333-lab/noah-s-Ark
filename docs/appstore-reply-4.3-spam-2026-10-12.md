# Guideline 4.3(a) Spam 申诉回复 (2026-10-12)
Submission 188809b4 · Version 1.0.0 (10) · iPad Air 11 M3

在 App Store Connect 回复审核团队时粘贴以下内容。

---

## 中文

尊敬的审核团队，您好：

关于 Guideline 4.3(a) 的反馈，我们想说明：本 App 为我们团队独立开发的产品，未购买或使用任何第三方 App 模板，源码与后端服务均为自主编写，与其他开发者的 App 不存在共享二进制或套用模板的情况。

**独立开发证据：**

1. 客户端基于 Flutter 框架从零开发，服务端为自研 Python (FastAPI) 系统，含独立的后台管理系统（Vue 3），三者构成完整闭环。我们可以提供完整的 Git 提交历史（长期渐进式迭代记录，非一次性导入）、服务端 API 文档与数据库设计文档备查。
2. App 内数据来自我们自建的服务端聚合：行情与 K 线数据由自有服务器实时接入 Binance、Hyperliquid 等公开行情源，经服务端清洗、缓存后下发，并非抓取或包装其他 App 的内容。

**差异化功能（与常见行情类 App 的区别）：**

1. **巨鲸异动速递 / 巨鲸雷达**：自建链上与交易所大额成交监控系统（Hyperliquid 与 Binance 双数据源实时 WebSocket 聚合、去重与阈值过滤），实时推送大额成交异动，该功能为本 App 独有实现。
2. **板块轮动动能看板**：自研的板块强弱动量计算与可视化。
3. **爆仓数据看板**：聚合全市场爆仓统计与明细。
4. **社区聊天 + 内容审核体系**：内置完整的内容审核后台（用户举报、删除、封禁流程）。
5. 完整支持简体中文、繁体中文、英语、日语、韩语、西班牙语、葡萄牙语、印地语 8 种语言的本地化。

**元数据方面：** 我们已检查应用名称「明策量化」、图标与截图均为自主设计；如审核团队认为某些截图或描述与其他 App 相似，请指出具体位置，我们将立即调整。

我们理解苹果对马甲包的管控，也重视账号信誉。如仍有疑问，我们愿意配合提供源代码仓库记录、服务器部署信息或进行电话沟通。恳请重新审核本 App，感谢。

## English

Dear App Review Team,

Thank you for the feedback on Guideline 4.3(a). This app is independently developed by our team — no third-party template was purchased or used, and it shares no binary, source code, or assets with apps from other developers.

Evidence of independent development:

1. The Flutter client, Python (FastAPI) backend, and Vue 3 admin console were all built from scratch. We can provide the full Git commit history (long-term incremental development, not a one-time import), API documentation, and database design for verification.
2. All data is served by our own servers: market data and charts are streamed from public sources (Binance, Hyperliquid) with our own processing and caching — not scraped or repackaged from any other app.

Differentiating features:

1. Whale Alert / Whale Radar: self-built large-transaction monitoring aggregating real-time WebSocket streams from Hyperliquid and Binance, with deduplication and threshold filtering.
2. Sector Rotation Momentum Board: our own sector strength computation and visualization.
3. Liquidation Dashboard: market-wide liquidation statistics and details.
4. Community chat with a full moderation system (reporting, removal, bans).
5. Full localization in 8 languages (zh-CN, zh-TW, en, ja, ko, es, pt, hi).

The app name "明策量化", icon, and screenshots are originally designed by us. If any metadata appears similar to other apps, please point it out and we will adjust immediately. We are happy to provide repository records, server deployment details, or schedule a call. We sincerely ask you to re-review this app. Thank you.

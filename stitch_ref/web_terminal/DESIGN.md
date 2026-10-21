# Design System: 明策 MINGCE Web 终端

> 桌面宽屏网页版市场情报终端。与 App / 邀请落地页同一视觉血统：
> 「Obsidian Precision」—— 深夜交易室的曜石黑 + 钴蓝，等宽数字，细网格，克制专业。
> 本规范面向桌面浏览器（1440px 基准），暗色唯一主题。

## 1. Visual Theme & Atmosphere

金融情报终端气质的深色 Web 应用。氛围是**专业操盘台**：信息密度高但不拥挤，
数据用等宽字体精确对齐，钴蓝只出现在关键路径（主按钮、选中态、上涨数据之外的唯一强调色）。

- **Density:** 8 (Desktop Pro —— 高密度，卡片间距紧凑，表格为主)
- **Variance:** 4 (Balanced —— 工具型应用以效率为先，允许功能区错落)
- **Motion:** 3 (Functional —— 仅悬停提亮、 tab 切换过渡，不要装饰动画)

## 2. Color Palette & Roles

| 名称 | Hex | 角色 |
|---|---|---|
| **Canvas Obsidian** | `#070D1C` | 页面主背景 |
| **Surface Slate** | `#0D1528` | 侧栏 / 面板填充 |
| **Card Navy** | `#121D34` | 卡片、表格行 |
| **Card Navy High** | `#1A2742` | 悬停态、选中行、徽章底 |
| **Hairline** | `#34415E` | 1px 结构描边、表格分隔线 |
| **Cobalt Accent** | `#2E5CFF` | 唯一主 accent：主按钮、选中 tab、链接 |
| **Cobalt Soft** | `#82A4FF` | accent 浅阶：图标、强调数字、聚焦环 |
| **Ink White** | `#F0F0FF` | 主文字 |
| **Steel Muted** | `#9EA0B2` | 次要文字、表头、元信息 |
| **Bull Green** | `#00E388` | 上涨 / 正向 / 在线状态 |
| **Bear Red** | `#FF5F6D` | 下跌 / 负向 / 危险操作 |
| **Amber Warn** | `#F7B733` | 警告、待处理 |

约束：禁止纯黑 `#000000`；禁止紫色/霓虹渐变；accent 只有 Cobalt。
涨跌配色固定 Bull Green / Bear Red，不要另创新色。

## 3. Typography Rules

- **Display / 页面标题：** `Space Grotesk`（中文回退 PingFang SC / Microsoft YaHei），
  字重 600–700，收紧字距。
- **Body / 正文表格：** `Inter`，13–14px 为主，行高 1.5–1.6。
- **Mono / 一切数字：** `JetBrains Mono` —— 价格、涨跌幅、时间戳、数量、编号一律等宽，
  右对齐。这是「终端感」的核心。
- 禁用 serif；禁用把 Inter 用在页面大标题。

## 4. Layout & Navigation

- **整体框架：** 左侧固定导航栏（240px，Surface Slate 底，含 logo、主导航、底部用户区）+
  右侧内容区（Canvas 底，内容最大宽度不限但左右留白 24–32px）。
- **顶部条：** 内容区顶部 56px 条：面包屑/页面标题 + 全局搜索框 + 通知铃铛 + 用户头像。
- **卡片：** Card Navy 底 + 1px Hairline 描边 + 12px 圆角；卡片内边距 16–20px。
  数据卡片网格 12 列，常用 3/4/6 列跨。
- **表格：** 表头 Steel Muted 小字大写感，行高 44px，行分隔 Hairline，悬停行 Card Navy High。
  数字列右对齐等宽。
- **Tab：** 下划线式，选中 Cobalt Accent 2px 下划线 + Ink White 文字，未选中 Steel Muted。

## 5. Components

* **主按钮：** Cobalt 实心填充白字，圆角 8px，高 36–40px；一页一个主按钮。
* **次按钮：** 幽灵描边（Surface 底 + Hairline + Cobalt Soft 文字）。
* **危险按钮：** Bear Red 描边或实心，仅用于封号/删除/拒绝。
* **输入框：** Surface 底 + Hairline 描边，聚焦时 Cobalt 描边 + 低透明辉光；高 40px。
* **状态徽章：** 小胶囊，语义色 12% 透明底 + 语义色文字（Bull=在线/上涨，Amber=待处理，Red=失败）。
* **K线/图表区：** 图表卡片内嵌，坐标轴 Steel Muted 10px，网格线 Hairline 30% 透明，
  阳线 Bull Green / 阴线 Bear Red，面积图用 Cobalt 20% 透明渐变填充。
* **图标：** 线性 icon（1.5px  stroke），不用 emoji。
* **头像：** 圆形 32px，首字母占位，Card Navy High 底。

## 6. Anti-Patterns (Banned)

- 不用 emoji / serif / 纯黑 / 紫色霓虹渐变
- 不用居中大 Hero 营销式排版（这是工具，不是官网）
- 不用虚假精确数字（99.99%）与占位名（John Doe / Acme）
- 不用 AI 腔文案（赋能 / 一站式 / Seamless / Elevate）
- 不用「交易/合约/杠杆」敏感字眼（用「行情/情报/市场情报」，上架审核口径）
- 表格不要用斑马纹，用 Hairline 行分隔
- 不要彩色渐变卡片背景

## 7. 页面语气

全部中文界面 + 英文小标签点缀（JetBrains Mono 大写小字，如 `MARKET`、`WHALE ALERT`）。
文案短、直、像仪器读数。示例：「24H 涨跌」「净流入」「确认中 3/12」。

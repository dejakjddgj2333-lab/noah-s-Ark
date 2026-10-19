# Design System: 明策 MINGCE 邀请落地页

> 供 Google Stitch 生成屏幕的语义化设计规范。目标页：与 App 内分享海报配套的邀请落地页
> （`https://shipapi.bdxapi.com/?invite=CODE`），承接收邀者，引导下载/打开 App 并自动带出邀请码。

## 1. Visual Theme & Atmosphere

金融情报终端气质的深色邀请落地页 —— 「Obsidian Precision」。
氛围是**深夜交易室的专业与克制**：曜石黑画布上泛着钴蓝色辉光，等宽数字与细网格传达
「数据精密仪器」的可信感。不喧闹、不促销腔，像一份递到手里的私密研报。

- **Density:** 6 (Daily App Balanced —— 信息密度适中，营销页留白充足)
- **Variance:** 6 (Offset Asymmetric —— Hero 左对齐，非居中；下方功能区错落)
- **Motion:** 5 (Fluid CSS —— 微妙浮动、网格呼吸、按钮弹性，不炫技)

整体调性参考 App 内 `_InvitePosterView` 海报：深底 + 网格 + 顶部径向辉光 + 钴蓝点缀，
落地页是这张海报在 Web 上的「展开版」。

## 2. Color Palette & Roles

| 名称 | Hex | 角色 |
|---|---|---|
| **Canvas Obsidian** | `#070D1C` | 页面主背景，深夜曜石蓝黑（非纯黑） |
| **Surface Slate** | `#0D1528` | 卡片/容器填充 |
| **Card Navy** | `#121D34` | 次级卡片、邀请码底块 |
| **Card Navy High** | `#1A2742` | 徽章/标签容器 |
| **Hairline** | `#34415E` | 1px 结构描边、分隔线 |
| **Cobalt Accent** | `#2E5CFF` | 唯一主 accent —— 主 CTA 填充、强调、聚焦环 |
| **Cobalt Soft** | `#82A4FF` | accent 的浅阶 —— 大标题高光、邀请码数字、图标 |
| **Ink White** | `#F0F0FF` | 主文字，带一丝蓝调的暖白 |
| **Steel Muted** | `#9EA0B2` | 次要文字、说明、元信息 |
| **Bull Green** | `#00E388` | 仅用于「在线/有效」状态点等极少语义场景 |

约束：单一 accent（Cobalt），饱和度适中；**禁止纯黑 `#000000`**；
辉光仅用 Cobalt 的低透明度径向渐变，**禁止紫色/霓虹蓝渐变**。

## 3. Typography Rules

- **Display / 标题：** `Space Grotesk` —— 收紧字距（letter-spacing -0.4px），
  靠字重（700）与颜色分层，不靠堆砌超大字号。中文主标同样收紧。
- **Body / 正文：** `Inter` —— 行高 1.6–1.8，单行不超过 65 字符，次要信息用 Steel Muted。
- **Mono / 数字与元信息：** `JetBrains Mono` —— 邀请码、英文小标签（如 `MARKET INTELLIGENCE`、
  `INVITE`）、统计数字一律等宽，强化「终端精密感」。
- **禁用：** 不要把 Inter 用在 Display 大标题（用 Space Grotesk）；落地页属营销/产品 UI，
  **不使用任何 serif 字体**。

## 4. Component Stylings

* **主按钮（下载/打开 App）：** 实心 Cobalt Accent 填充，白字，圆角约 10px，无外部辉光；
  按下时向下 1px 位移的 tactile 反馈。一页只允许**一个主 CTA**（下载/打开 App）。
* **次按钮（复制邀请码）：** 幽灵/描边样式 —— Surface 底 + Hairline 描边 + Cobalt Soft 图标。
* **邀请码块：** Card Navy 底 + 低透明 Cobalt 描边，内部 JetBrains Mono 大号 Cobalt Soft 数字，
  字距拉开（letter-spacing 3px）。这是页面视觉锚点之一。
* **功能卡片：** 仅当需要表达层级时用卡片；采用 2 列错落（zig-zag）或不对称网格，
  **禁止「三个等大卡片横排」**。高密度区可用 Hairline 顶部分隔线替代卡片。
* **徽章/标签：** Card Navy High 底 + Hairline 描边的小胶囊，内含 5px 状态圆点 +
  JetBrains Mono 小写英文标签（如 `INVITE`）。
* **顶部品牌条：** 圆角 logo + 「明策 MINGCE」中英标题 + 右侧状态徽章，与海报头部一致。
* **加载/空态：** 不使用通用转圈 spinner；邀请码未取到时用骨架条占位。

## 5. Layout Principles

- **Hero：** 左对齐、非对称布局（Variance>4 故**禁止居中 Hero**）。左侧为标题/副文案/邀请码/主 CTA；
  右侧或下方放置一个「App 界面预览卡」或「邀请海报缩略」作为视觉平衡。元素各自占位、**绝不重叠**。
- **结构分区：** 顶部品牌条 → Hero（含邀请码 + CTA）→ 三大功能条（图标+短句，Hairline 分隔，
  非等大卡片）→ 下载/打开引导区 → 页脚版权。
- **网格背景：** 全页铺一层极低透明度（≈0.12）的细网格（24px 步进），叠加顶部 Cobalt
  径向辉光 —— 与海报 `_GridPainter` 同款，营造仪器感。
- **容器：** 最大宽度约束（约 1100px）居中，内部留白充足（垂直区间 `clamp(3rem, 8vw, 5rem)`）。
- **响应式：** <768px 全部单列堆叠；邀请码块与 CTA 全宽；不出现横向滚动。

## 6. Motion & Interaction

- **弹性物理：** 所有可交互元素用 spring 感（近似 cubic-bezier(0.34,1.3,0.64,1)），不用线性缓动。
- **常驻微动效：** Hero 的 Cobalt 辉光缓慢呼吸（opacity 微浮 6s 循环）；邀请码块轻微
  float；功能图标 hover 时 Cobalt Soft 提亮。仅 `transform`/`opacity`，硬件加速。
- **级联进场：** 页面元素自上而下错峰淡入（waterfall，间隔 60–90ms）。
- **核心交互：** 页面加载读取 URL `?invite=CODE` 并填入邀请码块；「打开 App」优先尝试
  `mingce://invite?invite=CODE` 深链唤端，未安装则回落到下载引导；「复制邀请码」一键复制并给
  出内联成功反馈（不弹系统 alert）。

## 7. Anti-Patterns (Banned)

- 不使用 emoji（图标用线性 icon）
- Display 标题不用 Inter（用 Space Grotesk）；不用任何 serif
- 不用纯黑 `#000000`（用 Canvas Obsidian `#070D1C`）
- 不用霓虹/紫色渐变辉光；accent 只有一个 Cobalt
- 不用「三个等大卡片横排」的功能区
- 不用居中 Hero（本页 Variance 6）
- 不用虚假圆整数字（`99.99%`、`50%`）与通用占位名（John Doe / Acme / Nexus）
- 不用 AI 腔文案（Elevate / Seamless / Unleash / Next-Gen / 赋能 / 一站式）
- 不用「Scroll to explore / 下滑探索」+ 弹跳箭头等 filler
- 不用外部图床占位图（logo 用本地 `logo.png`；预览图用 picsum 或本地资源）
- 文案避免「交易/合约/杠杆」等敏感字眼（沿用 App 上架审核口径，用「行情/情报/市场情报」）

## 8. 落地页必备内容要素（供生成时填充真实文案）

- 品牌：明策 MINGCE / MARKET INTELLIGENCE
- 主标：突出「好友邀请你来」+ 产品价值主张（市场情报/数据洞察）
- 副标：一句话说明 + 强调专属邀请码已就绪
- 邀请码块：占位码 `MC8K2X`（JetBrains Mono 大字），运行时由 URL 参数替换
- 三大功能（与海报 `_featureStrip` 对齐）：行情洞察 / 巨鲸追踪 / 语音播报
- 主 CTA：「下载 / 打开 App」；次 CTA：「复制邀请码」
- 页脚：© 明策 MINGCE

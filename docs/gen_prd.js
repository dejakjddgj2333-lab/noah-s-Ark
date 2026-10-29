const fs = require('fs');
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  Header, Footer, AlignmentType, LevelFormat, HeadingLevel,
  BorderStyle, WidthType, ShadingType, PageNumber, TableOfContents
} = require('docx');

const FONT = { ascii: "Arial", hAnsi: "Arial", eastAsia: "Microsoft YaHei" };
const CONTENT_W = 9026; // A4, 1 inch margins

const children = [];

// ---------- helpers ----------
const p = (text, opts = {}) => children.push(new Paragraph({
  spacing: { after: 120, line: 320 },
  children: [new TextRun({ text, ...opts })]
}));

const h1 = t => children.push(new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun(t)] }));
const h2 = t => children.push(new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun(t)] }));
const h3 = t => children.push(new Paragraph({ heading: HeadingLevel.HEADING_3, children: [new TextRun(t)] }));

const bullet = (t, level = 0) => children.push(new Paragraph({
  numbering: { reference: "bullets", level },
  spacing: { after: 60, line: 300 },
  children: [new TextRun(t)]
}));

// bold-lead bullet: "标签：内容"
const kv = (lead, rest, level = 0) => children.push(new Paragraph({
  numbering: { reference: "bullets", level },
  spacing: { after: 60, line: 300 },
  children: [new TextRun({ text: lead, bold: true }), new TextRun(rest)]
}));

const note = t => children.push(new Paragraph({
  spacing: { after: 120, line: 300 },
  children: [new TextRun({ text: t, italics: true, color: "7F7F7F", size: 19 })]
}));

function table(headers, rows, widths) {
  const border = { style: BorderStyle.SINGLE, size: 1, color: "BFBFBF" };
  const borders = { top: border, bottom: border, left: border, right: border };
  const margins = { top: 60, bottom: 60, left: 100, right: 100 };
  const cell = (text, w, isHeader) => new TableCell({
    borders,
    width: { size: w, type: WidthType.DXA },
    shading: isHeader ? { fill: "1F3864", type: ShadingType.CLEAR, color: "auto" } : undefined,
    margins,
    children: [new Paragraph({
      children: [new TextRun({ text, bold: isHeader, color: isHeader ? "FFFFFF" : "000000", size: 19 })]
    })]
  });
  children.push(new Table({
    width: { size: widths.reduce((a, b) => a + b, 0), type: WidthType.DXA },
    columnWidths: widths,
    rows: [
      new TableRow({ tableHeader: true, children: headers.map((h, i) => cell(h, widths[i], true)) }),
      ...rows.map(r => new TableRow({ children: r.map((c, i) => cell(c, widths[i], false)) }))
    ]
  }));
  children.push(new Paragraph({ spacing: { after: 120 }, children: [] }));
}

// ---------- 封面标题 ----------
children.push(new Paragraph({
  alignment: AlignmentType.CENTER,
  spacing: { before: 600, after: 200 },
  children: [new TextRun({ text: "明策（Mingce）App 功能需求文档", bold: true, size: 44 })]
}));
children.push(new Paragraph({
  alignment: AlignmentType.CENTER,
  spacing: { after: 400 },
  children: [new TextRun({ text: "UI 重设计专项  |  V1.0  |  2026-10-21", color: "595959", size: 22 })]
}));
children.push(new Paragraph({
  alignment: AlignmentType.CENTER,
  spacing: { after: 600 },
  border: { bottom: { style: BorderStyle.SINGLE, size: 6, color: "1F3864", space: 1 } },
  children: [new TextRun({ text: "读者：UI / 视觉设计师（兼供产品、前端参考）", color: "595959", size: 20 })]
}));

children.push(new TableOfContents("目录", { hyperlink: true, headingStyleRange: "1-2" }));
children.push(new Paragraph({ spacing: { after: 200 }, children: [] }));

// ---------- 1 文档说明 ----------
h1("1. 文档说明");
h2("1.1 重设计原则");
bullet("功能与数据逻辑不变，仅重构视觉风格、布局与交互呈现；");
bullet("新设计需建立自有品牌风格，避免与主流交易所/行情类 App（如 OKX 风格）视觉雷同；");
bullet("需覆盖第 3 章页面清单中的全部页面，并包含各页面的加载态、空态、错误态；");
bullet("需同时输出 iOS 与 Android 两端的适配方案（同一套设计，注意安全区差异）。");
h2("1.2 阅读指引");
p("第 2 章为产品概述；第 3 章为信息架构与页面清单总表（UI 交付的核心范围）；第 4 章为逐页面功能需求详述；第 5 章为全局设计要求；第 6 章为合规与可见性说明；第 7 章为术语表。");

// ---------- 2 产品概述 ----------
h1("2. 产品概述");
kv("产品定位：", "加密货币行情数据 + 行业资讯 + 社区聊天 + 理财返佣 的综合平台（品牌名：明策 Mingce）。");
kv("平台形态：", "iOS / Android 移动 App（Flutter 开发），另有桌面 Web 端。");
kv("数据来源：", "OKX、Binance、Bybit、CoinGlass、Hyperliquid、DefiLlama 等行情与链上数据源，行情以 WebSocket 实时推送为主。");
kv("多语言：", "支持 8 种语言：简体中文（默认）、繁体中文、English、日语、韩语、西班牙语、葡萄牙语、印地语，切换即时生效。");
kv("重要说明：", "本 App 不含币币/合约下单交易功能，也不含股票/IPO 功能；资产相关功能为 USDT 充值/提现、理财产品申购与邀请返佣体系（详见第 6 章合规说明）。");
h2("2.1 核心能力一览");
bullet("实时行情：主流币种榜单、K线、盘口、逐笔成交、资金费率、持仓量；");
bullet("数据监控：多空爆仓监控、巨鲸大额成交雷达、资金费率矩阵、多维市场指数仪表盘；");
bullet("资讯体系：快讯/资讯/公告、行业政策、宏观日历、评论互动；");
bullet("社区社交：私聊/群聊、语音/图片/视频消息、1:1 WebRTC 语音通话、好友体系；");
bullet("资产体系：双账户（本金/收益）、USDT 多网络充提、理财产品、VIP 等级、三代团队返佣、邀请海报。");

// ---------- 3 信息架构 ----------
h1("3. 信息架构与页面清单");
h2("3.1 底部导航（4 个主 Tab）");
table(
  ["Tab", "名称", "说明"],
  [
    ["1", "首页", "顶部 6 个数据板块子 Tab 横滑切换（见 3.2）"],
    ["2", "资讯", "快讯/资讯/公告时间线 + 突发头条 + 宏观日历入口"],
    ["3", "聊天", "会话列表，带未读消息与好友请求动态角标；未登录显示登录引导占位"],
    ["4", "我的", "资产总览 + 理财中心 + 合伙人分佣 + 设置入口；未登录显示登录引导占位"],
  ],
  [900, 1400, 6726]
);
p("全局共享 Header：品牌 Logo + 数据同步状态标识 + 用户头像（点击进用户中心，未登录进登录页）。");
h2("3.2 首页子板块（6 个）");
p("综合 / 行情 / 终端 / 爆仓 / 巨鲸 / 费率 —— 顶部横向 Tab 切换，各板块功能详见第 4 章。");
h2("3.3 页面清单总表（共 40 个页面）");
note("下表为本次 UI 重设计需交付的全部页面范围。");
table(
  ["模块", "页面", "功能说明"],
  [
    ["首页", "综合看板", "情绪指数、24H爆仓、费率、山寨季指数、市场全景、巨鲸速递、主流资产速览"],
    ["首页", "行情榜单", "主流币 Top10 榜单、排序切换、板块筛选、热度指标与热力图"],
    ["首页", "终端仪表盘", "情绪/费率/OI/爆仓/稳定币/多空比/山寨季/市占率 多维指数"],
    ["首页", "爆仓监控", "24H 总爆仓、分时段、交易所统计、实时爆仓 feed、币种过滤"],
    ["首页", "巨鲸雷达", "大额成交时间线、链上流动性、阈值过滤、推送订阅设置"],
    ["首页", "资金费率", "加权费率指数、费率矩阵、结算倒计时、BTC 费率 7 日曲线"],
    ["行情", "行情详情", "实时价格、24H 统计、K线/盘口/逐笔成交、费率倒计时、持仓量、分享卡片"],
    ["行情", "行情预警", "新建预警（涨破/跌破、目标价/涨跌幅）、预警列表管理"],
    ["行情", "宏观日历", "按日期切换的宏观事件列表与事件详情"],
    ["资讯", "资讯列表", "突发头条、资讯/快讯/公告/行业政策分类、分页与自动刷新"],
    ["资讯", "资讯详情", "正文、点赞/评论（楼中楼）/收藏/分享/查看原文"],
    ["聊天", "会话列表", "全部/私聊/群聊过滤、搜索、未读角标、在线状态"],
    ["聊天", "聊天房间", "文字/图片/语音/视频消息、回复、表情表态、已读回执、通话入口"],
    ["聊天", "好友页", "好友/请求/添加 三 Tab，搜索加好友、接受/拒绝申请"],
    ["聊天", "发起群聊", "群名输入 + 好友多选创建"],
    ["聊天", "群信息", "群名修改（群主）、成员管理、拉人/移除"],
    ["聊天", "语音通话", "1:1 WebRTC 全屏通话页：呼叫/响铃/通话中/结束四态"],
    ["聊天", "媒体查看", "全屏图片缩放查看、视频播放"],
    ["聊天", "拉黑管理", "已拉黑用户列表、取消拉黑"],
    ["我的", "我的/资产首页", "身份卡、资产总览、理财中心入口、合伙人分佣卡、快捷功能、账号安全"],
    ["资产", "充值", "USDT 多网络选地址（4 网络）、二维码、充值记录、txid 补单"],
    ["资产", "提现", "账户/网络选择、金额地址、实时费用报价、确认提交"],
    ["资产", "钱包连接支付", "WalletConnect v2 连接钱包、金额、签名、广播、入账"],
    ["资产", "钱包矩阵", "各链专属充值地址一览 + 各链累计充值统计"],
    ["资产", "资金页", "资金明细/收益结算/佣金/提现记录/等级变动 五类流水"],
    ["理财", "理财产品", "产品列表/详情/购买（日化收益、期限、门槛、首购提示）"],
    ["理财", "我的订单", "生效中/已完成订单、锁定 VIP 加成、结算安排、到期时间"],
    ["理财", "VIP 等级", "有效持仓、当前等级、收益加成、升级差额、VIP0-10 等级表"],
    ["理财", "我的团队", "三代人数/持仓、团队等级、返佣比例、升级差额"],
    ["理财", "分佣中心", "累计佣金、三代返佣比例、佣金明细按代数筛选"],
    ["理财", "邀请好友", "邀请码/链接复制、海报生成分享、上级绑定、补填邀请码"],
    ["账户", "登录/注册", "同一页切换：用户名密码登录；邮箱+验证码+邀请码注册"],
    ["账户", "用户中心", "个人资料/安全设置/偏好设置 三 Tab"],
    ["账户", "修改密码", "原密码 + 新密码 + 确认"],
    ["账户", "资金密码", "设置（需登录密码）/ 修改"],
    ["账户", "谷歌验证 2FA", "绑定（显示密钥）/ 解绑（验证码）"],
    ["账户", "防钓鱼码", "设置 / 清除"],
    ["账户", "设备管理", "登录设备列表、远程下线"],
    ["账户", "语言选择", "8 种语言，选中即生效"],
    ["账户", "用户协议/隐私政策", "后端富文本渲染"],
    ["账户", "登录引导占位", "聊天/我的 Tab 未登录占位页（引导登录）"],
  ],
  [1100, 2100, 5826]
);

// ---------- 4 功能详述 ----------
h1("4. 功能需求详述");

h2("4.1 登录 / 注册");
kv("登录：", "用户名 + 密码；登录同时上报设备名与平台（用于设备管理）。");
kv("注册：", "用户名 + 密码（两次确认）+ 邮箱 + 邮箱验证码（60 秒倒计时重发）+ 邀请码（选填）。");
kv("协议：", "注册必须勾选同意《用户协议》与《隐私政策》，App 内打开富文本协议页。");
kv("邀请唤起：", "支持邀请链接/海报扫码唤起 App（mingce:// scheme 与落地页），自动填入邀请码并切换到注册。");
kv("登录后行为：", "建立聊天长连接、上报推送 token、同步昵称头像。");
note("暂不支持手机号登录与第三方（Google/Apple）登录。");

h2("4.2 首页 · 综合看板");
bullet("恐惧贪婪情绪指数卡：数值、情绪标签、环比变化；");
bullet("24H 爆仓迷你卡：多空比例条；");
bullet("资金费率迷你卡 + 山寨季指数；");
bullet("市场全景横幅：总市值、24H 涨跌、成交量、多空人数占比；");
bullet("巨鲸异动速递列表；");
bullet("主流资产速览（BTC/ETH/SOL/SUI，实时推送，本地缓存冷启动秒显）；");
bullet("首屏骨架屏加载；接口失败时数据显示“--”，不展示假数据。");

h2("4.3 首页 · 行情榜单");
bullet("主流币榜单（BTC/ETH/SOL/XRP/DOGE/ADA/AVAX/LINK/NEAR/SUI 等白名单，按 24H 名义成交额取 Top10）；");
bullet("排序切换：成交额 / 涨幅榜 / 跌幅榜；");
bullet("板块分类筛选：全部、Layer 1、DeFi、AI Agent、Meme、Solana 生态、RWA；");
bullet("每行展示：价格、涨跌幅、24H 高/低、分时走势小图（sparkline）、状态标签（突破/放量/横盘/弱势）；");
bullet("市场热度指标 + 板块热力图；");
bullet("点击币种进入行情详情页。");

h2("4.4 首页 · 终端仪表盘");
bullet("恐惧贪婪指数 + 近 8 日历史（昨日/上周对比）；");
bullet("资金费率加权值、未平仓合约 OI（BTC+ETH 永续名义额）；");
bullet("24H 爆仓总额/笔数、稳定币总流通量；");
bullet("多空人数比、山寨季指数、BTC/ETH/其他市占率分布；");
bullet("主流资产列表（行情 + 费率 + 走势）。");

h2("4.5 首页 · 爆仓监控");
bullet("24H 总爆仓卡：总额 / 多单 / 空单 / 笔数；");
bullet("分时段统计（1h/4h/12h）与监控时段切换；");
bullet("交易所统计（Binance/Bybit/OKX 等，时段可切）；");
bullet("实时爆仓 feed：轮询刷新、可设最小金额过滤、币种快捷过滤（全部/BTC/ETH…）；");
bullet("爆仓热力分布展示。");

h2("4.6 首页 · 巨鲸雷达");
bullet("Hyperliquid 大额成交实时异动时间线；");
bullet("链上流动性总览；");
bullet("分类筛选 + 预警阈值（美元金额）过滤；");
bullet("巨鲸推送订阅：开关 + 最小金额阈值设置（默认 $500,000）。");

h2("4.7 首页 · 资金费率");
bullet("全网加权费率指数（APY / 8H 费率）；");
bullet("费率矩阵：正费率/负费率/异动激增筛选，多合约币种，可展开更多；");
bullet("下次 8H 结算倒计时（UTC 00/08/16 整点）；");
bullet("BTC 费率近 7 日曲线 + 温度条游标；");
bullet("市场健康标签：多头过热/多头健康/均衡/空头温和/空头拥挤。");

h2("4.8 行情详情页");
bullet("实时价格：接口首帧 + WebSocket 推送，断流自动接口兜底；");
bullet("24H 统计：开/高/低/量/名义成交额/涨跌幅；");
bullet("三 Tab：K线（15m/1H/4H/1D，支持拖拽平移与捏合缩放）、盘口（5 档深度）、逐笔成交（最多 50 条）；");
bullet("资金费率 + 下次结算倒计时（永续）；持仓量卡片（数据缺失时整卡隐藏）；");
bullet("页内下拉快速切换交易对；");
bullet("分享卡片生成；iOS 灵动岛实时价格（Live Activity）。");

h2("4.9 行情预警");
bullet("新建预警：选择交易对、方向（涨破/跌破）、目标价或涨跌幅百分比；");
bullet("预警列表管理：查看、启停、删除。");

h2("4.10 宏观日历");
bullet("按北京时间日期切换浏览宏观事件列表；");
bullet("事件详情查看（重要性、前值/预期/公布值等）。");

h2("4.11 资讯");
bullet("突发头条横幅：展示全站最新一条突发；");
bullet("分类 Tab：资讯 / 快讯 / 公告 / 行业政策（监管、政策、SEC、法案、央行、合规等关键词过滤）；");
bullet("时间线列表：分页加载（每页 20 条）、60 秒静默自动刷新；");
bullet("利好/利空情绪标签；按当前语言加载对应资讯，切换语言自动重载；");
bullet("宏观日历入口。");
h3("4.11.1 资讯详情");
bullet("正文富文本渲染；");
bullet("点赞、收藏、分享、查看原文（外链浏览器）；");
bullet("评论：分页加载 + 楼中楼回复。");

h2("4.12 聊天 · 会话列表");
bullet("全部/私聊/群聊过滤、会话搜索；");
bullet("未读消息角标（与底部导航联动）、好友请求角标；");
bullet("好友在线状态显示（30 秒轮询）；");
bullet("长按删除会话/退出群聊；长连接实时更新。");

h2("4.13 聊天 · 聊天房间");
bullet("消息类型：文字、图片、语音（按住说话、上滑取消）、视频；");
bullet("消息操作：回复、表情表态（👍❤️🔥😂😮😢）、复制；");
bullet("发送状态：乐观发送（发送中→成功/失败可重试）；");
bullet("私聊已读回执（双勾）；本地消息库秒开 + 服务器合并，向上翻页加载历史；");
bullet("$币种标签点击跳转对应行情详情；");
bullet("私聊入口：1:1 语音通话、拉黑、举报。");
h3("4.13.1 好友 / 群组");
bullet("好友页三 Tab：好友列表 / 好友请求（接受/拒绝）/ 添加好友（搜索用户）；");
bullet("发起群聊：群名输入 + 好友多选；");
bullet("群信息：群主改群名、成员列表、移除成员、拉人进群。");
h3("4.13.2 语音通话");
bullet("1:1 WebRTC 语音通话全屏页：主叫中/被叫响铃/通话中/已结束 四态；");
bullet("静音、扬声器切换、通话计时；占线自动拒绝。");

h2("4.14 我的 / 资产首页");
bullet("身份卡：昵称、头像、邀请码（点击复制）；");
bullet("资产总览卡：总资产/可用/持仓/处理中；入口：充值、提现、钱包矩阵、收益转本金；");
bullet("理财中心入口：理财产品、我的 VIP、我的团队、我的订单、资金明细、提现；");
bullet("合伙人分佣卡：累计佣金、今日佣金、有效邀请人数、团队等级、专属邀请码，邀请好友/分佣中心入口、最近返佣记录；");
bullet("快捷功能：行情预警、设备管理、修改密码、设置；");
bullet("账号安全卡：邮箱绑定状态等。");

h2("4.15 充值 / 提现 / 钱包");
h3("4.15.1 充值");
bullet("USDT 链上充值，支持 TRC20 / ERC20 / BEP20 / Arbitrum 四网络；");
bullet("专属充值地址 + 二维码展示；最低 10 USDT，12 个区块确认入账；");
bullet("充值记录列表；txid 自助补单；");
bullet("支持 WalletConnect v2 连接钱包直接支付（连接→金额→签名→广播→入账）。");
h3("4.15.2 提现");
bullet("账户选择：收益账户（≥50 USDT，3% 服务费）/ 本金账户（无门槛、无服务费）；");
bullet("网络选择（同上四网络）、金额/地址输入；");
bullet("实时费用报价（服务费 + 网络费，内扣展示）；确认提交。");
h3("4.15.3 钱包矩阵");
bullet("各链专属充值地址一览 + 各链累计充值统计。");
h3("4.15.4 双账户与转化");
bullet("本金账户 + 收益账户双账户体系；收益→本金转化（报价确认 + 防重复提交）。");

h2("4.16 理财中心");
bullet("理财产品：列表/详情/购买；展示日化收益率、期限（天数）、金额区间、VIP/团队等级门槛；首购弹窗提示（购买后不可补绑邀请码）；防重复下单；");
bullet("我的订单：生效中/已完成两态，展示产品、金额、状态、锁定 VIP 加成、结算安排、到期时间；");
bullet("资金页：资金明细（按账户筛选）/ 收益结算 / 佣金 / 提现记录 / 等级变动 五类流水 Tab。");

h2("4.17 VIP / 团队 / 分佣 / 邀请");
bullet("VIP 等级：有效持仓、当前等级、收益加成、距下一级差额；VIP0-10 等级表（收益加成约 5%-24% 递增）；");
bullet("我的团队：三代有效人数/持仓、团队等级、各级返佣比例、升级差额（0-10 级表）；");
bullet("分佣中心：累计佣金、团队等级与三代返佣比例（5%/3%/2% 起递增）、佣金明细按代数筛选；");
bullet("邀请好友：专属邀请码/链接复制、邀请海报生成分享、上级绑定状态展示、补填邀请码入口。");

h2("4.18 用户中心（个人资料 / 安全设置 / 偏好设置 三 Tab）");
h3("4.18.1 个人资料");
bullet("更换头像（相册上传，≤10MB）、修改昵称；");
bullet("查看用户名/邮箱；退出登录；注销账号（需密码确认）。");
h3("4.18.2 安全设置");
bullet("登录密码修改、谷歌 2FA（TOTP 绑定/解绑）、邮箱验证状态；");
bullet("设备管理（设备列表、远程下线）、防钓鱼码、拉黑管理。");
h3("4.18.3 偏好设置");
bullet("语言选择（8 种）、计价货币（占位）、涨跌配色切换（红涨绿跌 / 绿涨红跌）；");
bullet("行情推送开关、公告推送开关、价格预警入口；");
bullet("用户协议 / 隐私政策入口。");

// ---------- 5 全局设计要求 ----------
h1("5. 全局设计要求");
h2("5.1 色彩语义：涨跌配色双方案");
p("用户可在设置中切换“红涨绿跌”与“绿涨红跌”。所有涉及涨跌的组件（价格、涨跌幅、K线、sparkline、爆仓多空条、费率温度条等）必须同时适配两套配色方案，设计稿需给出两套色板定义。");
h2("5.2 多语言适配");
p("全量页面支持 8 种语言。英语、西班牙语、葡萄牙语文案长度通常为中文的 1.5-2 倍，所有按钮、标签、卡片需预留文案膨胀空间，禁止固定宽度截断关键文案。");
h2("5.3 状态设计（每页必出）");
bullet("加载态：首屏骨架屏；");
bullet("空态：无数据/无好友/无订单等空页面插画与引导；");
bullet("错误态：接口失败时数据显示“--”，不展示假数据；网络断流时的兜底提示；");
bullet("未登录占位：聊天/我的 Tab 的登录引导页。");
h2("5.4 实时性表达");
p("行情类页面以 WebSocket 实时推送为主，价格跳动、实时爆仓 feed、巨鲸异动时间线等需要有明确的“实时更新”视觉反馈（如闪动、滚动插入动画），顶部 Header 含数据同步状态标识。");
h2("5.5 角标与推送");
bullet("未读消息、好友请求角标（会话列表与底部导航联动）；");
bullet("推送类型：聊天消息、巨鲸异动订阅、价格预警、公告；iOS 离线走 APNs。");
h2("5.6 iOS 专属设计");
bullet("桌面小组件：主流币价格展示；");
bullet("灵动岛 / 实时活动（Live Activity）：行情详情页开启后展示实时价格。");
h2("5.7 关键手势与交互");
bullet("K线：拖拽平移、双指捏合缩放；");
bullet("语音消息：按住说话、上滑取消；");
bullet("图片全屏缩放查看；列表分页加载与下拉刷新；");
bullet("行情详情页内下拉快速切换交易对。");

// ---------- 6 合规说明 ----------
h1("6. 合规说明");
bullet("“联系客服”入口当前版本隐藏，设计中可预留位置。");
bullet("注册必须包含用户协议与隐私政策勾选；注销账号入口需保留（苹果审核要求）。");

// ---------- 7 术语表 ----------
h1("7. 术语表");
table(
  ["术语", "说明"],
  [
    ["资金费率（Funding Rate）", "永续合约多空双方定期结算的费用，正费率=多头付空头"],
    ["OI / 持仓量", "未平仓合约总量（Open Interest），衡量市场杠杆规模"],
    ["爆仓（Liquidation）", "杠杆仓位被强制平仓的金额统计，分多单/空单"],
    ["多空比", "持多头与空头账户人数比例"],
    ["恐惧贪婪指数", "0-100 的市场情绪指标，越低越恐惧、越高越贪婪"],
    ["山寨季指数", "衡量山寨币相对 BTC 强弱的指标"],
    ["巨鲸", "大额持仓/大额成交的账户，其异动常被作为市场信号"],
    ["市占率", "BTC/ETH 等占整个加密市场总市值的比例"],
    ["TOTP / 谷歌验证", "基于时间的一次性动态口令，用于两步验证（2FA）"],
    ["防钓鱼码", "用户自定义的识别码，展示在官方通知中以辨别真伪"],
    ["WalletConnect", "连接第三方加密钱包进行签名支付的开放协议"],
    ["TRC20/ERC20/BEP20/Arbitrum", "USDT 支持的四种区块链网络，费率与速度不同"],
    ["Live Activity / 灵动岛", "iOS 锁屏与灵动岛区域展示实时信息的能力"],
    ["WebSocket（WS）", "实时推送行情与消息的长连接通道"],
  ],
  [2600, 6426]
);

p("");
note("本文档功能清单基于现有 App 代码完整梳理（截至 2026-10-21）。如在设计过程中发现功能遗漏或变更，以产品方最新确认为准。");

// ---------- document ----------
const doc = new Document({
  creator: "Mingce Product",
  title: "明策 App 功能需求文档",
  styles: {
    default: { document: { run: { font: FONT, size: 21 } } },
    paragraphStyles: [
      { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 32, bold: true, font: FONT, color: "1F3864" },
        paragraph: { spacing: { before: 360, after: 200 }, outlineLevel: 0 } },
      { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 26, bold: true, font: FONT, color: "1F3864" },
        paragraph: { spacing: { before: 280, after: 140 }, outlineLevel: 1 } },
      { id: "Heading3", name: "Heading 3", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 22, bold: true, font: FONT, color: "404040" },
        paragraph: { spacing: { before: 200, after: 100 }, outlineLevel: 2 } },
    ]
  },
  numbering: {
    config: [
      { reference: "bullets", levels: [
        { level: 0, format: LevelFormat.BULLET, text: "•", alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 540, hanging: 270 } } } },
        { level: 1, format: LevelFormat.BULLET, text: "◦", alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 1080, hanging: 270 } } } },
      ] },
    ]
  },
  sections: [{
    properties: {
      page: {
        size: { width: 11906, height: 16838 }, // A4
        margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 }
      }
    },
    headers: {
      default: new Header({
        children: [new Paragraph({
          alignment: AlignmentType.RIGHT,
          children: [new TextRun({ text: "明策 App 功能需求文档 · V1.0", color: "808080", size: 16 })]
        })]
      })
    },
    footers: {
      default: new Footer({
        children: [new Paragraph({
          alignment: AlignmentType.CENTER,
          children: [
            new TextRun({ text: "第 ", size: 16, color: "808080" }),
            new TextRun({ children: [PageNumber.CURRENT], size: 16, color: "808080" }),
            new TextRun({ text: " 页 / 共 ", size: 16, color: "808080" }),
            new TextRun({ children: [PageNumber.TOTAL_PAGES], size: 16, color: "808080" }),
            new TextRun({ text: " 页", size: 16, color: "808080" }),
          ]
        })]
      })
    },
    children
  }]
});

Packer.toBuffer(doc).then(buf => {
  fs.writeFileSync(process.argv[2] || "output.docx", buf);
  console.log("OK");
});

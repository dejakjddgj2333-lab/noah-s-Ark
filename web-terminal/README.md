# 明策 MINGCE Web 终端

App 的桌面宽屏网页版。Vue 3 + Vite + JS + Pinia + Vue Router + ECharts,
视觉按 Stitch 设计的「Obsidian Precision」体系 (`../stitch_ref/web_terminal/DESIGN.md`)。

## 开发

```bash
npm install
npm run dev   # http://localhost:5520, /api 代理到 http://shipapi.bdxapi.com
```

## 构建

```bash
npm run build # 产物在 dist/, 静态托管即可; 需把 /api 反代到后端
```

## 页面

| 路由 | 页面 | 数据源 |
|---|---|---|
| /login /register | 登录 / 注册 (邮箱验证码+邀请码) | /api/auth/* |
| /overview | 概览: 全局市值/BTC 占比/多空比/恐慌贪婪/涨幅榜/快讯 | market-overview/*, market/tickers, news |
| /market | 行情列表 (现货/永续, 搜索) | market/tickers |
| /market/:instId | K 线 (15m/1H/4H/1D) + 盘口 + 逐笔成交 | market/candles|books|trades |
| /multi | 多维数据: 多空比/持仓额/流动性/七大指数 sparkline | market-overview/* |
| /liquidation | 爆仓监控: 实时强平流水 10s 轮询 | liquidations/* |
| /whale | 巨鲸动向: HL+Binance 大额成交流 | whale-alerts |
| /funding | 资金费率: 各所当期费率 + 7 日历史 | funding/* |
| /news /news/:id | 资讯列表 (分类/分页) + 详情 (点赞/收藏) | news/*, interaction/* |
| /chat | 聊天室: 会话/消息 5s 轮询/成员 | chat/* |
| /assets | 理财产品 + 我的订单 + 返佣汇总 | products, orders, settlements |
| /profile | 个人中心: 邀请码/改密/登录设备 | auth/*, invite/* |

## 约定

- 数字一律 JetBrains Mono 右对齐; 涨绿 `#00E388` 跌红 `#FF5F6D`; 主 accent 钴蓝 `#2E5CFF`
- 鉴权 Bearer token 存 localStorage (`mc_token`); 401 自动回登录页
- 时间: 资讯 publish_at 是北京时间裸值, 用 `utils/format.ts()` 解析
- 申购等写操作在 App 内完成, Web 端只读展示

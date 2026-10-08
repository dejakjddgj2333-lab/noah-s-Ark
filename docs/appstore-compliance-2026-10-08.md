# App Store 合规整改记录 (2026-10-08)

对应审核回复 Submission 188809b4 (Version 1.0.0 (8), iPad Air 11 M3)。

**最终方案（用户拍板）**：分佣多级改动已全部还原，改为**整体隐藏**——理财与返佣本次上架不出现，资质下来后后台一键打开。

## C4 — Guideline 5 (多级返佣 MLM) + 理财占位 (2.1(a)) 隐藏方案

### 新增功能开关 `finance_enabled`（默认 0=隐藏）

**server/services/config_service.py**
- `_DEFAULTS` 加 `("finance_enabled", "0", "理财/返佣功能开关")`
- `PUBLIC_KEYS` 加 `finance_enabled`（App 公开读取）
- 后台「功能开关」页可切换，无需发版

**app/lib/services/feature_flag.dart**
- 新增 `financeEnabled`，`/api/config` 拉取，失败默认隐藏

### App 隐藏点（finance_enabled=0 时）

**app/lib/pages/assets_page.dart**
- 理财中心卡（产品/VIP/团队/订单/资金明细入口）整卡隐藏
- 合伙人分佣卡（累计佣金/今日佣金/邀请码/分佣入口）整卡隐藏
- 身份卡团队等级徽章隐藏
- VIP/团队等级条（_levelStrip）隐藏

### 已还原（不再做删改，等资质后原样放出来）
- commission_page.dart / team_page.dart 回到 c0ccbcf 前状态（多级展示代码保留）
- 后端结算多代返佣逻辑不动

### 恢复方式
后台「功能开关」把 `finance_enabled` 打开即可，App 端无需发版。

---

## 资金密码移除 (App 端)

**app/lib/pages/profile_page.dart**
- 删除「设置-资金密码」入口行及 import

**保留未删**（后端接口与数据仍在，便于恢复）:
- `app/lib/pages/fund_password_page.dart`（页面文件保留，无入口）
- `AuthStore.setFundPassword / changeFundPassword / hasFundPassword`
- 服务端 `/api/auth/fund-password*` 接口

---

## 待办（App Store Connect 后台操作, 非代码）

1. **2.3.8** 商店名 `Noah Quant` → 与设备名「明策」对齐（如「明策量化」）
2. **2.3.6** 年龄分级 → 「用户生成内容」选「是」
3. **2.1** 回复审核问题（无交易功能；资金密码功能已从本版本移除）

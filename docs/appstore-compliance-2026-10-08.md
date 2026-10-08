# App Store 合规整改记录 (2026-10-08)

对应审核回复 Submission 188809b4 (Version 1.0.0 (8), iPad Air 11 M3)。

## C4 — Guideline 5 (多级返佣 MLM) App 端整改

### 改动内容 (commit 见 git log)

**app/lib/pages/commission_page.dart (分佣页)**
- 佣金明细只显示直推（一代）记录：`gen == 1` 过滤，二代/三代不再展示
- 删除代数筛选胶囊（全部/一代/二代/三代）
- 团队等级卡返佣比例只显示一代（gen1_rate），删除二代/三代比例
- 记录项删除「N 代」数字徽章与「X 代返佣」标签，改中性图标

**app/lib/pages/team_page.dart (团队页)**
- 等级卡返佣比例只显示一代
- 等级规则表每行只显示一代返佣比例，删除「一代/二代/三代」三列展示

### 未动（保留）
- `FinanceApi.teamMe()` 接口返回字段不变（gen2/gen3 字段仍在，App 不渲染）
- 后端结算逻辑本轮未改（App 先行，后端砍多代结算另议）
- assets_page.dart 原本就只展示一代比例，无需改

### 恢复方式
回滚本 commit 即恢复多级展示。

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
3. **2.1(a)** 后台产品管理删除/替换理财中心占位产品
4. **2.1** 回复审核问题（交易功能否认 + 资金密码用途说明已随功能移除）

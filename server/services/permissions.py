"""后台权限码定义 (RBAC). 页面码 page:* 控制菜单/路由, 按钮码 btn:* 控制操作.

角色 perms 存权限码数组, ['*'] 表示全部 (超管).
"""
from __future__ import annotations

# 权限树: 前端角色编辑用 el-tree 勾选; 后端只做码校验
PERMISSION_TREE: list[dict] = [
    {"code": "page:dashboard", "name": "仪表盘", "children": []},
    {
        "code": "page:users",
        "name": "用户管理",
        "children": [
            {"code": "btn:user:freeze", "name": "冻结/解冻"},
            {"code": "btn:user:adjust", "name": "余额调整"},
            {"code": "btn:user:reset", "name": "重置密码"},
            {"code": "btn:user:update", "name": "改绑邮箱/上级"},
            # 删除单独一码 (2026-10-09): 仅空账户可删 (服务端逐项校验),
            # 默认仅超管, 需他人删时角色管理单独授
            {"code": "btn:user:delete", "name": "删除空账户"},
        ],
    },
    {"code": "page:deposit-records", "name": "充值记录", "children": []},
    {
        "code": "page:deposit-pool",
        "name": "充值地址池",
        "children": [
            {"code": "btn:deposit:generate", "name": "生成地址"},
        ],
    },
    {
        "code": "page:sweep",
        "name": "资金归集",
        "children": [
            # 拆分两码 (2026-10-06 审计): 改主钱包地址与执行归集不得同人同号,
            # 否则一个财务账号即可改地址+卷走全部池内资金
            {"code": "btn:sweep:target", "name": "设置主钱包/阈值"},
            {"code": "btn:sweep:run", "name": "执行归集"},
        ],
    },
    {
        "code": "page:products",
        "name": "产品管理",
        "children": [
            {"code": "btn:product:edit", "name": "新建/编辑/上下架"},
            # 删除单独一码 (2026-10-09): 物理删除不可恢复, 默认仅超管,
            # 需他人删时在角色管理单独授; 有订单的产品服务端仍会拒删
            {"code": "btn:product:delete", "name": "删除产品"},
        ],
    },
    {"code": "page:orders", "name": "购买订单", "children": []},
    {
        # 运营参数 (费率/限额/限流): 改动直接影响资金口径, 编辑码默认只给超管,
        # 需要他人改时在角色管理里单独授 btn:config:edit
        "code": "page:config",
        "name": "参数配置",
        "children": [
            {"code": "btn:config:edit", "name": "保存参数"},
        ],
    },
    {
        "code": "page:withdrawals",
        "name": "提现审核",
        "children": [
            {"code": "btn:withdrawal:audit", "name": "审核通过/拒绝"},
        ],
    },
    {
        "code": "page:admins",
        "name": "管理员管理",
        "children": [
            {"code": "btn:admin:manage", "name": "绑定/改角色/移除"},
        ],
    },
    {
        "code": "page:roles",
        "name": "角色权限",
        "children": [
            {"code": "btn:role:manage", "name": "新建/编辑/删除"},
        ],
    },
    {
        "code": "page:legal",
        "name": "协议管理",
        "children": [
            {"code": "btn:legal:edit", "name": "编辑协议"},
        ],
    },
    {
        "code": "page:report",
        "name": "举报管理",
        "children": [
            {"code": "btn:report:handle", "name": "处理举报"},
        ],
    },
    {
        "code": "page:feature",
        "name": "功能开关",
        "children": [
            {"code": "btn:feature:edit", "name": "修改开关"},
        ],
    },
]

ALL_CODES: set[str] = {
    c["code"] for p in PERMISSION_TREE for c in [p, *p["children"]]
}

# 权限码 → 中文名 (403 提示用: 告诉操作者缺的是哪项权限, 而不是干巴巴一句"没有权限")
PERM_NAMES: dict[str, str] = {
    c["code"]: f'{p["name"]} · {c["name"]}' if c is not p else p["name"]
    for p in PERMISSION_TREE
    for c in [p, *p["children"]]
}

# 预置角色 (code, name, perms); 启动幂等 upsert
BUILTIN_ROLES: list[tuple[str, str, list[str]]] = [
    ("superadmin", "超级管理员", ["*"]),
    (
        "ops",
        "运营",
        [
            "page:dashboard",
            "page:users",
            "btn:user:freeze",
            "btn:user:adjust",
            "btn:user:reset",
            "btn:user:update",
            "page:products",
            "btn:product:edit",
            "page:orders",
        ],
    ),
    (
        "finance",
        "财务",
        [
            "page:dashboard",
            "page:deposit-records",
            "page:deposit-pool",
            "btn:deposit:generate",
            "page:sweep",
            "btn:sweep:run",
            "page:withdrawals",
            "btn:withdrawal:audit",
            "page:orders",
            "page:config",
        ],
    ),
    (
        "support",
        "客服",
        ["page:dashboard", "page:users", "page:deposit-records"],
    ),
]

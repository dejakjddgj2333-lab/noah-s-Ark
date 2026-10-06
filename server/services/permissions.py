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
        ],
    },
    {"code": "page:orders", "name": "购买订单", "children": []},
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
]

ALL_CODES: set[str] = {
    c["code"] for p in PERMISSION_TREE for c in [p, *p["children"]]
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
        ],
    ),
    (
        "support",
        "客服",
        ["page:dashboard", "page:users", "page:deposit-records"],
    ),
]

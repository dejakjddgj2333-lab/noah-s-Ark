"""运营参数 DB 覆盖层 (2026-10-08): 后台「参数配置」页可改, 保存即生效.

- env (.env) 只作默认值兜底; 后台保存的值写 hk_config 表并刷进内存缓存;
- 业务代码统一走 get(key) 读值, 不再直接读 config.xxx (那些字段 = 默认值);
- 缓存是进程内字典: 生产为单进程 uvicorn, 本进程写后即时生效, 启动时 load() 回填.
"""
from __future__ import annotations

from decimal import Decimal, InvalidOperation

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from config import config
from models.param import HkParam

# 参数注册表: 只有登记在册的 key 后台才可改 (密钥/连接串等基础设施仍只走 env)
_PARAM_DEFS: list[dict] = [
    # ── 收益转本金 ──
    {"key": "income_convert_rate", "group": "convert", "name": "转化服务费率",
     "kind": "decimal", "default": config.income_convert_rate,
     "min": Decimal("0"), "max": Decimal("0.5"),
     "desc": "收益转本金服务费比例, 0.03 = 3%, 从转化金额内扣除"},
    {"key": "income_convert_min", "group": "convert", "name": "最低转化金额",
     "kind": "decimal", "default": config.income_convert_min,
     "min": Decimal("1"), "max": Decimal("1000000"),
     "desc": "单笔转化下限 (USDT)"},
    # ── 提现 ──
    {"key": "income_service_rate", "group": "withdraw", "name": "收益提现服务费率",
     "kind": "decimal", "default": config.income_service_rate,
     "min": Decimal("0"), "max": Decimal("0.5"),
     "desc": "收益账户提现服务费比例, 0.03 = 3% (本金账户提现不收)"},
    {"key": "income_min_withdraw", "group": "withdraw", "name": "收益提现最低金额",
     "kind": "decimal", "default": config.income_min_withdraw,
     "min": Decimal("1"), "max": Decimal("1000000"),
     "desc": "收益账户单笔提现下限 (USDT); 本金账户无门槛"},
    {"key": "withdraw_max_per_request", "group": "withdraw", "name": "单笔提现上限",
     "kind": "decimal", "default": config.withdraw_max_per_request,
     "min": Decimal("0"), "max": Decimal("100000000"),
     "desc": "按扣费前申请金额计 (USDT); 0 = 不限制"},
    {"key": "withdraw_daily_limit", "group": "withdraw", "name": "单日提现上限",
     "kind": "decimal", "default": config.withdraw_daily_limit,
     "min": Decimal("0"), "max": Decimal("100000000"),
     "desc": "同一用户单日累计 (处理中+已通过计入, USDT); 0 = 不限制"},
    {"key": "withdraw_fee_trc20", "group": "withdraw", "name": "网络费 TRC20",
     "kind": "decimal", "default": config.withdraw_fee_trc20,
     "min": Decimal("0"), "max": Decimal("1000"), "desc": "波场提现固定网络费 (USDT)"},
    {"key": "withdraw_fee_erc20", "group": "withdraw", "name": "网络费 ERC20",
     "kind": "decimal", "default": config.withdraw_fee_erc20,
     "min": Decimal("0"), "max": Decimal("1000"), "desc": "以太坊提现固定网络费 (USDT)"},
    {"key": "withdraw_fee_bep20", "group": "withdraw", "name": "网络费 BEP20",
     "kind": "decimal", "default": config.withdraw_fee_bep20,
     "min": Decimal("0"), "max": Decimal("1000"), "desc": "BNB Chain 提现固定网络费 (USDT)"},
    {"key": "withdraw_fee_arbitrum", "group": "withdraw", "name": "网络费 Arbitrum",
     "kind": "decimal", "default": config.withdraw_fee_arbitrum,
     "min": Decimal("0"), "max": Decimal("1000"), "desc": "Arbitrum 提现固定网络费 (USDT)"},
    # ── 限流 ──
    {"key": "purchase_rate_limit", "group": "ratelimit", "name": "购买限流",
     "kind": "int", "default": config.purchase_rate_limit,
     "min": 1, "max": 10000, "desc": "同一用户每分钟最大下单数"},
    {"key": "deposit_claim_rate_limit", "group": "ratelimit", "name": "补单限流",
     "kind": "int", "default": config.deposit_claim_rate_limit,
     "min": 1, "max": 1000, "desc": "同一用户每分钟最大 txid 补单数"},
    {"key": "login_rate_limit", "group": "ratelimit", "name": "登录限流",
     "kind": "int", "default": config.login_rate_limit,
     "min": 1, "max": 100, "desc": "同一 IP+用户名 5 分钟内最大失败尝试次数"},
    {"key": "register_rate_limit", "group": "ratelimit", "name": "注册限流",
     "kind": "int", "default": config.register_rate_limit,
     "min": 1, "max": 10000, "desc": "同一 IP 每小时最大注册数"},
    {"key": "email_code_rate_limit", "group": "ratelimit", "name": "发码限流",
     "kind": "int", "default": config.email_code_rate_limit,
     "min": 1, "max": 1000, "desc": "同一 IP 每小时最大发验证码数"},
]
_DEF_BY_KEY: dict[str, dict] = {d["key"]: d for d in _PARAM_DEFS}

_cache: dict[str, Decimal | int] = {}


def _parse(defn: dict, raw: str) -> Decimal | int:
    """按注册类型解析并校验范围, 非法值抛 400."""
    try:
        if defn["kind"] == "int":
            val: Decimal | int = int(Decimal(raw))
        else:
            val = Decimal(raw)
    except (InvalidOperation, ValueError):
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, f"{defn['name']}: 「{raw}」不是有效数字"
        )
    if val < defn["min"] or val > defn["max"]:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            f"{defn['name']} 须在 {defn['min']} ~ {defn['max']} 之间",
        )
    return val


def get(key: str) -> Decimal | int:
    """业务读值入口: 缓存覆盖值优先, 否则 env 默认.

    env 默认不做范围校验: 范围是约束后台运营输入的, 部署方在 env 里
    写多大都信任 (例如测试要放开限流到 100000).
    """
    if key in _cache:
        return _cache[key]
    d = _DEF_BY_KEY[key]  # KeyError = 代码 bug, 不该对调用方隐藏
    raw = str(d["default"])
    return int(Decimal(raw)) if d["kind"] == "int" else Decimal(raw)


async def load(db: AsyncSession) -> None:
    """启动时把 DB 覆盖值回填进缓存 (坏值跳过, 不阻塞启动)."""
    rows = (await db.execute(select(HkParam))).scalars().all()
    for r in rows:
        d = _DEF_BY_KEY.get(r.key)
        if d is None:
            continue
        try:
            _cache[r.key] = _parse(d, r.value)
        except HTTPException:
            continue


def view() -> list[dict]:
    """后台 GET 全量视图: 当前生效值 + 是否被后台改过 + 默认值/范围说明."""
    out = []
    for d in _PARAM_DEFS:
        overridden = d["key"] in _cache
        out.append({
            "key": d["key"],
            "group": d["group"],
            "name": d["name"],
            "kind": d["kind"],
            "value": str(get(d["key"])),
            "overridden": overridden,
            "default": str(d["default"]),
            "min": str(d["min"]),
            "max": str(d["max"]),
            "desc": d["desc"],
        })
    return out


async def update(
    db: AsyncSession, updates: dict[str, str], operator: str
) -> list[str]:
    """校验 → 落库 → 刷缓存. 全部合法才写, 任一非法整体拒绝 (不落半个)."""
    parsed: dict[str, Decimal | int] = {}
    for key, raw in updates.items():
        d = _DEF_BY_KEY.get(key)
        if d is None:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST, f"未知参数: {key}"
            )
        parsed[key] = _parse(d, str(raw).strip())

    changed: list[str] = []
    for key, val in parsed.items():
        row = (
            await db.execute(select(HkParam).where(HkParam.key == key))
        ).scalar_one_or_none()
        if row is None:
            db.add(HkParam(key=key, value=str(val), updated_by=operator))
        else:
            row.value = str(val)
            row.updated_by = operator
        _cache[key] = val
        changed.append(key)
    await db.flush()
    return changed

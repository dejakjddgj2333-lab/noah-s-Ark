"""协议文档种子: 隐私政策/用户协议初始内容 (字符串常量嵌入, 避免部署路径问题).

首次启动若 hk_legal_docs 为空, 插入 privacy/terms 两条.
"""
from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from models.hk import HkLegalDoc

PRIVACY_HTML = """<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="utf-8"><title>隐私政策</title></head>
<body>
<h1>隐私政策 / Privacy Policy</h1>
<p><em>更新日期：2026年10月6日 &nbsp;|&nbsp; 生效日期：2026年10月6日</em></p>

<h2>一、引言</h2>
<p>明策（MINGCE，下称"本 App"或"我们"）由重庆超玩潮品运营。本隐私政策说明我们在您使用本加密货币行情终端服务时，如何收集、使用、存储和保护您的个人信息。使用本 App 即表示您同意本政策。</p>

<h2>二、我们收集的信息</h2>
<ul>
<li><strong>账户信息</strong>：用户名、邮箱地址、加密存储的密码、昵称、头像。</li>
<li><strong>安全设置</strong>：资金密码（加密存储）、谷歌验证密钥、防钓鱼码、登录设备信息（设备名、平台、IP、登录时间）。</li>
<li><strong>推送标识</strong>：APNs 设备令牌（device token），用于向您发送行情预警、新消息、提现到账等通知。</li>
<li><strong>社交内容</strong>：您主动发送的聊天消息、图片、语音、视频及好友关系。服务端仅作中继转发，定期清理。</li>
<li><strong>行情偏好</strong>：您设置的价格预警、自选语言、涨跌配色等使用偏好。</li>
<li><strong>设备与日志</strong>：为保障服务安全而记录的必要日志（如登录限流、异常检测）。</li>
</ul>

<h2>三、信息的使用</h2>
<p>我们仅将收集的信息用于：提供行情展示与预警服务、账户安全验证、社交功能、推送通知、改进产品体验及防范欺诈滥用。我们不会将您的个人信息用于无关用途。</p>

<h2>四、信息的共享</h2>
<p>我们不出售您的个人信息。仅在以下情形共享：</p>
<ul>
<li>行情数据来自公开交易所 API（Binance、Bybit、OKX 等），仅传输必要的行情查询请求，不含您的身份信息。</li>
<li>APNs 推送经苹果推送服务送达，仅包含通知标题与内容。</li>
<li>法律法规要求或监管机构依法调取时。</li>
</ul>

<h2>五、信息的存储与安全</h2>
<p>密码与资金密码采用 bcrypt 加盐哈希存储，传输全程 HTTPS 加密。聊天媒体文件定期自动清理。我们采取合理的技术与管理措施保护信息安全，但无法保证绝对安全，请您妥善保管账户凭证。</p>

<h2>六、您的权利</h2>
<p>您可在 App 内：修改昵称/头像、管理登录设备并远程下线、设置或关闭推送、开启/解绑两步验证。如需注销账户或删除个人数据，请联系我们。</p>

<h2>七、未成年人</h2>
<p>本 App 不面向 17 周岁以下未成年人，我们不会故意收集未成年人信息。</p>

<h2>八、政策更新</h2>
<p>本政策更新时将在本页面公布并注明生效日期，重大变更将通过 App 内公告提示。</p>

<h2>九、联系我们</h2>
<p>如对本隐私政策有任何疑问，请通过 App 内客服或运营方联系渠道与我们取得联系。</p>

<hr>
<h1>Privacy Policy (English Summary)</h1>
<p>Mingce ("the App"), operated by Chongqing Chaowan Chaopin, provides a crypto market terminal. We collect: account info (username, email, hashed password, nickname, avatar); security settings (hashed fund password, TOTP secret, anti-phishing code, login devices); APNs device tokens for notifications; social content you send (relayed and periodically purged); market preferences (price alerts, language); and necessary security logs. We use data only to provide the service, secure your account, and send notifications. We do not sell personal data. Market data comes from public exchange APIs without your identity. Passwords are bcrypt-hashed and traffic is HTTPS-encrypted. You may edit your profile, manage devices, toggle notifications, and enable 2FA in-app, and may request account deletion via support. The App is not directed at minors under 17. Updates will be posted here.</p>
</body>
</html>
"""

TERMS_HTML = """<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="utf-8"><title>用户服务协议</title></head>
<body>
<h1>用户服务协议 / Terms of Service</h1>
<p><em>更新日期：2026年10月6日 &nbsp;|&nbsp; 生效日期：2026年10月6日</em></p>

<h2>一、协议范围</h2>
<p>本协议由您与明策（MINGCE，下称"本 App"）运营方重庆超玩潮品签订。您注册、登录或使用本 App 即表示已阅读并同意本协议全部内容。如您不同意，请停止使用。</p>

<h2>二、服务说明</h2>
<p>本 App 是一款加密货币行情数据终端与社交工具，提供行情展示、多维指数、链上数据、价格预警、资讯、聊天与音视频通话等功能。<strong>本 App 不提供法币充值、真实货币交易撮合或投资咨询服务，所有行情数据均来自公开交易所 API，仅供参考。</strong></p>

<h2>三、账户与安全</h2>
<ul>
<li>您应提供真实、准确的信息注册账户，并妥善保管登录密码、资金密码及两步验证密钥。</li>
<li>因您主动泄露凭证导致的损失由您自行承担；发现账户异常应立即通过设备管理下线并联系我们。</li>
<li>我们有权对涉嫌违法违规、批量注册、欺诈滥用的账户采取限制或封禁措施。</li>
</ul>

<h2>四、风险提示（重要）</h2>
<ul>
<li><strong>加密货币市场波动剧烈，投资存在高风险，可能导致全部本金损失。</strong></li>
<li>本 App 提供的行情、指数、预警、资讯等内容均不构成任何投资建议或要约。您据此作出的任何决策及后果由您自行承担。</li>
<li>行情数据可能存在延迟、错误或中断，我们不保证其准确性、完整性与及时性。</li>
<li>请您遵守所在司法辖区关于加密资产的法律法规。部分国家/地区禁止相关活动，请您自行判断并承担合规责任。</li>
</ul>

<h2>五、用户行为规范</h2>
<p>您在使用社交功能时不得：发布违法违规、色情暴力、诈骗赌博、侵犯他人权益的内容；不得骚扰他人、散布恶意软件、干扰服务正常运行。违规内容我们有权删除，情节严重者封禁账户。</p>

<h2>六、知识产权</h2>
<p>本 App 的界面、标识、代码及内容（第三方行情数据除外）的知识产权归运营方所有，未经授权不得复制、修改或用于商业用途。</p>

<h2>七、服务变更与免责</h2>
<ul>
<li>我们可基于运营需要调整、暂停或终止部分功能，并通过公告告知。</li>
<li>因不可抗力、网络故障、第三方数据中断等导致的服务异常，我们不承担由此产生的间接损失。</li>
<li>法律允许范围内，我们对使用本 App 产生的任何直接或间接投资损失不承担责任。</li>
</ul>

<h2>八、协议修改与法律适用</h2>
<p>我们可适时修订本协议并在本页面公布，修订后继续使用即视为接受。本协议适用中华人民共和国法律，争议由运营方所在地有管辖权的人民法院管辖。</p>

<h2>九、联系我们</h2>
<p>如对本协议有任何疑问，请通过 App 内客服或运营方联系渠道与我们取得联系。</p>

<hr>
<h1>Terms of Service (English Summary)</h1>
<p>By using Mingce you agree to these terms. The App is a crypto market data terminal and social tool; it does <strong>not</strong> provide fiat deposits, real-money trading, or investment advice — all market data comes from public exchange APIs for reference only. Crypto markets are highly volatile and you may lose all funds; nothing in the App constitutes investment advice and you bear sole responsibility for your decisions. Market data may be delayed, inaccurate, or interrupted. You must comply with your local laws on crypto assets. Keep your credentials secure; we may restrict fraudulent or abusive accounts. Do not post illegal, fraudulent, or infringing content. Our liability is limited to the maximum extent permitted by law. These terms are governed by the laws of the PRC.</p>
</body>
</html>
"""

_SEED = (
    ("privacy", "隐私政策", PRIVACY_HTML),
    ("terms", "用户服务协议", TERMS_HTML),
)


async def seed_legal_docs(db: AsyncSession) -> None:
    """hk_legal_docs 为空时插入 privacy/terms 种子 (幂等: 仅当表空才插)."""
    existing = (
        await db.execute(select(HkLegalDoc.id).limit(1))
    ).scalar_one_or_none()
    if existing is not None:
        return
    for key, title, content in _SEED:
        db.add(HkLegalDoc(doc_key=key, title=title, content=content))
    await db.commit()

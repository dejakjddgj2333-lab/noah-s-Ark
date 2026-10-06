"""协议文档种子: 隐私政策/用户协议初始内容 (字符串常量嵌入, 避免部署路径问题).

首次启动若 hk_legal_docs 为空, 插入 privacy/terms 两条.
"""
from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from models.hk import HkLegalDoc

PRIVACY_HTML = """<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>隐私政策</title></head>
<body>
<h1>隐私政策</h1>
<p><em>更新日期：2026年10月6日 &nbsp;|&nbsp; 生效日期：2026年10月6日</em></p>

<h2>一、引言与适用范围</h2>
<p>本《隐私政策》由<strong>重庆潮玩潮品电子商务有限公司</strong>（以下简称"我们"或"本公司"）制定并发布，适用于我们运营的"明策（MINGCE）"移动应用程序（以下简称"本 App"）及其提供的全部产品与服务。</p>
<p>我们深知个人信息安全的重要性，并将严格按照《中华人民共和国个人信息保护法》《中华人民共和国网络安全法》《中华人民共和国数据安全法》等法律法规，以及本政策的约定，收集、使用、存储、共享和保护您的个人信息。请您在使用本 App 前仔细阅读并充分理解本政策；您开始使用本 App，即表示您已阅读并同意本政策的全部内容。如您不同意，请立即停止使用。</p>

<h2>二、我们收集的个人信息及用途</h2>
<p>我们遵循合法、正当、必要和最小化原则，仅为实现下列功能之目的收集相关信息：</p>

<h3>（一）账户注册与登录</h3>
<ul>
<li><strong>收集信息</strong>：用户名、电子邮箱地址、登录密码（仅以 bcrypt 加盐哈希形式存储，我们无法获取明文）。</li>
<li><strong>用途</strong>：创建并验证您的账户、保障账户安全、提供登录服务。</li>
</ul>

<h3>（二）账户安全设置</h3>
<ul>
<li><strong>收集信息</strong>：资金密码（加密哈希存储）、谷歌两步验证（TOTP）密钥、防钓鱼码、登录设备信息（设备名称、操作系统平台、IP 地址、登录及活跃时间）。</li>
<li><strong>用途</strong>：增强账户安全防护、异常登录识别、支持您远程管理并下线登录设备。</li>
</ul>

<h3>（三）消息推送</h3>
<ul>
<li><strong>收集信息</strong>：苹果推送通知服务（APNs）设备令牌（Device Token）。</li>
<li><strong>用途</strong>：在您授权后向您发送行情预警、新聊天消息、好友请求、提现到账等通知。您可随时在 App 内或系统设置中关闭。</li>
</ul>

<h3>（四）社交与通讯功能</h3>
<ul>
<li><strong>收集信息</strong>：您在使用聊天、群组、音视频通话功能时主动发送的文字、图片、语音、视频内容，以及您建立的好友关系。</li>
<li><strong>用途</strong>：实现消息的中继转发与通话连接。服务端仅作传输中继，聊天媒体文件将定期自动清理。</li>
</ul>

<h3>（五）行情与个性化偏好</h3>
<ul>
<li><strong>收集信息</strong>：您设置的价格预警（交易对与目标价）、界面语言、涨跌配色等使用偏好。</li>
<li><strong>用途</strong>：为您提供个性化行情提醒与界面展示。</li>
</ul>

<h3>（六）设备权限的使用</h3>
<p>以下系统权限仅在您使用对应功能时才会申请，且您可拒绝而不影响其它功能：</p>
<ul>
<li><strong>相机</strong>：用于扫描二维码、拍摄头像照片、进行音视频通话。</li>
<li><strong>相册</strong>：用于选择图片发送或设置为头像，以及保存图片到本地。</li>
<li><strong>麦克风</strong>：用于发送语音消息及音视频通话。</li>
<li><strong>通知</strong>：用于接收上述各类消息提醒。</li>
</ul>

<h3>（七）日志信息</h3>
<ul>
<li><strong>收集信息</strong>：为保障服务安全所必需的操作与访问日志（如登录失败限流、异常请求检测）。</li>
<li><strong>用途</strong>：防范欺诈、滥用与网络攻击，维护服务稳定运行。</li>
</ul>

<h2>三、我们如何使用 Cookie 及同类技术</h2>
<p>本 App 主要通过本地存储保存您的登录凭证与偏好设置，以维持登录状态和提升使用体验。我们不会将此类技术用于本政策未载明的其它目的。</p>

<h2>四、个人信息的共享、转让与公开披露</h2>
<p><strong>我们不会向任何第三方出售您的个人信息。</strong>仅在以下情形下共享必要信息：</p>
<ul>
<li><strong>行情数据服务</strong>：行情数据来自公开的第三方交易所 API（包括但不限于 Binance、Bybit、OKX）。相关请求仅包含行情查询参数，不含您的任何身份信息。</li>
<li><strong>推送服务</strong>：通知内容经苹果 APNs 服务送达您的设备，仅包含通知标题与正文。</li>
<li><strong>法律要求</strong>：根据法律法规的强制性规定、司法或行政机关的合法要求，或为保护我们及用户的合法权益、防范重大安全风险所必需时。</li>
</ul>
<p>我们不会转让您的个人信息，除非涉及合并、收购或资产转让，并将要求受让方继续受本政策约束。我们不会公开披露您的个人信息，除非获得您的明示同意或基于法律强制要求。</p>

<h2>五、个人信息的存储与跨境传输</h2>
<ul>
<li><strong>存储地点</strong>：您的个人信息存储于我们位于境内的服务器。</li>
<li><strong>存储期限</strong>：我们仅在实现本政策所述目的所必需的最短期限内保留您的个人信息；账户注销后，我们将按法律要求删除或匿名化处理，法律法规另有规定的除外。</li>
<li><strong>跨境传输</strong>：除向您推送通知需经苹果境外服务节点外，我们不会将您的个人信息传输至境外。</li>
</ul>

<h2>六、个人信息安全保护</h2>
<p>我们采取符合业界标准的技术与管理措施保护您的信息安全，包括但不限于：密码与资金密码的 bcrypt 加盐哈希存储、全链路 HTTPS 加密传输、访问权限控制与安全审计。请您理解，互联网环境并非绝对安全，任何安全措施都存在被突破的可能。如发生个人信息安全事件，我们将按法律要求及时告知您并向主管部门报告。请您务必妥善保管账户凭证，勿将其透露给他人。</p>

<h2>七、您的权利</h2>
<p>依据相关法律法规，您对自己的个人信息享有以下权利：</p>
<ul>
<li><strong>访问与更正</strong>：您可在 App 内查看并修改昵称、头像等个人资料。</li>
<li><strong>设备管理</strong>：您可查看全部登录设备并远程下线任何设备。</li>
<li><strong>授权管理</strong>：您可随时开启/关闭推送通知、绑定/解绑两步验证、开启/关闭各类系统权限。</li>
<li><strong>删除与注销</strong>：您可请求删除个人信息或注销账户。注销后我们将依法删除或匿名化您的个人信息。</li>
</ul>
<p>如您希望行使上述权利或对我们的处理活动有任何疑问，可通过本政策载明的方式与我们联系，我们将在合理期限内予以响应。</p>

<h2>八、未成年人保护</h2>
<p>本 App 面向成年用户，不面向 17 周岁以下的未成年人。我们不会故意收集未成年人的个人信息；如发现误收集，将尽快删除。若您所在司法辖区对加密资产相关服务设有年龄限制，请您自觉遵守。</p>

<h2>九、本政策的更新</h2>
<p>我们可能适时修订本政策。更新后的政策将在本页面公布并注明生效日期；涉及重大变更时，我们将通过 App 内公告等显著方式另行提示。修订后的政策自公布之日起生效，您继续使用本 App 即视为接受修订后的政策。</p>

<h2>十、如何联系我们</h2>
<p>如对本隐私政策或个人信息保护有任何疑问、意见或投诉，您可通过本 App 内的客服渠道，或通过以下方式与本公司联系：</p>
<p><strong>重庆潮玩潮品电子商务有限公司</strong><br>（联系邮箱 / 地址：以 App 内公示及公司登记信息为准）</p>
<p>我们将在核实您身份后的合理期限内（通常不超过 15 个工作日）予以答复。</p>

<hr>
<h1>Privacy Policy (English)</h1>
<p><em>Last updated: October 6, 2026</em></p>
<p>This Privacy Policy is issued by <strong>Chongqing Chaowan Chaopin E-Commerce Co., Ltd.</strong> ("we", "us") for the "Mingce (MINGCE)" mobile application (the "App"). By using the App you agree to this Policy.</p>
<h3>1. Information We Collect</h3>
<ul>
<li><strong>Account</strong>: username, email, password (bcrypt-hashed only).</li>
<li><strong>Security</strong>: hashed fund password, TOTP (2FA) secret, anti-phishing code, login devices (name, platform, IP, timestamps).</li>
<li><strong>Notifications</strong>: APNs device token, used to send price alerts, messages, friend requests and withdrawal notices (you may disable anytime).</li>
<li><strong>Social</strong>: chat content (text/image/voice/video) and friend relationships you create; the server relays content and periodically purges media.</li>
<li><strong>Preferences</strong>: price alerts, language, chart color settings.</li>
<li><strong>Device permissions</strong>: camera (scan/avatar/calls), photo library (send/avatar/save), microphone (voice/calls), notifications — requested only when needed.</li>
<li><strong>Logs</strong>: security logs for abuse and attack prevention.</li>
</ul>
<h3>2. Sharing</h3>
<p>We do not sell personal data. Market data is fetched from public exchange APIs (Binance/Bybit/OKX) without your identity. Notifications are delivered via Apple APNs. We may disclose data only where required by law.</p>
<h3>3. Storage & Security</h3>
<p>Data is stored on servers in-country and retained only as long as necessary. Passwords are bcrypt-hashed and all traffic is HTTPS-encrypted. No method is 100% secure; please safeguard your credentials.</p>
<h3>4. Your Rights</h3>
<p>You may access and edit your profile, manage and remotely sign out devices, toggle notifications and 2FA, and request deletion or account cancellation by contacting us.</p>
<h3>5. Minors</h3>
<p>The App is not directed at users under 17 and we do not knowingly collect their data.</p>
<h3>6. Changes & Contact</h3>
<p>Updates will be posted here with the effective date. Questions may be sent to Chongqing Chaowan Chaopin E-Commerce Co., Ltd. via the in-app support channel.</p>
</body>
</html>
"""

TERMS_HTML = """<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>用户服务协议</title></head>
<body>
<h1>用户服务协议</h1>
<p><em>更新日期：2026年10月6日 &nbsp;|&nbsp; 生效日期：2026年10月6日</em></p>

<h2>一、协议的确认与接受</h2>
<p>本《用户服务协议》（以下简称"本协议"）由您与<strong>重庆潮玩潮品电子商务有限公司</strong>（以下简称"本公司"）共同缔结，适用于本公司运营的"明策 / Noah's Ark"移动应用程序（以下简称"本 App"）及相关服务。</p>
<p>请您在使用本 App 前审慎阅读并充分理解本协议全部条款，特别是以<strong>加粗</strong>形式提示的免责、风险提示及责任限制条款。您注册、登录或以任何方式使用本 App，即视为已阅读、理解并同意接受本协议全部内容；如您不同意，请立即停止注册与使用。</p>

<h2>二、服务内容</h2>
<p>本 App 是一款加密货币市场行情数据终端与社交工具，主要功能包括：行情数据展示、多维市场指数、链上巨鲸数据、价格预警、资讯阅读、即时聊天及音视频通话等。</p>
<p><strong>本 App 仅为信息展示与数据服务工具，不提供任何形式的法币充值、真实货币或加密资产的交易撮合、托管、清算、投资顾问或资产管理服务。</strong>App 内所有行情数据均来自公开的第三方交易所 API，仅供参考。</p>

<h2>三、账户注册与安全</h2>
<ul>
<li>您应提供真实、准确、合法的信息完成注册，并及时更新。您应对账户项下的一切活动负责。</li>
<li>您应妥善保管登录密码、资金密码及两步验证密钥，勿将其泄露、出借或转让给他人。因您主动泄露凭证导致的任何损失，由您自行承担。</li>
<li>发现账户被盗用或存在安全漏洞时，您应立即通过设备管理功能下线异常设备并通知本公司。</li>
<li>对于涉嫌违反法律法规或本协议、批量恶意注册、欺诈滥用、危害服务安全的账户，本公司有权采取警告、限制功能、暂停或封禁等措施，并保留追究责任的权利。</li>
</ul>

<h2>四、风险揭示（请特别注意）</h2>
<ul>
<li><strong>加密资产市场波动极为剧烈，价格可能在短时间内大幅上涨或下跌，参与相关活动存在极高风险，可能导致您的全部资金损失。</strong></li>
<li><strong>本 App 提供的行情、指数、预警、资讯、数据等所有内容，均不构成任何投资建议、财务建议、要约或要约邀请。</strong>您基于上述信息作出的任何决策，均由您独立判断并自行承担全部后果，本公司不为此承担任何责任。</li>
<li>行情数据来源于第三方，可能存在延迟、错误、遗漏或服务中断，本公司不保证其准确性、完整性、及时性与可靠性。</li>
<li><strong>请您严格遵守所在国家/地区关于加密资产的法律法规及监管要求。</strong>部分司法辖区禁止或限制加密资产相关活动，您应自行确认并承担相应的合规责任；本公司不面向禁止此类活动的地区提供服务。</li>
</ul>

<h2>五、用户行为规范</h2>
<p>您在使用本 App（尤其是社交功能）时，承诺不得从事以下行为：</p>
<ul>
<li>发布、传播违反法律法规、危害国家安全、色情低俗、血腥暴力、赌博诈骗、侵犯他人合法权益的内容；</li>
<li>发布虚假信息、从事任何形式的诈骗、传销、洗钱或其他违法犯罪活动；</li>
<li>骚扰、诽谤、威胁他人，或侵害他人隐私、知识产权；</li>
<li>散布恶意程序、从事网络攻击，或以任何方式干扰、破坏本 App 及其服务的正常运行；</li>
<li>利用本 App 进行任何未经授权的商业活动。</li>
</ul>
<p>对于违规内容与行为，本公司有权删除相关内容、限制或封禁账户，并依法向有关部门报告。</p>

<h2>六、知识产权</h2>
<p>本 App 的界面设计、标识、图标、软件代码及相关内容（第三方提供的行情数据、资讯内容除外）的知识产权，归本公司或相应权利人所有。未经书面许可，您不得复制、修改、传播、出售或用于任何商业用途。</p>

<h2>七、服务的变更、中断与终止</h2>
<ul>
<li>本公司可基于业务发展需要，调整、升级、暂停或终止部分或全部服务，并通过 App 内公告等方式告知。</li>
<li>因不可抗力、网络故障、系统维护、第三方数据服务中断等非本公司可控原因导致的服务异常或数据损失，本公司不承担责任，但将尽力及时恢复。</li>
</ul>

<h2>八、免责声明与责任限制</h2>
<ul>
<li>本 App 及其服务按"现状"和"可用"基础提供。在法律允许的最大范围内，本公司不对服务的适用性、无错误、不间断作任何明示或默示担保。</li>
<li><strong>对于您因使用或无法使用本 App 而产生的任何直接或间接损失（包括但不限于投资损失、利润损失、数据丢失），本公司不承担赔偿责任。</strong></li>
<li>您与任何第三方（含交易所、其他用户）之间的任何纠纷，由您与该第三方自行解决，本公司不介入亦不承担责任。</li>
</ul>

<h2>九、协议的修改与法律适用</h2>
<p>本公司可适时修订本协议，修订后的协议将在本页面公布并注明生效日期；涉及重大变更时将通过 App 内显著方式提示。您在本协议修订后继续使用本 App，即视为接受修订后的协议。</p>
<p>本协议的订立、效力、解释、履行及争议解决均适用中华人民共和国法律。因本协议产生的任何争议，双方应友好协商解决；协商不成的，任何一方均可向本公司所在地有管辖权的人民法院提起诉讼。</p>

<h2>十、联系我们</h2>
<p>如对本协议有任何疑问，您可通过本 App 内的客服渠道，或通过以下方式与本公司联系：</p>
<p><strong>重庆潮玩潮品电子商务有限公司</strong><br>（联系邮箱 / 地址：以 App 内公示及公司登记信息为准）</p>

<hr>
<h1>Terms of Service (English)</h1>
<p><em>Last updated: October 6, 2026</em></p>
<p>These Terms of Service ("Terms") are entered into between you and <strong>Chongqing Chaowan Chaopin E-Commerce Co., Ltd.</strong> ("the Company") for the "Mingce / Noah's Ark" mobile application (the "App"). By registering or using the App you agree to these Terms.</p>
<h3>1. The Service</h3>
<p>The App is a crypto market data terminal and social tool offering market quotes, multi-dimensional indices, on-chain whale data, price alerts, news, chat and voice/video calls. <strong>The App is an information tool only; it does not provide fiat deposits, trading, custody, clearing, investment advisory or asset-management services.</strong> All market data comes from public third-party exchange APIs for reference only.</p>
<h3>2. Risk Disclosure</h3>
<p><strong>Crypto-asset markets are extremely volatile and you may lose all of your funds. Nothing in the App constitutes investment, financial or other advice, nor any offer or solicitation.</strong> You are solely responsible for decisions made based on the information provided. Market data may be delayed, inaccurate or interrupted. You must comply with the laws and regulations of your jurisdiction regarding crypto assets; the App is not offered where such activities are prohibited.</p>
<h3>3. Account</h3>
<p>You must provide accurate information and safeguard your credentials, and you are responsible for all activity under your account. We may restrict or suspend accounts involved in fraud, abuse or violation of these Terms.</p>
<h3>4. Acceptable Use</h3>
<p>You may not post illegal, fraudulent, infringing or harmful content, harass others, distribute malware, disrupt the service, or use the App for unauthorized commercial purposes. Violations may result in content removal or account suspension.</p>
<h3>5. Intellectual Property</h3>
<p>The App's design, logos, code and content (excluding third-party market data) are owned by the Company or respective rights holders and may not be used commercially without permission.</p>
<h3>6. Disclaimers & Limitation of Liability</h3>
<p>The service is provided "as is" and "as available". To the maximum extent permitted by law, the Company is not liable for any direct or indirect losses (including investment losses, lost profits or data loss) arising from your use of the App. Disputes between you and any third party are your own responsibility.</p>
<h3>7. Changes & Governing Law</h3>
<p>We may update these Terms and will post the revised version here. Continued use constitutes acceptance. These Terms are governed by the laws of the People's Republic of China; disputes shall be submitted to the people's court with jurisdiction at the Company's domicile.</p>
<h3>8. Contact</h3>
<p>Chongqing Chaowan Chaopin E-Commerce Co., Ltd. — via the in-app support channel.</p>
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

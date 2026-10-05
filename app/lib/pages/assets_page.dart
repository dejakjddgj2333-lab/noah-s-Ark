import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/auth.dart';
import '../services/finance_api.dart';
import '../services/invite_api.dart';
import 'profile_page.dart';

/// 我的 / 资产 — bottom-nav tab content body (header + bottom nav live in shell).
/// Content body only: scrollable, h-pad 14, top 16, bottom 32.
class AssetsPage extends StatefulWidget {
  const AssetsPage({super.key});

  @override
  State<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends State<AssetsPage> {
  static const cobalt = Color(0xFF2E5CFF);
  static const cobaltSoft = Color(0xFF85A5FF);

  String? _inviteCode;
  Map<String, dynamic>? _acct; // 双账户余额
  Map<String, dynamic>? _vip; // 有效持仓
  Map<String, dynamic>? _team; // 团队等级/有效人数/返佣比例
  Map<String, dynamic>? _commSummary; // 佣金汇总
  List<dynamic> _recentComms = const []; // 最近返佣记录

  @override
  void initState() {
    super.initState();
    _loadInvite();
    _loadData();
  }

  /// 邀请码 (身份卡 chip 展示, 点击复制). 静默容错.
  Future<void> _loadInvite() async {
    try {
      final info = await InviteApi.me();
      if (!mounted) return;
      setState(() => _inviteCode = info.inviteCode);
    } catch (_) {/* 静默 */}
  }

  /// 账户/持仓/团队/佣金真实数据. 单项失败静默, 不阻塞整页.
  Future<void> _loadData() async {
    Future<void> safe(Future<void> Function() f) async {
      try {
        await f();
      } catch (_) {/* 静默 */}
    }

    await Future.wait([
      safe(() async => _acct = await FinanceApi.account()),
      safe(() async => _vip = await FinanceApi.vipMe()),
      safe(() async => _team = await FinanceApi.teamMe()),
      safe(() async => _commSummary = await FinanceApi.commissionSummary()),
      safe(() async =>
          _recentComms = (await FinanceApi.commissions()).take(2).toList()),
    ]);
    if (mounted) setState(() {});
  }

  void _copy(String text, String toast) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(toast, style: McText.sans(size: 13)),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        backgroundColor: McColors.surfaceContainerHighest,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 32),
      children: [
        _identityCard(),
        const SizedBox(height: 20),
        _assetCard(),
        const SizedBox(height: 20),
        _financeCenterCard(),
        const SizedBox(height: 20),
        _commissionCard(),
        const SizedBox(height: 20),
        _settingsCard(),
      ],
    );
  }

  // ---- 1. 用户核心身份与网络状态 HUD ----
  Widget _identityCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDeco(),
      child: Column(
        children: [
          // 头像/昵称/ID: 真实账号数据, 点按进个人信息页.
          GestureDetector(
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ProfilePage())),
            behavior: HitTestBehavior.opaque,
            child: ListenableBuilder(
              listenable: AuthStore.instance,
              builder: (context, _) {
                final auth = AuthStore.instance;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: cobalt.withValues(alpha: 0.5),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: McAvatar(
                                  name: auth.displayName,
                                  url: auth.avatarUrl,
                                  size: 48,
                                  radius: 24,
                                  bg: McColors.surfaceContainerHighest,
                                  fg: McColors.primary,
                                ),
                              ),
                              const Positioned(
                                bottom: 0,
                                right: 0,
                                child: McGlowDot(
                                    color: McColors.tertiary, size: 12),
                              ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        auth.displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: McText.display(
                                            size: 16,
                                            weight: FontWeight.w700),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.verified,
                                        size: 16, color: cobalt),
                                    const SizedBox(width: 6),
                                    // 团队等级徽章 (紧跟昵称, 真实数据).
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: cobalt.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                            color: cobalt.withValues(alpha: 0.4)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.diamond,
                                              size: 16, color: cobaltSoft),
                                          const SizedBox(width: 4),
                                          Text(
                                            _team == null
                                                ? '团队'
                                                : '团队 ${_team!['team_level'] ?? 0} 级',
                                            style: McText.mono(
                                              size: 11,
                                              weight: FontWeight.w700,
                                              color: cobaltSoft,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'ID: ${auth.userId ?? '-'}',
                                  style: McText.mono(
                                    size: 12,
                                    weight: FontWeight.w700,
                                    color: McColors.onSurfaceVariant,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Padding(
                      padding: EdgeInsets.only(top: 14),
                      child: Icon(Icons.chevron_right,
                          size: 18, color: McColors.onSurfaceVariant),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          // 邀请码整行 chip (点击复制)
          GestureDetector(
            onTap: _inviteCode == null
                ? null
                : () => _copy(_inviteCode!, '已复制邀请码'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: McColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: McColors.surfaceContainerHigh.withValues(alpha: 0.6)),
              ),
              child: Row(
                children: [
                  Text('邀请码',
                      style: McText.sans(
                          size: 12, color: McColors.onSurfaceVariant)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _inviteCode ?? '加载中…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: McText.mono(
                        size: 13,
                        weight: FontWeight.w700,
                        color: cobaltSoft,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const Icon(Icons.content_copy,
                      size: 14, color: McColors.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- 2. 链上钱包充值与资产总览 ----
  Widget _assetCard() {
    final principal = FinanceApi.d(_acct?['principal_balance']);
    final income = FinanceApi.d(_acct?['income_balance']);
    final pending =
        FinanceApi.d(_acct?['principal_pending']) + FinanceApi.d(_acct?['income_pending']);
    final holding = FinanceApi.d(_vip?['effective_holding']);
    final total = principal + income + pending + holding;
    final available = principal + income;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet,
                  size: 18, color: cobalt),
              const SizedBox(width: 4),
              Text(
                '终端资产总值 (USDT)',
                style: McText.mono(
                  size: 12,
                  weight: FontWeight.w600,
                  color: McColors.onSurfaceVariant,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _acct == null ? '--' : total.toStringAsFixed(2),
            style: McText.display(
              size: 32,
              weight: FontWeight.w700,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text.rich(
                TextSpan(
                  text: '可用: ',
                  style: McText.mono(
                      size: 12,
                      weight: FontWeight.w700,
                      color: McColors.onSurfaceVariant),
                  children: [
                    TextSpan(
                      text: _acct == null ? '--' : available.toStringAsFixed(2),
                      style: McText.mono(
                          size: 12,
                          weight: FontWeight.w700,
                          color: McColors.onSurface),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '•',
                style: McText.mono(
                    size: 12,
                    weight: FontWeight.w700,
                    color: McColors.onSurfaceVariant),
              ),
              const SizedBox(width: 12),
              Text.rich(
                TextSpan(
                  text: '持仓中: ',
                  style: McText.mono(
                      size: 12,
                      weight: FontWeight.w700,
                      color: McColors.onSurfaceVariant),
                  children: [
                    TextSpan(
                      text: _vip == null ? '--' : holding.toStringAsFixed(2),
                      style: McText.mono(
                          size: 12,
                          weight: FontWeight.w700,
                          color: McColors.onSurface),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '•',
                style: McText.mono(
                    size: 12,
                    weight: FontWeight.w700,
                    color: McColors.onSurfaceVariant),
              ),
              const SizedBox(width: 12),
              Text.rich(
                TextSpan(
                  text: '提现中: ',
                  style: McText.mono(
                      size: 12,
                      weight: FontWeight.w700,
                      color: McColors.onSurfaceVariant),
                  children: [
                    TextSpan(
                      text: _acct == null ? '--' : pending.toStringAsFixed(2),
                      style: McText.mono(
                          size: 12,
                          weight: FontWeight.w700,
                          color: McColors.onSurface),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Action buttons
          Row(
            children: [
              Expanded(
                child: _actionBtn(
                  icon: Icons.bolt,
                  iconColor: Colors.white,
                  text: '链上充值',
                  primary: true,
                  onTap: () => Navigator.pushNamed(context, '/deposit'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionBtn(
                  icon: Icons.arrow_outward,
                  iconColor: McColors.onSurfaceVariant,
                  text: '链上提现',
                  onTap: () => Navigator.pushNamed(context, '/withdraw'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionBtn(
                  icon: Icons.sync_alt,
                  iconColor: cobaltSoft,
                  text: '钱包矩阵',
                  onTap: () => Navigator.pushNamed(context, '/wallet-matrix'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Supported chains
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Text(
                  '支持多链:',
                  style: McText.mono(
                      size: 12,
                      weight: FontWeight.w700,
                      color: McColors.onSurfaceVariant,
                      letterSpacing: 1),
                ),
                const SizedBox(width: 6),
                for (final c in ['TRC20', 'ERC20', 'BEP20', 'Arbitrum'])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: McColors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: McColors.surfaceContainerHigh),
                      ),
                      child: Text(
                        c,
                        style: McText.mono(
                            size: 12, color: McColors.onSurface),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required Color iconColor,
    required String text,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return Material(
      color: primary ? cobalt : McColors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: primary
                ? null
                : Border.all(color: McColors.surfaceContainerHighest),
            boxShadow: primary
                ? [
                    BoxShadow(
                      color: cobalt.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: primary ? Colors.white : iconColor),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: McText.display(
                    size: 13,
                    weight: primary ? FontWeight.w700 : FontWeight.w600,
                    color: primary ? Colors.white : McColors.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- 理财中心 (功能直达, 独立卡片) ----
  Widget _financeCenterCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '理财中心',
            style: McText.display(size: 16, weight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            padding: EdgeInsets.zero, // 否则 primary 滚动视图自动吃状态栏 inset, 标题下出现大空隙
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.5,
            children: [
              for (final (route, icon, label) in [
                ('/products', Icons.savings_outlined, '理财产品'),
                ('/vip', Icons.workspace_premium_outlined, '我的VIP'),
                ('/team', Icons.groups_outlined, '我的团队'),
                ('/orders', Icons.receipt_long_outlined, '我的订单'),
                ('/funds', Icons.account_balance_wallet_outlined, '资金明细'),
                ('/withdraw', Icons.outbox_outlined, '提现'),
              ])
                Material(
                  color: McColors.surfaceContainerHigh.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => Navigator.pushNamed(context, route),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 22, color: McColors.primarySoft),
                        const SizedBox(height: 6),
                        Text(
                          label,
                          style: McText.sans(size: 12, weight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- 3. 合伙人分佣体系看板 ----
  Widget _commissionCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 16,
                    decoration: BoxDecoration(
                      color: cobalt,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '合伙人分佣体系',
                    style: McText.display(size: 16, weight: FontWeight.w700),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cobalt.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: cobalt.withValues(alpha: 0.4)),
                  boxShadow: [
                    BoxShadow(
                        color: cobalt.withValues(alpha: 0.2), blurRadius: 10),
                  ],
                ),
                child: Text(
                  '协议返佣分润系统',
                  style: McText.mono(
                      size: 12, weight: FontWeight.w700, color: cobaltSoft),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Income cards
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: McColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: McColors.surfaceContainerHigh.withValues(alpha: 0.6)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pushNamed(context, '/commission'),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '累计分佣收益 (USDT)',
                          style: McText.mono(
                              size: 12,
                              weight: FontWeight.w700,
                              color: McColors.onSurfaceVariant,
                              letterSpacing: 1),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _commSummary == null
                                ? '--'
                                : FinanceApi.d(_commSummary!['total']).toStringAsFixed(2),
                            style: McText.display(
                                size: 20,
                                weight: FontWeight.w700,
                                color: cobaltSoft),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '佣金随产品收益同步结算',
                          style: McText.mono(
                              size: 12, color: McColors.tertiary),
                        ),
                      ],
                    ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pushNamed(context, '/commission'),
                    child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: McColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: McColors.surfaceContainerHigh
                              .withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '今日佣金',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: McText.mono(
                                    size: 12,
                                    weight: FontWeight.w700,
                                    color: McColors.onSurfaceVariant,
                                    letterSpacing: 1),
                              ),
                            ),
                            const McGlowDot(color: cobalt, size: 6),
                          ],
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _commSummary == null
                                ? '--'
                                : '+${FinanceApi.d(_commSummary!['today']).toStringAsFixed(2)}',
                            style: McText.display(
                                size: 20,
                                weight: FontWeight.w700,
                                color: McColors.onSurface),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '收益按产品周期结算',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: McText.mono(size: 12, color: cobaltSoft),
                        ),
                      ],
                    ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // 3 metrics
          Row(
            children: [
              _metricCell(
                  '有效受邀者',
                  _team == null ? '--' : '${_team!['member_count'] ?? 0} 人',
                  McColors.onSurface),
              const SizedBox(width: 10),
              _metricCell(
                  '今日佣金',
                  _commSummary == null
                      ? '--'
                      : '+${FinanceApi.d(_commSummary!['today']).toStringAsFixed(2)}',
                  McColors.tertiary),
              const SizedBox(width: 10),
              _metricCell(
                  '团队等级',
                  _team == null
                      ? '--'
                      : 'Lv${_team!['team_level'] ?? 0}'
                        '${_team!['gen1_rate'] == null ? '' : ' (${(FinanceApi.d(_team!['gen1_rate']) * 100).toStringAsFixed(1)}%)'}',
                  cobaltSoft),
            ],
          ),
          const SizedBox(height: 10),
          // Invite code & share
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: McColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: McColors.surfaceContainerHigh.withValues(alpha: 0.6)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '专属邀请码',
                      style: McText.mono(
                          size: 12, color: McColors.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: McColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(4),
                    border:
                        Border.all(color: cobalt.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _inviteCode ?? '加载中…',
                        style: McText.mono(
                            size: 16,
                            weight: FontWeight.w700,
                            color: cobaltSoft,
                            letterSpacing: 1),
                      ),
                      GestureDetector(
                        onTap: _inviteCode == null
                            ? null
                            : () => _copy(_inviteCode!, '已复制邀请码'),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.content_copy,
                                size: 15, color: cobaltSoft),
                            const SizedBox(width: 4),
                            Text(
                              '复制',
                              style: McText.mono(
                                  size: 12,
                                  weight: FontWeight.w700,
                                  color: cobaltSoft),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // 直达邀请好友
                Material(
                  color: McColors.surfaceContainerHigh.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => Navigator.pushNamed(context, '/invite'),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: McColors.surfaceContainerHigh),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.card_giftcard,
                              size: 16, color: McColors.primarySoft),
                          const SizedBox(width: 6),
                          Text(
                            '邀请好友 · 邀请码与补填',
                            style: McText.display(
                                size: 13,
                                weight: FontWeight.w600,
                                color: McColors.onSurface),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_forward,
                              size: 16, color: McColors.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // 直达分佣中心
                Material(
                  color: cobalt.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => Navigator.pushNamed(context, '/commission'),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: cobalt.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '直达合伙人分佣中心看板',
                            style: McText.display(
                                size: 13,
                                weight: FontWeight.w700,
                                color: cobaltSoft),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_forward,
                              size: 16, color: cobaltSoft),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Recent feed
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '最近返佣记录',
                style: McText.mono(
                    size: 12,
                    weight: FontWeight.w700,
                    color: McColors.onSurfaceVariant,
                    letterSpacing: 1),
              ),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/commission'),
                child: Text(
                  '查看全部明细',
                  style: McText.mono(
                      size: 12, weight: FontWeight.w700, color: cobaltSoft),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_recentComms.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              child: Text(
                '暂无返佣记录, 邀请好友购买产品后按结算收益返佣',
                style: McText.sans(size: 12, color: McColors.onSurfaceVariant),
              ),
            )
          else
            for (final r in _recentComms) ...[
              _feedItem(
                icon: Icons.swap_horiz,
                iconColor: McColors.tertiary,
                iconBg: McColors.tertiary.withValues(alpha: 0.1),
                title:
                    '来自 ${(r['buyer_username'] ?? '用户#${r['buyer_id']}')} · ${r['gen'] ?? '-'}代返佣',
                sub:
                    '订单#${r['order_id']} 第${r['period_no'] ?? '-'}期 · 比例 ${(FinanceApi.d(r['rate']) * 100).toStringAsFixed(2)}%',
                amount: '+${FinanceApi.d(r['amount']).toStringAsFixed(2)}',
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  Widget _metricCell(String label, String value, Color valueColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: McColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: McColors.surfaceContainerHighest),
        ),
        child: Column(
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: McText.mono(
                  size: 12,
                  weight: FontWeight.w700,
                  color: McColors.onSurfaceVariant,
                  letterSpacing: 1),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: McText.display(
                    size: 16, weight: FontWeight.w700, color: valueColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _feedItem({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String sub,
    required String amount,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
            color: McColors.surfaceContainerHigh.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(icon, size: 16, color: iconColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: McText.mono(
                            size: 12, color: McColors.onSurface),
                      ),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: McText.mono(
                            size: 12,
                            weight: FontWeight.w700,
                            color: McColors.onSurfaceVariant,
                            letterSpacing: 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: McText.display(
                    size: 16,
                    weight: FontWeight.w700,
                    color: McColors.tertiary),
              ),
              Text(
                'USDT',
                style: McText.mono(
                    size: 12,
                    weight: FontWeight.w700,
                    color: McColors.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- 4. 客服支持 ----
  Widget _settingsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.support_agent, size: 18, color: cobaltSoft),
              const SizedBox(width: 4),
              Text(
                '客服支持',
                style: McText.display(size: 16, weight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _linkTile(Icons.support_agent, McColors.tertiary, '7x24 在线客服'),
        ],
      ),
    );
  }

  Widget _linkTile(IconData icon, Color iconColor, String text) {
    return Material(
      color: McColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {},
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: McColors.surfaceContainerHigh.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: iconColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: McText.display(
                            size: 13,
                            weight: FontWeight.w500,
                            color: McColors.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 16, color: McColors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration _cardDeco() {
    return BoxDecoration(
      color: McColors.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: McColors.surfaceContainerHigh),
      boxShadow: const [
        BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 6)),
      ],
    );
  }
}

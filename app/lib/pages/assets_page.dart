import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/auth.dart';
import '../services/feature_flag.dart';
import '../services/finance_api.dart';
import '../services/invite_api.dart';
import '../widgets/convert_sheet.dart';
import 'change_password_page.dart';
import 'devices_page.dart';
import 'price_alerts_page.dart';
import 'profile_page.dart';
import 'totp_page.dart';

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
      safe(() => FeatureFlag.instance.refresh()), // 钱包开关, 进页刷新
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

  /// 收益→本金转化入口: 打开公共转化弹层, 成功后刷新资产数据.
  Future<void> _openConvert() async {
    final incomeBal = FinanceApi.d(_acct?['income_balance']);
    final done = await showConvertSheet(context, incomeBal);
    if (done) _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 32),
      children: [
        _identityCard(),
        const SizedBox(height: 20),
        // 终端资产总值卡片: 钱包开关关闭时整卡隐藏 (含充值/提现/总值)
        ListenableBuilder(
          listenable: FeatureFlag.instance,
          builder: (context, _) {
            if (!FeatureFlag.instance.walletEnabled) {
              return const SizedBox.shrink();
            }
            return Column(
              children: [
                _assetCard(),
                const SizedBox(height: 20),
              ],
            );
          },
        ),
        // 理财中心 + 合伙人分佣已迁入独立「理财」tab (finance_page.dart, 编译期开关控制显隐).
        // 联系客服卡片已隐藏 (需求).
        // 快捷功能 + 账号安全
        _quickToolsCard(),
        const SizedBox(height: 20),
        _securityCard(),
      ],
    );
  }

  // ---- 快捷功能 (信息/工具类, 审核安全) ----
  Widget _quickToolsCard() {
    final items = [
      (Icons.notifications_active_outlined, tr('assets_qt_price_alert'),
          () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PriceAlertsPage()))),
      (Icons.devices_outlined, tr('assets_qt_devices'),
          () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DevicesPage()))),
      (Icons.lock_reset_outlined, tr('assets_qt_change_pw'),
          () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ChangePasswordPage()))),
      (Icons.settings_outlined, tr('assets_qt_settings'),
          () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ProfilePage()))),
    ];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('assets_qt_title'),
              style: McText.display(size: 16, weight: FontWeight.w700)),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.95,
            children: [
              for (final (icon, label, onTap) in items)
                Material(
                  color: McColors.surfaceContainerHigh.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onTap,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 22, color: McColors.primarySoft),
                        const SizedBox(height: 6),
                        Text(label,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: McText.sans(size: 12, weight: FontWeight.w600)),
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

  // ---- 账号安全状态 ----
  Widget _securityCard() {
    return ListenableBuilder(
      listenable: AuthStore.instance,
      builder: (context, _) {
        final auth = AuthStore.instance;
        Widget row(IconData icon, String label, bool ok, Widget page) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: InkWell(
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => page)),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: McColors.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(label,
                        style: McText.sans(size: 13, weight: FontWeight.w600)),
                  ),
                  Icon(
                    ok ? Icons.check_circle : Icons.error_outline,
                    size: 16,
                    color: ok ? McColors.tertiary : McColors.goldBright,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    ok ? tr('status_set') : tr('status_unset'),
                    style: McText.sans(
                        size: 11,
                        color: ok ? McColors.tertiary : McColors.goldBright),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right,
                      size: 16, color: McColors.onSurfaceVariant),
                ],
              ),
            ),
          );
        }
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: _cardDeco(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('assets_sec_title'),
                  style: McText.display(size: 16, weight: FontWeight.w700)),
              const SizedBox(height: 6),
              row(Icons.lock_outline, tr('sec_login_password'), true,
                  const ChangePasswordPage()),
              const Divider(height: 1, color: McColors.outlineVariant),
              row(Icons.verified_user_outlined, tr('sec_2fa'), auth.has2fa,
                  const TotpPage()),
              const Divider(height: 1, color: McColors.outlineVariant),
              row(Icons.mail_outline, tr('assets_sec_email'),
                  (auth.email ?? '').isNotEmpty, const ProfilePage()),
            ],
          ),
        );
      },
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
                                    // 团队等级徽章: 理财开关关闭时隐藏 (资质待批)
                                    if (FeatureFlag.instance.financeEnabled) ...[
                                      const SizedBox(width: 6),
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
                                                  ? tr('assets_team')
                                                  : tr('assets_team_level').replaceAll('{n}', '${_team!['team_level'] ?? 0}'),
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
          // 邀请码整行 chip: 理财开关关闭时隐藏 (资质待批)
          if (FeatureFlag.instance.financeEnabled)
          GestureDetector(
            onTap: _inviteCode == null
                ? null
                : () => _copy(_inviteCode!, tr('assets_invite_copied')),
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
                  Text(tr('assets_invite_code'),
                      style: McText.sans(
                          size: 12, color: McColors.onSurfaceVariant)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _inviteCode ?? tr('assets_loading'),
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
          // VIP / 团队等级条: 理财开关关闭时隐藏 (资质待批)
          if (FeatureFlag.instance.financeEnabled) ...[
            const SizedBox(height: 10),
            _levelStrip(),
          ],
        ],
      ),
    );
  }

  /// 等级条: VIP / 团队当前等级 + 升级差距 (数据同 /vip /team 详情页).
  Widget _levelStrip() {
    final vipLv = _vip?['vip_level'] as int? ?? 0;
    final vipGap = _vip?['gap_to_next'];
    final vipNext = _vip?['next_level'] as int?;
    final teamLv = _team?['team_level'] as int? ?? 0;
    final teamNext = _team?['next_level'] as int?;
    final memberGap = _team?['next_member_gap'] as int? ?? 0;
    final holdingGap = FinanceApi.d(_team?['next_holding_gap']);

    final vipSub = _vip == null
        ? tr('assets_loading')
        : (vipGap == null || vipNext == null)
            ? tr('vip_max_level')
            : '${tr('vip_to_next').replaceAll('{n}', '$vipNext')} ${FinanceApi.d(vipGap).toStringAsFixed(0)} USDT';
    final teamSub = _team == null
        ? tr('assets_loading')
        : teamNext == null
            ? tr('team_max_level')
            : tr('team_to_next')
                .replaceAll('{next}', '$teamNext')
                .replaceAll('{member_gap}', '$memberGap')
                .replaceAll('{holding_gap}', holdingGap.toStringAsFixed(0));

    return Row(
      children: [
        Expanded(
          child: _levelCell(
            tr('assets_vip_level').replaceAll('{n}', '$vipLv'),
            vipSub,
            McColors.goldBright,
            () => Navigator.pushNamed(context, '/vip'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _levelCell(
            tr('assets_team_level').replaceAll('{n}', '$teamLv'),
            teamSub,
            cobaltSoft,
            () => Navigator.pushNamed(context, '/team'),
          ),
        ),
      ],
    );
  }

  Widget _levelCell(String title, String sub, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: McColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: McText.mono(size: 12, weight: FontWeight.w700, color: color)),
            const SizedBox(height: 3),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: McText.sans(size: 11, color: McColors.onSurfaceVariant),
            ),
          ],
        ),
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
                tr('assets_total_value'),
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
              Flexible(
                child: Text.rich(
                  TextSpan(
                    text: tr('assets_available'),
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
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
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
              Flexible(
                child: Text.rich(
                  TextSpan(
                    text: tr('assets_holding'),
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
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
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
              Flexible(
                child: Text.rich(
                  TextSpan(
                    text: tr('assets_pending'),
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
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Action buttons (整卡由外层 FeatureFlag 控制显隐, 这里直接渲染)
          Row(
            children: [
              Expanded(
                child: _actionBtn(
                  icon: Icons.bolt,
                  iconColor: Colors.white,
                  text: tr('assets_deposit'),
                  primary: true,
                  onTap: () => Navigator.pushNamed(context, '/deposit'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionBtn(
                  icon: Icons.arrow_outward,
                  iconColor: McColors.onSurfaceVariant,
                  text: tr('assets_withdraw'),
                  onTap: () => Navigator.pushNamed(context, '/withdraw'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionBtn(
                  icon: Icons.sync_alt,
                  iconColor: cobaltSoft,
                  text: tr('assets_wallet_matrix'),
                  onTap: () =>
                      Navigator.pushNamed(context, '/wallet-matrix'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 收益→本金转化 (收服务费, 报价确认后执行; 与资金明细页同一弹层)
          Row(
            children: [
              Expanded(
                child: _actionBtn(
                  icon: Icons.currency_exchange,
                  iconColor: McColors.goldBright,
                  text: tr('assets_convert'),
                  onTap: _openConvert,
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
                  tr('assets_multi_chain'),
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

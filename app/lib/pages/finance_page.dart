import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/feature_flag.dart';
import '../services/finance_api.dart';
import '../services/invite_api.dart';

/// 理财 — bottom-nav tab (FINANCE_ENABLED 编译期开启时出现, 位于第 3 位).
/// 理财中心功能直达 + 合伙人分佣看板, 自「我的」页迁出独立成 tab.
/// Content body only: scrollable, h-pad 14, top 16, bottom 32.
class FinancePage extends StatefulWidget {
  const FinancePage({super.key});

  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage> {
  static const cobalt = Color(0xFF2E5CFF);
  static const cobaltSoft = Color(0xFF85A5FF);

  String? _inviteCode;
  Map<String, dynamic>? _team; // 团队等级/有效人数/返佣比例
  Map<String, dynamic>? _commSummary; // 佣金汇总
  List<dynamic> _recentComms = const []; // 最近返佣记录

  @override
  void initState() {
    super.initState();
    _loadInvite();
    _loadData();
  }

  /// 邀请码 (分佣看板展示, 点击复制). 静默容错.
  Future<void> _loadInvite() async {
    try {
      final info = await InviteApi.me();
      if (!mounted) return;
      setState(() => _inviteCode = info.inviteCode);
    } catch (_) {/* 静默 */}
  }

  /// 团队/佣金真实数据. 单项失败静默, 不阻塞整页.
  Future<void> _loadData() async {
    Future<void> safe(Future<void> Function() f) async {
      try {
        await f();
      } catch (_) {/* 静默 */}
    }

    await Future.wait([
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
    return RefreshIndicator(
      color: cobalt,
      backgroundColor: McColors.surfaceContainer,
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 32),
        children: [
          _financeCenterCard(),
          const SizedBox(height: 20),
          _commissionCard(),
        ],
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
            tr('assets_finance_center'),
            style: McText.display(size: 16, weight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          ListenableBuilder(
            listenable: FeatureFlag.instance,
            builder: (context, _) {
              final walletOn = FeatureFlag.instance.walletEnabled;
              final items = [
                ('/products', Icons.savings_outlined, tr('assets_products')),
                ('/vip', Icons.workspace_premium_outlined, tr('assets_my_vip')),
                ('/team', Icons.groups_outlined, tr('assets_my_team')),
                ('/orders', Icons.receipt_long_outlined, tr('assets_my_orders')),
                ('/funds', Icons.account_balance_wallet_outlined, tr('assets_fund_details')),
                // 提现入口随钱包开关显隐
                if (walletOn)
                  ('/withdraw', Icons.outbox_outlined, tr('assets_withdraw_short')),
              ];
              return GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                padding: EdgeInsets.zero, // 否则 primary 滚动视图自动吃状态栏 inset, 标题下出现大空隙
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.5,
                children: [
                  for (final (route, icon, label) in items)
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
              );
            },
          ),
        ],
      ),
    );
  }

  // ---- 合伙人分佣体系看板 ----
  Widget _commissionCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
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
                    tr('assets_partner_system'),
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
                  tr('assets_protocol_system'),
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
                          tr('assets_total_commission'),
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
                          tr('assets_commission_settle_note'),
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
                                tr('assets_today_commission'),
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
                          tr('assets_income_settle_note'),
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
                  tr('assets_valid_invitees'),
                  _team == null ? '--' : tr('assets_people').replaceAll('{n}', '${_team!['member_count'] ?? 0}'),
                  McColors.onSurface),
              const SizedBox(width: 10),
              _metricCell(
                  tr('assets_today_commission'),
                  _commSummary == null
                      ? '--'
                      : '+${FinanceApi.d(_commSummary!['today']).toStringAsFixed(2)}',
                  McColors.tertiary),
              const SizedBox(width: 10),
              _metricCell(
                  tr('assets_team_level_label'),
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
                      tr('assets_exclusive_invite_code'),
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
                        _inviteCode ?? tr('assets_loading'),
                        style: McText.mono(
                            size: 16,
                            weight: FontWeight.w700,
                            color: cobaltSoft,
                            letterSpacing: 1),
                      ),
                      GestureDetector(
                        onTap: _inviteCode == null
                            ? null
                            : () => _copy(_inviteCode!, tr('assets_invite_copied')),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.content_copy,
                                size: 15, color: cobaltSoft),
                            const SizedBox(width: 4),
                            Text(
                              tr('assets_copy'),
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
                            tr('assets_invite_friends'),
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
                            tr('assets_goto_commission_center'),
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
                tr('assets_recent_commissions'),
                style: McText.mono(
                    size: 12,
                    weight: FontWeight.w700,
                    color: McColors.onSurfaceVariant,
                    letterSpacing: 1),
              ),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/commission'),
                child: Text(
                  tr('assets_view_all'),
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
                tr('assets_no_commission'),
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
                    tr('assets_commission_from').replaceAll('{name}', '${r['buyer_username'] ?? '${tr('assets_user_prefix')}${r['buyer_id']}'}').replaceAll('{gen}', '${r['gen'] ?? '-'}'),
                sub:
                    tr('assets_commission_sub').replaceAll('{order}', '${r['order_id']}').replaceAll('{period}', '${r['period_no'] ?? '-'}').replaceAll('{rate}', (FinanceApi.d(r['rate']) * 100).toStringAsFixed(2)),
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

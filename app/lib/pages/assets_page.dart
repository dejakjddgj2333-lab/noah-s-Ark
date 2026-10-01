import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/auth.dart';
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

  bool _whaleAlert = true;
  bool _liquidationAudio = true;
  String? _inviteCode;

  @override
  void initState() {
    super.initState();
    _loadInvite();
  }

  /// 邀请码 (身份卡 chip 展示, 点击复制). 静默容错.
  Future<void> _loadInvite() async {
    try {
      final info = await InviteApi.me();
      if (!mounted) return;
      setState(() => _inviteCode = info.inviteCode);
    } catch (_) {/* 静默 */}
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
                                  ],
                                ),
                                const SizedBox(height: 2),
                                // ID + 邀请码 (点击复制).
                                GestureDetector(
                                  onTap: _inviteCode == null
                                      ? null
                                      : () =>
                                          _copy(_inviteCode!, '已复制邀请码'),
                                  child: Text(
                                    'ID: ${auth.userId ?? '-'}'
                                    '${_inviteCode == null ? '' : ' · 邀请码: $_inviteCode'}',
                                    style: McText.mono(
                                      size: 12,
                                      weight: FontWeight.w700,
                                      color: McColors.onSurfaceVariant,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right,
                              size: 18, color: McColors.onSurfaceVariant),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 返佣等级徽章 (占位, 待返佣系统上线后对接真实等级).
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: cobalt.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border:
                            Border.all(color: cobalt.withValues(alpha: 0.4)),
                        boxShadow: [
                          BoxShadow(
                            color: cobalt.withValues(alpha: 0.25),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.diamond,
                              size: 14, color: cobaltSoft),
                          const SizedBox(width: 6),
                          Text(
                            '钻石合伙人 45%',
                            style: McText.mono(
                              size: 12,
                              weight: FontWeight.w700,
                              color: cobaltSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          // Web3 wallet address pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: McColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: McColors.surfaceContainerHigh.withValues(alpha: 0.6)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const McGlowDot(color: McColors.tertiary, size: 8),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '0x3Fa8...9e42',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: McText.mono(
                              size: 12,
                              weight: FontWeight.w600,
                              color: McColors.onSurface),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: cobalt.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: cobalt.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          'Arbitrum One',
                          style: McText.mono(
                              size: 12,
                              weight: FontWeight.w700,
                              color: cobaltSoft),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () => _copy(
                          '0x3Fa8D081F082987a1C54302619E42', '已复制钱包地址'),
                      icon: const Icon(Icons.content_copy, size: 16),
                      color: McColors.onSurfaceVariant,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      tooltip: '复制钱包地址',
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.power_settings_new, size: 16),
                      color: McColors.onSurfaceVariant,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      tooltip: '断开连接',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- 2. 链上钱包充值与资产总览 ----
  Widget _assetCard() {
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.trending_up,
                      size: 14, color: McColors.tertiary),
                  const SizedBox(width: 4),
                  Text(
                    '24H 净流 +\$1,240',
                    style: McText.mono(
                        size: 12,
                        weight: FontWeight.w700,
                        color: McColors.tertiary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '\$12,850.00',
                style: McText.display(
                  size: 32,
                  weight: FontWeight.w700,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '≈ ¥93,162.50',
                style: McText.mono(
                    size: 12, color: McColors.onSurfaceVariant),
              ),
            ],
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
                      text: '10,240.00',
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
                  text: '策略保证金: ',
                  style: McText.mono(
                      size: 12,
                      weight: FontWeight.w700,
                      color: McColors.onSurfaceVariant),
                  children: [
                    TextSpan(
                      text: '2,610.00',
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
                  onTap: () {},
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionBtn(
                  icon: Icons.sync_alt,
                  iconColor: cobaltSoft,
                  text: '钱包矩阵',
                  onTap: () {},
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
                for (final c in ['Arbitrum', 'TRC20', 'ERC20', 'BSC', 'Solana'])
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
                            '\$4,680.50',
                            style: McText.display(
                                size: 20,
                                weight: FontWeight.w700,
                                color: cobaltSoft),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '历史结算到账率 100%',
                          style: McText.mono(
                              size: 12, color: McColors.tertiary),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
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
                                '待结算收益',
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
                            '\$342.10',
                            style: McText.display(
                                size: 20,
                                weight: FontWeight.w700,
                                color: McColors.onSurface),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '每周一 00:00 (UTC+8) 划转',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: McText.mono(size: 12, color: cobaltSoft),
                        ),
                      ],
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
              _metricCell('有效受邀者', '148 人', McColors.onSurface),
              const SizedBox(width: 10),
              _metricCell('今日贡献', '+\$86.40', McColors.tertiary),
              const SizedBox(width: 10),
              _metricCell('分佣级别', 'L3 (45%)', cobaltSoft),
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
                    Text(
                      '推广专属链接',
                      style: McText.mono(
                          size: 12, color: McColors.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Container(
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
                              'MC-892104',
                              style: McText.mono(
                                  size: 16,
                                  weight: FontWeight.w700,
                                  color: cobaltSoft,
                                  letterSpacing: 1),
                            ),
                            GestureDetector(
                              onTap: () => _copy('MC-892104', '已复制'),
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
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {},
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF363940),
                          borderRadius: BorderRadius.circular(4),
                          border:
                              Border.all(color: cobalt.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.qr_code_2,
                                size: 16, color: McColors.onSurface),
                            const SizedBox(width: 4),
                            Text(
                              '海报',
                              style: McText.mono(
                                  size: 12,
                                  weight: FontWeight.w600,
                                  color: McColors.onSurface),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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
              Text(
                '查看全网明细',
                style: McText.mono(
                    size: 12, weight: FontWeight.w700, color: cobaltSoft),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _feedItem(
            icon: Icons.swap_horiz,
            iconColor: McColors.tertiary,
            iconBg: McColors.tertiary.withValues(alpha: 0.1),
            title: '合约交易返佣 • 0x4a...8c',
            sub: '10分钟前 · 交易额 \$42,000',
            amount: '+\$14.20',
          ),
          const SizedBox(height: 8),
          _feedItem(
            icon: Icons.currency_exchange,
            iconColor: cobaltSoft,
            iconBg: cobalt.withValues(alpha: 0.15),
            title: '充值交易分润 • 0x7e...3d',
            sub: '1小时前 · 新入金结算',
            amount: '+\$28.50',
          ),
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

  // ---- 4. 终端监控与量化偏好设置 ----
  Widget _settingsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune, size: 18, color: cobaltSoft),
              const SizedBox(width: 4),
              Text(
                '终端监控与量化偏好设置',
                style: McText.display(size: 16, weight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _settingRow(
            icon: Icons.notifications_active,
            iconColor: cobalt,
            title: '全网大额巨鲸预警阈值',
            sub: '当前触发: > \$1,000,000 USDT',
            subColor: McColors.onSurfaceVariant,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: McColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '>1M 开关开启',
                    style: McText.mono(
                        size: 12, weight: FontWeight.w700, color: cobaltSoft),
                  ),
                ),
                const SizedBox(width: 8),
                _toggle(_whaleAlert, (v) => setState(() => _whaleAlert = v)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _settingRow(
            icon: Icons.volume_up,
            iconColor: McColors.error,
            title: '极端多空爆仓音频提醒',
            sub: '高密度低延迟穿透声效 (已启用)',
            subColor: McColors.onSurfaceVariant,
            trailing: _toggle(
                _liquidationAudio, (v) => setState(() => _liquidationAudio = v)),
          ),
          const SizedBox(height: 10),
          _settingRow(
            icon: Icons.speed,
            iconColor: McColors.tertiary,
            title: '机构专属 RPC 极速节点',
            sub: 'Arbitrum FlashNode 延迟: 18ms',
            subColor: McColors.tertiary,
            trailing: GestureDetector(
              onTap: () {},
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: McColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(4),
                  border:
                      Border.all(color: McColors.surfaceContainerHighest),
                ),
                child: Text(
                  '切换节点',
                  style: McText.mono(
                      size: 12,
                      weight: FontWeight.w700,
                      color: McColors.onSurface),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // 2 link tiles
          Row(
            children: [
              Expanded(
                child: _linkTile(
                    Icons.verified_user, cobaltSoft, '规则与安全中心'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child:
                    _linkTile(Icons.support_agent, McColors.tertiary, '7x24 在线客服'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // TG channel
          _settingRow(
            icon: Icons.forum,
            iconColor: cobalt,
            title: '量化合伙人 TG 官方频道',
            sub: '明策 VIP Alpha 策略情报独家群',
            subColor: McColors.onSurfaceVariant,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: cobalt,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(color: cobalt.withValues(alpha: 0.45), blurRadius: 14),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '进入群组',
                    style: McText.mono(
                        size: 12, weight: FontWeight.w700, color: Colors.white),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward,
                      size: 13, color: Colors.white),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String sub,
    required Color subColor,
    required Widget trailing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLowest,
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
                Icon(icon, size: 20, color: iconColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: McText.display(
                            size: 14,
                            weight: FontWeight.w600,
                            color: McColors.onSurface),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: McText.mono(size: 12, color: subColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
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

  Widget _toggle(bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40,
        height: 20,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: value ? cobalt : McColors.surfaceContainerHigh,
          boxShadow: value
              ? [BoxShadow(color: cobalt.withValues(alpha: 0.4), blurRadius: 12)]
              : null,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 16,
            height: 16,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
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

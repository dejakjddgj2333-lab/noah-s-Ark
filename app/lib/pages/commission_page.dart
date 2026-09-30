import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../core/widgets.dart';

/// 合伙人分佣 — pushed route ('/commission'). Full Scaffold with own app bar.
class CommissionPage extends StatefulWidget {
  const CommissionPage({super.key});

  @override
  State<CommissionPage> createState() => _CommissionPageState();
}

class _CommissionPageState extends State<CommissionPage> {
  int _mainTab = 0; // 0: 渠道网络, 1: 返佣结算流水
  int _netFilter = 0; // 0 直推, 1 间接, 2 机构
  int _settleFilter = 0; // 0 全部动态 ...

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
    return Scaffold(
      backgroundColor: McColors.surface,
      appBar: AppBar(
        backgroundColor: McColors.surface.withValues(alpha: 0.85),
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 44,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          color: McColors.onSurface,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          '合伙人分佣',
          style: McText.sans(size: 16, weight: FontWeight.w600),
        ),
        titleSpacing: 0,
        actions: [
          TextButton.icon(
            onPressed: () {},
            style: TextButton.styleFrom(
              backgroundColor:
                  McColors.surfaceContainerHigh.withValues(alpha: 0.7),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.help_outline,
                size: 15, color: McColors.secondary),
            label: Text(
              '规则说明',
              style:
                  McText.sans(size: 12, color: McColors.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.share, size: 17),
            color: McColors.onSurfaceVariant,
            style: IconButton.styleFrom(
              backgroundColor:
                  McColors.surfaceContainerHigh.withValues(alpha: 0.7),
              shape: const CircleBorder(),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(right: 12, left: 2),
            child: CircleAvatar(
              radius: 14,
              backgroundColor: McColors.surfaceContainerHigh,
              child: Icon(Icons.person, size: 18, color: McColors.primary),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 40),
        children: [
          _heroCard(),
          const SizedBox(height: 8),
          _levelCard(),
          const SizedBox(height: 8),
          _inviteCard(),
          const SizedBox(height: 8),
          _tabModule(),
        ],
      ),
    );
  }

  // ---- 1. Hero: tier + balance engine ----
  Widget _heroCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tier bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _tierPill(
                      icon: Icons.verified,
                      text: 'Tier 3 钻石合伙人',
                      color: McColors.secondary,
                      bg: McColors.surfaceContainer,
                    ),
                    _tierPill(
                      text: '45.0% 永续返佣',
                      color: McColors.tertiary,
                      bg: const Color(0xFF007E49).withValues(alpha: 0.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const McGlowDot(color: McColors.tertiary, size: 6),
                  const SizedBox(width: 6),
                  Text(
                    '实时链上清算',
                    style: McText.sans(
                        size: 12,
                        weight: FontWeight.w600,
                        color: McColors.onSurfaceVariant,
                        letterSpacing: 0.5),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Balance block
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '累计已结算收益 (USDT)',
                style: McText.sans(size: 12, color: McColors.onSurfaceVariant),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF007E49).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.trending_up,
                        size: 13, color: McColors.tertiary),
                    const SizedBox(width: 2),
                    Text(
                      '+12.4% 本周',
                      style: McText.sans(
                          size: 12,
                          weight: FontWeight.w600,
                          color: McColors.tertiary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '\$18,452.80',
            style: McText.sans(
              size: 34,
              weight: FontWeight.w700,
              height: 1.1,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 16),
          // Quick action box
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: McColors.surfaceContainerLowest.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: McColors.surfaceContainerHigh.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '可提现佣金',
                        style: McText.sans(
                            size: 12,
                            weight: FontWeight.w600,
                            color: McColors.onSurfaceVariant,
                            letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text.rich(
                          TextSpan(
                            text: '\$3,240.50 ',
                            style: McText.sans(
                              size: 20,
                              weight: FontWeight.w700,
                              color: McColors.primary,
                            ),
                            children: [
                              TextSpan(
                                text: 'USDT',
                                style: McText.sans(
                                  size: 12,
                                  weight: FontWeight.w500,
                                  color: McColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: McColors.primaryContainer,
                        foregroundColor: McColors.onPrimaryContainer,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                        shadowColor: McColors.primaryContainer,
                      ),
                      icon: const Icon(Icons.account_balance_wallet, size: 16),
                      label: Text(
                        '立即提现',
                        style: McText.sans(
                            size: 12,
                            weight: FontWeight.w600,
                            color: McColors.onPrimaryContainer),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: McColors.surfaceContainerHighest,
                        foregroundColor: McColors.onSurface,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        '划转',
                        style: McText.sans(
                            size: 12,
                            weight: FontWeight.w500,
                            color: McColors.onSurface),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Micro stats strip (4 cols)
          Row(
            children: [
              _statCell('待结算预估', '\$420.00', McColors.onSurface),
              const SizedBox(width: 8),
              _statCell('有效直推', '48 人', McColors.secondary),
              const SizedBox(width: 8),
              _statCell('间接网络', '312 人', McColors.onSurface),
              const SizedBox(width: 8),
              _statCell('昨日净收益', '+\$168.2', McColors.tertiary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tierPill({
    IconData? icon,
    required String text,
    required Color color,
    required Color bg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: McText.sans(
                size: 12,
                weight: FontWeight.w600,
                color: color,
                letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _statCell(String label, String value, Color valueColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: McColors.surfaceContainer.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: McColors.surfaceContainerHigh.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: McText.sans(
                  size: 12,
                  weight: FontWeight.w600,
                  color: McColors.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: McText.sans(
                    size: 13, weight: FontWeight.w600, color: valueColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 2. Level progress & tier ladder ----
  Widget _levelCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: McColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.workspace_premium,
                      size: 20, color: McColors.secondary),
                  const SizedBox(width: 8),
                  Text(
                    '合伙人等级晋升',
                    style: McText.sans(size: 15, weight: FontWeight.w600),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () {},
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '距黑钻还差 28%',
                      style: McText.sans(
                          size: 12,
                          weight: FontWeight.w500,
                          color: McColors.secondary),
                    ),
                    const Icon(Icons.chevron_right,
                        size: 14, color: McColors.secondary),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '当前: 钻石 45%',
                style: McText.sans(
                    size: 12,
                    weight: FontWeight.w600,
                    color: McColors.secondary),
              ),
              Text(
                '目标: 黑钻合伙人 50%',
                style: McText.sans(
                    size: 12, color: McColors.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 8,
              padding: const EdgeInsets.all(2),
              color: McColors.surfaceContainerLowest,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: 0.72,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      gradient: const LinearGradient(
                        colors: [
                          McColors.primaryContainer,
                          McColors.secondary,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _milestoneCell('月团队交易量', '72%', McColors.primary,
                  '\$7.2M / \$10.0M'),
              const SizedBox(width: 10),
              _milestoneCell('活跃跟单用户', '96%', McColors.tertiary, '48 / 50 人'),
            ],
          ),
          const SizedBox(height: 12),
          // Privileges chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _privChip(Icons.insights, McColors.primary, '专属量化研报'),
                const SizedBox(width: 8),
                _privChip(
                    Icons.support_agent, McColors.secondary, '1v1 客户经理'),
                const SizedBox(width: 8),
                _privChip(Icons.speed, McColors.tertiary, '高频节点减免'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _milestoneCell(
      String label, String pct, Color pctColor, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: McColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: McColors.surfaceContainerHigh.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: McText.sans(
                        size: 12, color: McColors.onSurfaceVariant),
                  ),
                ),
                Text(
                  pct,
                  style: McText.sans(
                      size: 12, weight: FontWeight.w600, color: pctColor),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: McText.sans(
                  size: 12, weight: FontWeight.w600, color: McColors.onSurface),
            ),
          ],
        ),
      ),
    );
  }

  Widget _privChip(IconData icon, Color color, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: McText.sans(
                size: 12,
                weight: FontWeight.w600,
                color: McColors.onSurfaceVariant,
                letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  // ---- 3. Referral code & share center ----
  Widget _inviteCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: McColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.share, size: 20, color: McColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    '专属推广渠道与邀请码',
                    style: McText.sans(size: 15, weight: FontWeight.w600),
                  ),
                ],
              ),
              Text(
                '实时返现生效',
                style:
                    McText.sans(size: 12, color: McColors.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _copyRow(
            label: '专属邀请码',
            value: 'MC-8899X',
            valueStyle: McText.sans(
                size: 18,
                weight: FontWeight.w700,
                color: McColors.onSurface,
                letterSpacing: 1),
            btnText: '复制',
            onCopy: () => _copy('MC-8899X', '已复制'),
          ),
          const SizedBox(height: 10),
          _copyRow(
            label: '推广专属链接',
            value: 'mingce.io/r/8899X',
            valueStyle: McText.sans(
                size: 13,
                weight: FontWeight.w500,
                color: McColors.primary),
            btnText: '复制链接',
            onCopy: () => _copy('https://mingce.io/r/8899X', '已复制链接'),
          ),
          const SizedBox(height: 10),
          // Ratio allocation
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: McColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: McColors.surfaceContainerHigh.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '分佣比例配置',
                      style: McText.sans(
                          size: 12,
                          weight: FontWeight.w500,
                          color: McColors.onSurfaceVariant),
                    ),
                    Text(
                      '总额: 45%',
                      style: McText.sans(
                          size: 12,
                          weight: FontWeight.w600,
                          color: McColors.onSurface),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '自留返佣: 40%',
                      style: McText.sans(
                          size: 12,
                          weight: FontWeight.w600,
                          color: McColors.primary),
                    ),
                    Text(
                      '好友返现: 5%',
                      style: McText.sans(
                          size: 12,
                          weight: FontWeight.w600,
                          color: McColors.secondary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 8,
                    child: Row(
                      children: [
                        Expanded(
                          flex: 888,
                          child: Container(color: McColors.primaryContainer),
                        ),
                        Expanded(
                          flex: 112,
                          child: Container(color: McColors.secondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Share toolbar
          Row(
            children: [
              _shareBtn(Icons.image, McColors.primary, '推广海报'),
              const SizedBox(width: 10),
              _shareBtn(Icons.send, McColors.secondary, '发 Telegram'),
              const SizedBox(width: 10),
              _shareBtn(Icons.qr_code_2, McColors.tertiary, '拓客二维码'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _copyRow({
    required String label,
    required String value,
    required TextStyle valueStyle,
    required String btnText,
    required VoidCallback onCopy,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: McColors.surfaceContainerHigh.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: McText.sans(
                      size: 12,
                      weight: FontWeight.w600,
                      color: McColors.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: valueStyle),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onCopy,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: McColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                btnText,
                style: McText.sans(
                    size: 12,
                    weight: FontWeight.w500,
                    color: McColors.onSurface),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shareBtn(IconData icon, Color color, String text) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: McColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 6),
            Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: McText.sans(
                  size: 12, weight: FontWeight.w500, color: McColors.onSurface),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 4. Tab module: 渠道网络 / 返佣结算流水 ----
  Widget _tabModule() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: McColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Tab header
          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                    color:
                        McColors.surfaceContainerHigh.withValues(alpha: 0.6)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    _mainTabBtn(
                      0,
                      Icons.group,
                      McColors.secondary,
                      '渠道网络',
                      badge: '363',
                    ),
                    const SizedBox(width: 16),
                    _mainTabBtn(
                      1,
                      Icons.receipt_long,
                      McColors.primary,
                      '返佣结算流水',
                    ),
                  ],
                ),
                Text(
                  '全量已存证',
                  style: McText.sans(
                      size: 12, color: McColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_mainTab == 0) _networkPane() else _settlementPane(),
        ],
      ),
    );
  }

  Widget _mainTabBtn(int index, IconData icon, Color iconColor, String text,
      {String? badge}) {
    final active = _mainTab == index;
    return GestureDetector(
      onTap: () => setState(() => _mainTab = index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: active ? McColors.primary : Colors.transparent,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 6),
            Text(
              text,
              style: McText.sans(
                size: 15,
                weight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? McColors.onSurface : McColors.onSurfaceVariant,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: McColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge,
                  style: McText.sans(
                      size: 12,
                      weight: FontWeight.w500,
                      color: McColors.secondary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _networkPane() {
    final filters = ['直推 (48)', '间接 (312)', '机构 (3)'];
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: McColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < filters.length; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => setState(() => _netFilter = i),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _netFilter == i
                                  ? McColors.surfaceContainerHigh
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              filters[i],
                              style: McText.sans(
                                size: 12,
                                weight: _netFilter == i
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: _netFilter == i
                                    ? McColors.onSurface
                                    : McColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            GestureDetector(
              onTap: () {},
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '按交易量',
                    style: McText.sans(
                        size: 12, color: McColors.onSurfaceVariant),
                  ),
                  const Icon(Icons.swap_vert,
                      size: 14, color: McColors.onSurfaceVariant),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _memberItem(
          name: '0x7a8e...8e92',
          tag: 'VIP 6',
          tagColor: McColors.primary,
          tagBg: McColors.primaryContainer.withValues(alpha: 0.2),
          volume: '本月交易量 \$1.82M',
          amount: '+\$452.10',
        ),
        const SizedBox(height: 8),
        _memberItem(
          name: 'Crypto_K***',
          tag: 'VIP 4',
          tagColor: McColors.secondary,
          tagBg: McColors.secondary.withValues(alpha: 0.2),
          volume: '本月交易量 \$940K',
          amount: '+\$289.40',
        ),
        const SizedBox(height: 8),
        _memberItem(
          name: 'AlphaFund_09',
          tag: '机构席位',
          tagColor: McColors.tertiary,
          tagBg: const Color(0xFF007E49).withValues(alpha: 0.3),
          volume: '本月交易量 \$2.40M',
          amount: '+\$618.50',
        ),
      ],
    );
  }

  Widget _memberItem({
    required String name,
    required String tag,
    required Color tagColor,
    required Color tagBg,
    required String volume,
    required String amount,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: McColors.surfaceContainerHigh.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: McColors.surfaceContainerHighest,
                  child: Text(
                    name.characters.first.toUpperCase(),
                    style: McText.sans(
                        size: 14,
                        weight: FontWeight.w700,
                        color: McColors.primary),
                  ),
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
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: McText.sans(
                                  size: 13,
                                  weight: FontWeight.w600,
                                  color: McColors.onSurface),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: tagBg,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              tag,
                              style: McText.sans(
                                  size: 12,
                                  weight: FontWeight.w700,
                                  color: tagColor),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        volume,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: McText.sans(
                            size: 12, color: McColors.onSurfaceVariant),
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
                style: McText.sans(
                    size: 13,
                    weight: FontWeight.w700,
                    color: McColors.tertiary),
              ),
              Text(
                '贡献返佣',
                style: McText.sans(
                    size: 12, color: McColors.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _settlementPane() {
    final chips = ['全部动态', '交易返佣', '策略分成', '提现记录'];
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < chips.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => _settleFilter = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: _settleFilter == i
                          ? McColors.primaryContainer
                          : McColors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      chips[i],
                      style: McText.sans(
                        size: 12,
                        weight: _settleFilter == i
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: _settleFilter == i
                            ? McColors.onPrimaryContainer
                            : McColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _settleItem(
          icon: Icons.candlestick_chart,
          iconColor: McColors.primary,
          iconBg: McColors.primaryContainer.withValues(alpha: 0.15),
          title: 'BTC/USDT 永续高频返佣',
          sub: '2 分钟前 · 来自 0x8a...411e',
          amount: '+\$14.28',
          amountColor: McColors.tertiary,
          status: '已结算',
          statusColor: McColors.onSurfaceVariant,
        ),
        const SizedBox(height: 8),
        _settleItem(
          icon: Icons.notifications_active,
          iconColor: McColors.secondary,
          iconBg: McColors.secondary.withValues(alpha: 0.15),
          title: 'ETH 巨鲸预警策略分成 (30%)',
          sub: '18 分钟前 · 策略订阅分成',
          amount: '+\$45.00',
          amountColor: McColors.tertiary,
          status: '已结算',
          statusColor: McColors.onSurfaceVariant,
        ),
        const SizedBox(height: 8),
        _settleItem(
          icon: Icons.grid_view,
          iconColor: McColors.primary,
          iconBg: McColors.primaryContainer.withValues(alpha: 0.15),
          title: 'SOL/USDT 量化网格返佣',
          sub: '1 小时前 · 来自 VIP_Alpha',
          amount: '+\$6.80',
          amountColor: McColors.tertiary,
          status: '已结算',
          statusColor: McColors.onSurfaceVariant,
        ),
        const SizedBox(height: 8),
        _settleItem(
          icon: Icons.north_east,
          iconColor: McColors.onSurfaceVariant,
          iconBg: McColors.surfaceContainerHighest,
          title: '佣金链上提现',
          sub: '昨天 19:42 · 目标 0x4b...8821',
          amount: '-\$1,500.00',
          amountColor: McColors.onSurface,
          status: '已到账',
          statusColor: McColors.secondary,
        ),
      ],
    );
  }

  Widget _settleItem({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String sub,
    required String amount,
    required Color amountColor,
    required String status,
    required Color statusColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: McColors.surfaceContainerHigh.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: iconColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: McText.sans(
                            size: 13,
                            weight: FontWeight.w600,
                            color: McColors.onSurface),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: McText.sans(
                            size: 12, color: McColors.onSurfaceVariant),
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
                style: McText.sans(
                    size: 13, weight: FontWeight.w700, color: amountColor),
              ),
              Text(
                status,
                style: McText.sans(size: 12, color: statusColor),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

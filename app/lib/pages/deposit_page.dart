import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/widgets.dart';

/// 链上充值 (on-chain deposit). Pushed route ('/deposit') with its own app bar.
class DepositPage extends StatelessWidget {
  const DepositPage({super.key});

  static const _address = 'TX8qWnK2vE83u7PLjY9cMkdP8h1xN92KzLa';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: McColors.surface,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: _DepositAppBar(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
        children: const [
          _SecurityBar(),
          SizedBox(height: 20),
          _AssetCard(),
          SizedBox(height: 20),
          _NetworkCard(),
          SizedBox(height: 20),
          _QrCard(address: _address),
          SizedBox(height: 20),
          _RadarBar(),
          SizedBox(height: 20),
          _RecordsCard(),
        ],
      ),
    );
  }
}

/// Custom app bar: back + title(WEB3) + 规则说明 + share + avatar.
class _DepositAppBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: McColors.surface.withValues(alpha: 0.85),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 1)),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                _roundBtn(
                  icon: Icons.arrow_back,
                  onTap: () => Navigator.maybePop(context),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          '链上充值',
                          style: McText.sans(
                            size: 16,
                            weight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const McPill('WEB3',
                          color: McColors.primary, fontSize: 12, bold: false),
                    ],
                  ),
                ),
                const Spacer(),
                _textBtn(icon: Icons.help_outline, label: '规则说明'),
                const SizedBox(width: 2),
                _roundBtn(icon: Icons.share, onTap: () {}),
                const SizedBox(width: 6),
                const CircleAvatar(
                  radius: 14,
                  backgroundColor: McColors.surfaceContainerHigh,
                  child: Icon(Icons.person, size: 16, color: McColors.primary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _roundBtn({required IconData icon, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: McColors.surfaceContainerHigh.withValues(alpha: 0.6),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: McColors.onSurface),
      ),
    );
  }

  Widget _textBtn({required IconData icon, required String label}) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: McColors.primary),
          const SizedBox(width: 4),
          Text(label, style: McText.sans(size: 12, weight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// 1. Security shield badge bar.
class _SecurityBar extends StatelessWidget {
  const _SecurityBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: McColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user, size: 16, color: McColors.primary),
          const SizedBox(width: 6),
          Text(
            'SECURE SHIELD',
            style: McText.sans(
              size: 12,
              weight: FontWeight.w700,
              color: McColors.primary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 6),
          Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                  color: McColors.outlineVariant, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '硬件冷热隔离 · 慢雾/派盾双重审计',
              style: McText.sans(size: 12, color: McColors.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: McColors.tertiary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const McGlowDot(color: McColors.tertiary, size: 4),
                const SizedBox(width: 4),
                Text(
                  '已认证',
                  style: McText.sans(
                      size: 12, weight: FontWeight.w500, color: McColors.tertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 2. Asset selection + available balance card.
class _AssetCard extends StatelessWidget {
  const _AssetCard();

  @override
  Widget build(BuildContext context) {
    return McCard(
      color: McColors.surfaceContainer,
      borderColor: Colors.transparent,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '选择充币资产',
                style: McText.sans(
                  size: 12,
                  weight: FontWeight.w500,
                  color: McColors.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
              Row(
                children: [
                  Text('可用余额:',
                      style: McText.sans(
                          size: 12, color: McColors.onSurfaceVariant)),
                  const SizedBox(width: 6),
                  Text(
                    '12,450.00 USDT',
                    style: McText.sans(
                        size: 13, weight: FontWeight.w600, color: McColors.onSurface),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Selected coin row
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: McColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF26A17B).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    '₮',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF26A17B),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'USDT',
                            style: McText.sans(
                                size: 18,
                                weight: FontWeight.w600,
                                letterSpacing: -0.2),
                          ),
                          const SizedBox(width: 6),
                          const McChip('Tether USD'),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '≈ \$12,450.00 USD',
                        style: McText.sans(
                            size: 12, color: McColors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Text('切换币种',
                        style: McText.sans(
                            size: 12,
                            weight: FontWeight.w500,
                            color: McColors.onSurfaceVariant)),
                    const Icon(Icons.expand_more,
                        size: 18, color: McColors.onSurfaceVariant),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Quick-select tags
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _tag('USDT', selected: true),
                const SizedBox(width: 8),
                _tag('BTC'),
                const SizedBox(width: 8),
                _tag('ETH'),
                const SizedBox(width: 8),
                _tag('SOL'),
                const SizedBox(width: 8),
                _tag('USDC'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(String label, {bool selected = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: selected
            ? McColors.primaryContainer
            : McColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected) ...[
            const McGlowDot(color: McColors.primary, size: 6),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: McText.sans(
              size: 12,
              weight: FontWeight.w500,
              color: selected
                  ? McColors.onPrimaryContainer
                  : McColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 3. Network selection 2x2 grid card.
class _NetworkCard extends StatelessWidget {
  const _NetworkCard();

  @override
  Widget build(BuildContext context) {
    return McCard(
      color: McColors.surfaceContainer,
      borderColor: Colors.transparent,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    '充值公链网络',
                    style: McText.sans(
                      size: 12,
                      weight: FontWeight.w500,
                      color: McColors.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.info_outline,
                      size: 14, color: McColors.outline),
                ],
              ),
              Row(
                children: [
                  const McGlowDot(color: McColors.tertiary, size: 6),
                  const SizedBox(width: 4),
                  Text(
                    '全链路由畅通',
                    style: McText.sans(
                        size: 12, weight: FontWeight.w500, color: McColors.primary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.5,
            children: const [
              _NetworkTile(
                name: 'TRC20',
                tag: '推荐',
                tagColor: McColors.tertiary,
                chain: 'Tron 主网',
                speed: '费率低 · ~1-2分',
                speedColor: McColors.primary,
                selected: true,
              ),
              _NetworkTile(
                name: 'ERC20',
                right: '12 Confirms',
                chain: 'Ethereum',
                speed: '~3-5分',
                speedColor: McColors.onSurfaceVariant,
              ),
              _NetworkTile(
                name: 'Arbitrum',
                tag: 'L2 极速',
                tagColor: McColors.secondary,
                chain: 'Arbitrum One',
                speed: '< 30秒',
                speedColor: McColors.tertiary,
              ),
              _NetworkTile(
                name: 'Solana',
                right: 'SPL',
                chain: 'High-TPS',
                speed: '< 15秒',
                speedColor: McColors.tertiary,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Params strip
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: McColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                _param('预计到账', '约 2 分钟', McColors.onSurface),
                _param('最小充值额', '10.00 USDT', McColors.onSurface),
                _param('安全入账确认', '1 个区块确认', McColors.tertiary),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _param(String label, String value, Color valueColor) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style:
                  McText.sans(size: 12, color: McColors.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(
            value,
            style: McText.sans(
                size: 12, weight: FontWeight.w600, color: valueColor),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _NetworkTile extends StatelessWidget {
  const _NetworkTile({
    required this.name,
    required this.chain,
    required this.speed,
    required this.speedColor,
    this.tag,
    this.tagColor = McColors.tertiary,
    this.right,
    this.selected = false,
  });

  final String name;
  final String? tag;
  final Color tagColor;
  final String? right;
  final String chain;
  final String speed;
  final Color speedColor;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: selected
            ? McColors.primaryContainer.withValues(alpha: 0.2)
            : McColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: selected
            ? Border.all(color: McColors.primaryContainer.withValues(alpha: 0.5))
            : null,
        boxShadow: selected
            ? [
                BoxShadow(
                  color: McColors.primaryContainer.withValues(alpha: 0.18),
                  blurRadius: 12,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: McText.sans(
                          size: 15,
                          weight: selected ? FontWeight.w700 : FontWeight.w500,
                          letterSpacing: -0.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (tag != null) ...[
                      const SizedBox(width: 6),
                      McPill(tag!, color: tagColor, fontSize: 12, bold: false),
                    ],
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle,
                    size: 18, color: McColors.primary)
              else if (right != null)
                Text(right!,
                    style: McText.mono(size: 12, color: McColors.outline)),
            ],
          ),
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: selected
                      ? McColors.primaryContainer.withValues(alpha: 0.2)
                      : McColors.surfaceContainerHighest.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(chain,
                      style: McText.sans(
                          size: 12, color: McColors.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis),
                ),
                Text(
                  speed,
                  style: McText.sans(
                      size: 12, weight: FontWeight.w600, color: speedColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 4. QR code + custodial address card.
class _QrCard extends StatelessWidget {
  const _QrCard({required this.address});

  final String address;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 16)],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    '专属收款托管地址',
                    style: McText.sans(
                      size: 12,
                      weight: FontWeight.w500,
                      color: McColors.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const McPill('TRC20',
                      color: McColors.primary, fontSize: 12, bold: false),
                ],
              ),
              Row(
                children: [
                  const McGlowDot(color: McColors.tertiary, size: 8),
                  const SizedBox(width: 6),
                  Text(
                    '地址有效中',
                    style: McText.sans(
                        size: 12, weight: FontWeight.w500, color: McColors.tertiary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // QR placeholder
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 4))
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.qr_code_2, size: 160, color: Color(0xFF0B0E14)),
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: McColors.surface,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: McColors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'M',
                      style: McText.sans(
                        size: 13,
                        weight: FontWeight.w900,
                        color: McColors.onPrimaryContainer,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.touch_app, size: 15, color: McColors.primary),
              const SizedBox(width: 4),
              Text(
                '扫描二维码或复制下方地址充币',
                style: McText.sans(size: 12, color: McColors.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Address block
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: McColors.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('TRON 收款地址',
                        style: McText.sans(
                            size: 12, color: McColors.onSurfaceVariant)),
                    Row(
                      children: [
                        const McGlowDot(color: McColors.tertiary, size: 4),
                        const SizedBox(width: 4),
                        Text('已校验通过',
                            style: McText.mono(
                                size: 12, color: McColors.tertiary)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: McColors.surfaceContainerHighest.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectableText(
                    address,
                    style: McText.mono(
                      size: 12,
                      weight: FontWeight.w500,
                      color: McColors.onSurface,
                      letterSpacing: 0.5,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Action buttons
          Row(
            children: [
              Expanded(
                child: _actionBtn(
                  icon: Icons.content_copy,
                  label: '复制充值地址',
                  primary: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionBtn(
                  icon: Icons.download_for_offline,
                  label: '保存充值海报',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Warning tip
            Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: McColors.error.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.info_outline,
                      size: 15, color: McColors.error),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: McText.sans(
                          size: 12,
                          color: const Color(0xFFFFDAD6),
                          height: 1.4),
                      children: [
                        const TextSpan(text: '仅支持接收 '),
                        TextSpan(
                          text: 'TRC20-USDT',
                          style: McText.sans(
                              size: 12,
                              weight: FontWeight.w600,
                              color: McColors.error),
                        ),
                        const TextSpan(
                            text: '，转入其他资产将无法追回。智能合约自动结算到账。'),
                      ],
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
    required String label,
    bool primary = false,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      decoration: BoxDecoration(
        color: primary ? McColors.primaryContainer : McColors.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        boxShadow: primary
            ? [
                BoxShadow(
                  color: McColors.primaryContainer.withValues(alpha: 0.35),
                  blurRadius: 12,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              size: 18,
              color: primary ? McColors.onPrimaryContainer : McColors.onSurface),
          const SizedBox(width: 6),
          Text(
            label,
            style: McText.sans(
              size: 12,
              weight: primary ? FontWeight.w600 : FontWeight.w500,
              color: primary ? McColors.onPrimaryContainer : McColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// 5. On-chain radar listening status bar.
class _RadarBar extends StatelessWidget {
  const _RadarBar();

  @override
  Widget build(BuildContext context) {
    return McCard(
      color: McColors.surfaceContainer,
      borderColor: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: McColors.tertiary.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.radar,
                      size: 16, color: McColors.tertiary),
                ),
                const Positioned(
                  top: 0,
                  right: 0,
                  child: McGlowDot(color: McColors.tertiary, size: 8),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '链上智能雷达监听中',
                        style: McText.sans(
                            size: 13, weight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const McPill('RPC OK',
                        color: McColors.tertiary, fontSize: 12, bold: false),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '毫秒级捕获网络广播，出块后 30 秒内推送通知',
                  style: McText.sans(size: 12, color: McColors.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.sensors, size: 18, color: McColors.outline),
        ],
      ),
    );
  }
}

/// 6. Recent deposit records card.
class _RecordsCard extends StatelessWidget {
  const _RecordsCard();

  @override
  Widget build(BuildContext context) {
    return McCard(
      color: McColors.surfaceContainer,
      borderColor: Colors.transparent,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    '最近充值记录',
                    style: McText.sans(
                      size: 12,
                      weight: FontWeight.w500,
                      color: McColors.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                    decoration: BoxDecoration(
                      color: McColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('3',
                        style: McText.mono(size: 12, color: McColors.onSurface)),
                  ),
                ],
              ),
              Row(
                children: [
                  Text('全部记录',
                      style: McText.sans(size: 12, color: McColors.primary)),
                  const Icon(Icons.chevron_right,
                      size: 14, color: McColors.primary),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _RecordTile(
            amount: '+2,000.00 USDT',
            net: 'TRC20',
            netColor: McColors.onSurfaceVariant,
            meta: '10 分钟前 · TXID: f8e9...3b21',
            confirms: '24 确认数',
          ),
          const SizedBox(height: 8),
          const _RecordTile(
            amount: '+500.00 USDT',
            net: 'Arbitrum',
            netColor: McColors.secondary,
            meta: '昨天 16:30 · TXID: 0x9a...7c1a',
            confirms: 'L2 Finalized',
          ),
          const SizedBox(height: 8),
          const _RecordTile(
            amount: '+0.0500 BTC',
            net: 'BTC Mainnet',
            netColor: Color(0xFFF7931A),
            meta: '3 天前 · TXID: 4d2e...99e1',
            confirms: '3/3 确认',
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.travel_explore,
                  size: 15, color: McColors.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                '查看全部链上存证哈希 (Blockchain Explorer)',
                style: McText.sans(
                    size: 12,
                    weight: FontWeight.w500,
                    color: McColors.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({
    required this.amount,
    required this.net,
    required this.netColor,
    required this.meta,
    required this.confirms,
  });

  final String amount;
  final String net;
  final Color netColor;
  final String meta;
  final String confirms;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: McColors.tertiary.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.call_received,
                    size: 16, color: McColors.tertiary),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        amount,
                        style: McText.sans(
                            size: 14, weight: FontWeight.w600),
                      ),
                      const SizedBox(width: 6),
                      McChip(net, color: netColor),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(meta,
                      style: McText.sans(
                          size: 12, color: McColors.onSurfaceVariant)),
                ],
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: McColors.tertiary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const McGlowDot(color: McColors.tertiary, size: 4),
                    const SizedBox(width: 4),
                    Text(
                      '已入账',
                      style: McText.sans(
                          size: 12,
                          weight: FontWeight.w600,
                          color: McColors.tertiary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(confirms,
                  style: McText.sans(size: 12, color: McColors.outline)),
            ],
          ),
        ],
      ),
    );
  }
}

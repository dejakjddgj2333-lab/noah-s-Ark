import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/widgets.dart';

/// 社区交流 (Telegram-style chat hub). Body-only tab inside the app shell:
/// search bar, quick-action pills, folder tabs, pinned + conversation lists.
class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: McColors.surfaceContainerLowest,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 32),
        children: [
          _SearchBar(),
          const SizedBox(height: 10),
          const _QuickActions(),
          const SizedBox(height: 10),
          const _FolderTabs(),
          const SizedBox(height: 8),
          _sectionDivider(
            icon: Icons.push_pin,
            iconColor: McColors.primaryContainer,
            title: '置顶交流组与核心信号 (Pinned)',
            trailing: '实时推送',
          ),
          const _ChatTile(
            title: '明策 VIP Alpha 策略交流群',
            badge: '官方群',
            badgeColor: McColors.primarySoft,
            time: '14:58',
            timeColor: McColors.bull,
            previewPrefix: '巨鲸异动监测:',
            prefixColor: McColors.secondary,
            preview: ' 币安 \$25M 买单支撑墙已挂出，多军准备冲锋突破...',
            unread: '99+',
            pinned: true,
            highlighted: true,
            avatar: _Avatar.verified(),
          ),
          const Divider(height: 1, color: Color(0x0AFFFFFF)),
          const _ChatTile(
            title: '明策清算机器人 BOT',
            badge: 'BOT',
            badgeColor: McColors.error,
            time: '14:50',
            previewPrefix: '全网高频爆仓预警:',
            prefixColor: McColors.error,
            preview: ' BTC 现价突破 \$96,520，空头清算达 \$12.8M',
            unread: '12',
            pinned: true,
            highlighted: true,
            avatar: _Avatar.icon(
              Icons.warning_amber_rounded,
              fg: McColors.error,
              bg: Color(0xFF2B1216),
              badgeIcon: Icons.bolt,
              badgeColor: McColors.error,
            ),
          ),
          const SizedBox(height: 4),
          _sectionDivider(
            title: '全部交流消息 (Conversations)',
            trailing: '4 位好友在线',
          ),
          const _ChatTile(
            title: 'Crypto_Ghost_0x',
            badge: '钻石合伙人',
            badgeColor: McColors.secondary,
            time: '14:52',
            preview: '你刚才看链上那笔 1,500 BTC 的大额提现了吗？主力洗盘动作明显。',
            readIcon: Icons.done_all,
            readColor: McColors.secondary,
            avatar: _Avatar.initials('CG', online: true),
          ),
          const Divider(height: 1, color: Color(0x0AFFFFFF)),
          const _ChatTile(
            title: '以太坊与 L2 生态研讨组',
            subtitle: '(1,840 人)',
            time: '13:20',
            previewPrefix: 'SatoshiSniper:',
            prefixColor: Colors.white,
            preview: ' 资金费率回落，准备看第二轮轧空机会。',
            unread: '5',
            avatar: _Avatar.icon(
              Icons.token,
              fg: McColors.primarySoft,
              bg: Color(0xFF16213E),
            ),
          ),
          const Divider(height: 1, color: Color(0x0AFFFFFF)),
          const _ChatTile(
            title: 'Alex_Macro_Alpha',
            badge: '量化导师',
            badgeColor: McColors.bull,
            time: '昨天',
            preview: '今晚美联储鲍威尔讲话要特别注意波动率，期权隐含波动已到 68%。',
            readIcon: Icons.done,
            readColor: McColors.onSurfaceVariant,
            avatar: _Avatar.initials('AM'),
          ),
          const Divider(height: 1, color: Color(0x0AFFFFFF)),
          const _ChatTile(
            title: '巨鲸异动智能雷达广播',
            badge: '频道',
            badgeColor: McColors.onSurfaceVariant,
            time: '昨天',
            preview: '[大额转账] 2,400 ETH (约 \$8.2M) 从 Coinbase 提出至匿名多签金库。',
            readIcon: Icons.volume_off,
            readColor: McColors.onSurfaceVariant,
            avatar: _Avatar.icon(
              Icons.radar,
              fg: McColors.secondary,
              bg: Color(0xFF0E2230),
              badgeIcon: Icons.podcasts,
              badgeColor: McColors.secondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionDivider({
    IconData? icon,
    Color iconColor = McColors.primaryContainer,
    required String title,
    required String trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 6),
          ],
          Text(
            title,
            style: McText.mono(
              size: 12,
              color: McColors.onSurfaceVariant.withValues(alpha: 0.7),
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          Text(
            trailing,
            style: McText.mono(
              size: 12,
              color: McColors.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

/// Telegram-style global search bar.
class _SearchBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF171A22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 18, color: Color(0xFF8E90A2)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '搜索用户、群组、公链频道或消息 (@username / Group)',
              style: McText.sans(size: 13, color: const Color(0xFF6A6D7F)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.filter_list, size: 17, color: Color(0xFF8E90A2)),
        ],
      ),
    );
  }
}

/// Quick-action shortcut pill strip.
class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _pill(Icons.person_add, '添加好友', McColors.primaryContainer,
              primary: true),
          const SizedBox(width: 8),
          _pill(Icons.group_add, '加入群组', McColors.secondary),
          const SizedBox(width: 8),
          _pill(Icons.radar, '巨鲸信号频道', McColors.bull),
          const SizedBox(width: 8),
          _pill(Icons.query_stats, '量化策略社群', McColors.primary),
        ],
      ),
    );
  }

  Widget _pill(IconData icon, String label, Color iconColor,
      {bool primary = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: primary
            ? McColors.primaryContainer.withValues(alpha: 0.15)
            : McColors.surfaceContainerHigh.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: primary
              ? McColors.primaryContainer.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: McText.sans(
              size: 12,
              weight: primary ? FontWeight.w600 : FontWeight.w500,
              color: primary ? McColors.primary : McColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal chat folder tabs.
class _FolderTabs extends StatelessWidget {
  const _FolderTabs();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1017),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            _tab('全部', count: '12', active: true),
            _tab('群聊', count: '8'),
            _tab('私聊/好友', count: '4'),
            _tab('机器人/BOT', count: '3'),
            _tab('频道/公告'),
          ],
        ),
      ),
    );
  }

  Widget _tab(String label, {String? count, bool active = false}) {
    final color = active ? Colors.white : McColors.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: McText.sans(
                  size: 12,
                  weight: active ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: active
                        ? McColors.primaryContainer
                        : McColors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    count,
                    style: McText.mono(
                      size: 12,
                      weight: active ? FontWeight.w700 : FontWeight.w400,
                      color: active ? Colors.white : McColors.onSurfaceVariant,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 2,
            width: 28,
            decoration: BoxDecoration(
              color: active ? McColors.primaryContainer : Colors.transparent,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: McColors.primaryContainer.withValues(alpha: 0.8),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Avatar variants (no network images — icon / initials placeholders).
class _Avatar extends StatelessWidget {
  const _Avatar.icon(
    this.icon, {
    required this.fg,
    required this.bg,
    this.badgeIcon,
    this.badgeColor,
  })  : initials = null,
        online = false,
        verified = false;

  const _Avatar.initials(
    this.initials, {
    this.online = false,
  })  : icon = null,
        fg = McColors.primary,
        bg = McColors.surfaceContainerHigh,
        badgeIcon = null,
        badgeColor = null,
        verified = false;

  const _Avatar.verified()
      : icon = null,
        initials = 'M',
        online = false,
        fg = Colors.white,
        bg = McColors.primaryContainer,
        badgeIcon = Icons.verified,
        badgeColor = McColors.primaryContainer,
        verified = true;

  final IconData? icon;
  final String? initials;
  final Color fg;
  final Color bg;
  final IconData? badgeIcon;
  final Color? badgeColor;
  final bool online;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: verified
                    ? McColors.primaryContainer.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.1),
                width: verified ? 2 : 1,
              ),
              boxShadow: verified
                  ? [
                      BoxShadow(
                        color: McColors.primaryContainer.withValues(alpha: 0.35),
                        blurRadius: 12,
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: icon != null
                ? Icon(icon, size: 24, color: fg)
                : Text(
                    initials!,
                    style: McText.display(size: 16, weight: FontWeight.w700, color: fg),
                  ),
          ),
          if (badgeIcon != null)
            Positioned(
              bottom: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: McColors.surfaceContainerLowest, width: 2),
                ),
                child: Icon(badgeIcon, size: 12, color: Colors.white),
              ),
            ),
          if (online)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: McColors.bull,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: McColors.surfaceContainerLowest, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A single conversation row.
class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.title,
    required this.time,
    required this.preview,
    required this.avatar,
    this.badge,
    this.badgeColor = McColors.primarySoft,
    this.subtitle,
    this.timeColor = McColors.onSurfaceVariant,
    this.previewPrefix,
    this.prefixColor = McColors.secondary,
    this.unread,
    this.pinned = false,
    this.highlighted = false,
    this.readIcon,
    this.readColor = McColors.onSurfaceVariant,
  });

  final String title;
  final String? badge;
  final Color badgeColor;
  final String? subtitle;
  final String time;
  final Color timeColor;
  final String? previewPrefix;
  final Color prefixColor;
  final String preview;
  final String? unread;
  final bool pinned;
  final bool highlighted;
  final IconData? readIcon;
  final Color readColor;
  final Widget avatar;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: highlighted ? const Color(0xFF11151F).withValues(alpha: 0.85) : null,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          avatar,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: McText.sans(
                          size: 14,
                          weight: badge != null ? FontWeight.w700 : FontWeight.w600,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 6),
                      McPill(badge!, color: badgeColor, fontSize: 12),
                    ],
                    if (subtitle != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        subtitle!,
                        style: McText.mono(
                          size: 12,
                          color: McColors.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      time,
                      style: McText.mono(
                        size: 12,
                        weight: FontWeight.w600,
                        color: timeColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            if (previewPrefix != null)
                              TextSpan(
                                text: previewPrefix,
                                style: McText.sans(
                                  size: 12,
                                  weight: FontWeight.w500,
                                  color: prefixColor,
                                ),
                              ),
                            TextSpan(
                              text: preview,
                              style: McText.sans(
                                size: 12,
                                color: McColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (pinned)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(Icons.push_pin,
                            size: 13, color: McColors.primaryContainer),
                      ),
                    if (unread != null)
                      Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        height: 18,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: McColors.primaryContainer,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: McColors.primaryContainer
                                  .withValues(alpha: 0.7),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          unread!,
                          style: McText.mono(
                            size: 12,
                            weight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      )
                    else if (readIcon != null)
                      Icon(readIcon, size: 15, color: readColor),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

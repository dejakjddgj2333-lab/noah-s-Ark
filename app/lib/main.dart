import 'dart:async';
import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'core/widgets.dart';
import 'pages/assets_page.dart';
import 'pages/chat_page.dart';
import 'pages/commission_page.dart';
import 'pages/deposit_page.dart';
import 'pages/home_funding_page.dart';
import 'pages/home_liquidation_page.dart';
import 'pages/home_market_page.dart';
import 'pages/home_overview_page.dart';
import 'pages/home_terminal_page.dart';
import 'pages/home_whale_page.dart';
import 'pages/invite_page.dart';
import 'pages/login_page.dart';
import 'pages/news_page.dart';
import 'services/auth.dart';
import 'services/chat_api.dart';
import 'services/chat_ws.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthStore.instance.load();
  // 已登录则启动聊天长连接.
  if (AuthStore.instance.loggedIn) ChatWs.instance.connect();
  runApp(const MingceApp());
}

class MingceApp extends StatelessWidget {
  const MingceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Noah’s Ark',
      debugShowCheckedModeBanner: false,
      theme: buildMcTheme(),
      routes: {
        '/login': (_) => const LoginPage(),
      },
      onGenerateRoute: (settings) {
        // 需登录的 push 路由
        final gated = <String, Widget>{
          '/deposit': const DepositPage(),
          '/commission': const CommissionPage(),
          '/invite': const InvitePage(),
        };
        final page = gated[settings.name];
        if (page == null) return null;
        return MaterialPageRoute(
          builder: (_) =>
              AuthStore.instance.loggedIn ? page : const LoginPage(),
        );
      },
      home: const McShell(),
    );
  }
}

/// App shell: fixed top header + 4-tab bottom nav.
class McShell extends StatefulWidget {
  const McShell({super.key});

  @override
  State<McShell> createState() => _McShellState();
}

class _McShellState extends State<McShell> {
  int _index = 0;
  StreamSubscription<Map<String, dynamic>>? _chatSub;

  final _pages = const [
    HomePage(),
    NewsPage(),
    ChatPage(),
    AssetsPage(),
  ];

  @override
  void initState() {
    super.initState();
    // 全局监听好友请求: 任何页面都弹通知 + 角标 (聊天页外也能感知).
    _chatSub = ChatWs.instance.events.listen(_onChatEvent);
    _seedChatBadges();
  }

  Future<void> _seedChatBadges() async {
    if (!AuthStore.instance.loggedIn) return;
    try {
      await ChatApi.friendRequests();
    } catch (_) {/* 静默 */}
  }

  void _onChatEvent(Map<String, dynamic> e) {
    if (!mounted || e['type'] != 'friend_request') return;
    final from = e['from_user'];
    final name = from is Map ? (from['username'] ?? '对方') : '对方';
    ChatApi.friendRequestCount.value++;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: McColors.surfaceContainerHigh,
        content: Text('$name 请求添加你为好友',
            style: McText.sans(size: 13, color: McColors.onSurface)),
        action: SnackBarAction(
          label: '查看',
          textColor: McColors.primarySoft,
          onPressed: () => setState(() => _index = 2),
        ),
        duration: const Duration(seconds: 4),
      ));
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const McAppHeader(),
          Expanded(
            child: ListenableBuilder(
              listenable: AuthStore.instance,
              builder: (context, _) {
                final loggedIn = AuthStore.instance.loggedIn;
                // 聊天/我的 需登录
                final gated = {
                  2: loggedIn ? const ChatPage() : const _LoginGate('聊天'),
                  3: loggedIn ? const AssetsPage() : const _LoginGate('我的'),
                };
                return IndexedStack(
                  index: _index,
                  children: [
                    for (var i = 0; i < _pages.length; i++) gated[i] ?? _pages[i],
                  ],
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: McBottomNav(
        current: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

/// 未登录占位: 引导跳转 /login.
class _LoginGate extends StatelessWidget {
  const _LoginGate(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: McColors.primaryContainer.withValues(alpha: 0.12),
                border: Border.all(
                    color: McColors.primaryContainer.withValues(alpha: 0.4)),
              ),
              child: const Icon(Icons.lock_outline,
                  size: 28, color: McColors.primarySoft),
            ),
            const SizedBox(height: 16),
            Text('登录后使用$name',
                style: McText.display(size: 16, weight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('终端功能需要验证身份',
                style: McText.sans(
                    size: 12, color: McColors.onSurfaceVariant)),
            const SizedBox(height: 20),
            SizedBox(
              width: 180,
              height: 44,
              child: ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, '/login'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: McColors.primaryContainer,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: Text('去登录',
                    style: McText.sans(
                        size: 13, weight: FontWeight.w700, letterSpacing: 2)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared top header: brand logo + sync status + avatar. h=56, cobalt blur bar.
class McAppHeader extends StatelessWidget {
  const McAppHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: McColors.surface.withValues(alpha: 0.9),
        border: Border(
          bottom: BorderSide(
            color: McColors.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, 4)),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                // Logo block
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: McColors.primaryContainer.withValues(alpha: 0.45),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset('assets/logo.png', fit: BoxFit.cover),
                ),
                const SizedBox(width: 10),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Noah’s Ark',
                          style: McText.display(size: 14, weight: FontWeight.w700),
                        ),
                        const SizedBox(width: 6),
                        const McPill('Alpha', color: McColors.primarySoft),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const McGlowDot(size: 6),
                        const SizedBox(width: 6),
                        Text(
                          'MAINNET SYNC',
                          style: McText.mono(
                            size: 10,
                            weight: FontWeight.w500,
                            color: McColors.bull,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    if (!AuthStore.instance.loggedIn) {
                      Navigator.pushNamed(context, '/login');
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: McColors.surfaceContainer,
                      border: Border.all(
                        color: McColors.primaryContainer.withValues(alpha: 0.5),
                      ),
                    ),
                    child: ListenableBuilder(
                      listenable: AuthStore.instance,
                      builder: (context, _) {
                        final name = AuthStore.instance.username;
                        return CircleAvatar(
                          radius: 14,
                          backgroundColor: McColors.surfaceContainerHigh,
                          child: name != null
                              ? Text(
                                  name[0].toUpperCase(),
                                  style: McText.mono(
                                    size: 12,
                                    weight: FontWeight.w700,
                                    color: McColors.primary,
                                  ),
                                )
                              : const Icon(Icons.person,
                                  size: 18, color: McColors.primary),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom nav: 首页 / 资讯 / 聊天(动态未读角标) / 我的. h=56, blur dark bar.
class McBottomNav extends StatelessWidget {
  const McBottomNav({super.key, required this.current, required this.onTap});

  final int current;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: McColors.surface.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(color: McColors.outlineVariant.withValues(alpha: 0.5)),
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _item(0, Icons.radar, '首页'),
              _item(1, Icons.query_stats, '资讯', dot: true),
              ValueListenableBuilder<int>(
                valueListenable: ChatApi.unreadCount,
                builder: (context, unread, _) => ValueListenableBuilder<int>(
                  valueListenable: ChatApi.friendRequestCount,
                  builder: (context, reqs, _) {
                    final count = unread + reqs; // 未读消息 + 待处理好友请求
                    return _item(
                      2,
                      Icons.chat_bubble_outline,
                      '聊天',
                      badge: count > 0 ? (count > 99 ? '99+' : '$count') : null,
                    );
                  },
                ),
              ),
              _item(3, Icons.account_balance_wallet, '我的'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(
    int index,
    IconData icon,
    String label, {
    bool dot = false,
    String? badge,
  }) {
    final active = current == index;
    final color = active ? McColors.primaryContainer : McColors.onSurfaceVariant;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(index),
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 22, color: color),
                if (dot)
                  const Positioned(
                    top: -2,
                    right: -4,
                    child: McGlowDot(color: McColors.secondary, size: 6),
                  ),
                if (badge != null)
                  Positioned(
                    top: -4,
                    right: -10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: McColors.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: McColors.primaryContainer
                                .withValues(alpha: 0.6),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Text(
                        badge,
                        style: McText.mono(
                            size: 9, weight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: McText.sans(
                size: 10,
                weight: active ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 首页: top tab bar with 6 boards.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  static const _tabs = ['综合', '行情', '多维指数', '多空爆仓', '巨鲸雷达', '资金费率'];

  @override
  Widget build(BuildContext context) {
    final pages = [
      const HomeOverviewPage(), // 综合: 聚合看板
      const HomeMarketPage(),
      const HomeTerminalPage(),
      const HomeLiquidationPage(),
      const HomeWhalePage(),
      const HomeFundingPage(),
    ];
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: McColors.surface.withValues(alpha: 0.6),
            border: Border(
              bottom: BorderSide(
                color: McColors.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                for (var i = 0; i < _tabs.length; i++) ...[
                  if (i > 0) const SizedBox(width: 24),
                  _tabItem(i),
                ],
              ],
            ),
          ),
        ),
        Expanded(child: IndexedStack(index: _tab, children: pages)),
      ],
    );
  }

  Widget _tabItem(int i) {
    final active = _tab == i;
    return GestureDetector(
      onTap: () => setState(() => _tab = i),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              _tabs[i],
              style: McText.sans(
                size: 12,
                weight: active ? FontWeight.w700 : FontWeight.w400,
                color: active ? Colors.white : McColors.onSurfaceVariant,
              ),
            ),
          ),
          Container(
            height: 2,
            width: 28,
            decoration: BoxDecoration(
              color: active ? McColors.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(1),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color:
                            McColors.primaryContainer.withValues(alpha: 0.8),
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

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'pages/login_page.dart';
import 'pages/overview_page.dart';
import 'pages/market_page.dart';
import 'pages/multidim_page.dart';
import 'pages/liquidation_page.dart';
import 'pages/whale_page.dart';
import 'pages/funding_page.dart';
import 'pages/news_page.dart';
import 'pages/chat_page.dart';
import 'pages/assets_page.dart';
import 'pages/profile_page.dart';
import 'state/auth_store.dart';
import 'state/settings_store.dart';
import 'theme.dart';
import 'widgets/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  const opts = WindowOptions(
    size: Size(1440, 900),
    minimumSize: Size(1120, 700),
    center: true,
    title: '明策终端',
    backgroundColor: Color(0xFF070D1C),
  );
  windowManager.waitUntilReadyToShow(opts, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  await AuthStore.I.init();
  await SettingsStore.I.load();
  runApp(const TerminalApp());
}

class TerminalApp extends StatelessWidget {
  const TerminalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '明策终端',
      debugShowCheckedModeBanner: false,
      theme: Mc.theme(),
      home: AnimatedBuilder(
        animation: Listenable.merge([AuthStore.I, SettingsStore.I]),
        builder: (context, _) {
          if (!AuthStore.I.ready) {
            return const Scaffold(
                body: Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Mc.cobaltSoft)));
          }
          if (!AuthStore.I.loggedIn) return const LoginPage();
          return AppShell(items: [
            NavItem(Icons.dashboard_outlined, '概览', 'OVERVIEW', const OverviewPage()),
            NavItem(Icons.candlestick_chart_outlined, '行情', 'MARKET', const MarketPage()),
            NavItem(Icons.query_stats, '多维数据', 'MULTI-DIM', const MultiDimPage()),
            NavItem(Icons.crisis_alert, '爆仓监控', 'LIQUIDATION', const LiquidationPage()),
            NavItem(Icons.visibility_outlined, '巨鲸动向', 'WHALE', const WhalePage()),
            NavItem(Icons.percent, '资金费率', 'FUNDING', const FundingPage()),
            NavItem(Icons.article_outlined, '资讯', 'NEWS', const NewsPage()),
            NavItem(Icons.chat_bubble_outline, '聊天', 'CHAT', const ChatPage()),
            NavItem(Icons.account_balance_wallet_outlined, '资产理财', 'ASSETS', const AssetsPage()),
            NavItem(Icons.person_outline, '我的', 'PROFILE', const ProfilePage()),
          ]);
        },
      ),
    );
  }
}

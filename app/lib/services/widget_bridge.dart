/// iOS 桌面小组件数据桥: 把固定五币行情 + 最新巨鲸异动写进 App Group
/// shared UserDefaults (经 home_widget 插件), WidgetKit 扩展读同一份数据.
///
/// 仅在 iOS 生效; 其它平台 init 直接返回. 数据为公开行情, 与登录态无关.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'data.dart';
import 'ticker_ws.dart';

class WidgetBridge {
  WidgetBridge._();
  static final WidgetBridge instance = WidgetBridge._();

  /// App Group id, 须与 ios Runner/MingceWidget entitlements 一致.
  static const String appGroupId = 'group.com.hkmc.noahsark.shared';

  /// 小组件关注的固定币种 (与 server /api/widget 一致).
  static const List<String> coins = ['BTC', 'ETH', 'SOL', 'XRP', 'DOGE'];

  StreamSubscription<TickerPush>? _tickerSub;
  Timer? _whaleTimer;
  bool _started = false;

  // 最新价缓存: symbol → {price, changePct}
  final Map<String, Map<String, double>> _prices = {};

  /// 节流: ticker 流很高频, 30s 最多写一次.
  DateTime _lastWrite = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> init() async {
    if (_started || kIsWeb || !Platform.isIOS) return;
    _started = true;
    try {
      await HomeWidget.setAppGroupId(appGroupId);
    } catch (_) {
      return; // 插件未就绪 (如 extension 未配好), 静默跳过
    }
    // 行情: 监听现有 OKX ticker 流, 节流写共享存储
    _tickerSub = TickerWs.instance.stream.listen(_onTicker);
    // 巨鲸: 每 5 分钟刷一次 REST (WS 无巨鲸频道)
    await _refreshWhales();
    _whaleTimer = Timer.periodic(
        const Duration(minutes: 5), (_) => _refreshWhales());
  }

  void _onTicker(TickerPush t) {
    // instId 形如 BTC-USDT-SWAP / BTC-USDT
    final symbol = t.instId.split('-').first;
    if (!coins.contains(symbol)) return;
    _prices[symbol] = {'price': t.last, 'changePct': t.changePct};
    final now = DateTime.now();
    if (now.difference(_lastWrite).inSeconds < 30) return;
    if (_prices.length < coins.length) return; // 等五币都拿到首帧
    _lastWrite = now;
    _writePrices();
  }

  Future<void> _writePrices() async {
    try {
      final list = [
        for (final c in coins)
          if (_prices.containsKey(c))
            {
              'symbol': c,
              'price': _prices[c]!['price'],
              'change_pct': _prices[c]!['changePct'],
            }
      ];
      if (list.isEmpty) return;
      await HomeWidget.saveWidgetData<String>(
          'mc_prices', jsonEncode(list));
      await HomeWidget.updateWidget(name: 'MingcePriceWidget');
    } catch (_) {
      // 写共享存储失败不影响主流程
    }
  }

  Future<void> _refreshWhales() async {
    try {
      final resp = await McData.overview('whale-alerts');
      final alerts = resp['alerts'];
      if (alerts is! List) return;
      final top = alerts.take(3).map((e) {
        final m = (e as Map).cast<String, dynamic>();
        return {
          'symbol': m['symbol'] ?? '',
          'side': m['side'] ?? '',
          'usd': m['positionSize'] ?? 0,
          'time': m['time'] ?? 0,
          'source': m['user'] ?? '',
        };
      }).toList();
      await HomeWidget.saveWidgetData<String>(
          'mc_whales', jsonEncode(top));
      await HomeWidget.updateWidget(name: 'MingceWhaleWidget');
    } catch (_) {
      // 静默: 下次周期再试
    }
  }

  Future<void> dispose() async {
    await _tickerSub?.cancel();
    _whaleTimer?.cancel();
  }
}

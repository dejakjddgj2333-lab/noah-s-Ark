/// iOS 桌面小组件数据桥: 把固定五币行情 + 最新巨鲸异动写进 App Group
/// shared UserDefaults (经 home_widget 插件), WidgetKit 扩展读同一份数据.
///
/// 仅在 iOS 生效; 其它平台 init 直接返回. 数据为公开行情, 与登录态无关.
/// 行情走自建后端 /api/widget/prices (服务端行情代理缓存), 不依赖客户端
/// 直连 OKX WS — 后者在部分网络/模拟器下连不上会导致小组件永远空.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'api.dart';
import 'data.dart';

class WidgetBridge {
  WidgetBridge._();
  static final WidgetBridge instance = WidgetBridge._();

  /// App Group id, 须与 ios Runner/MingceWidget entitlements 一致.
  static const String appGroupId = 'group.com.hkmc.noahsark.shared';

  /// 小组件关注的固定币种 (与 server /api/widget 一致).
  static const List<String> coins = ['BTC', 'ETH', 'SOL', 'XRP', 'DOGE'];

  Timer? _priceTimer;
  Timer? _whaleTimer;
  bool _started = false;

  Future<void> init() async {
    if (_started || kIsWeb || !Platform.isIOS) return;
    _started = true;
    try {
      await HomeWidget.setAppGroupId(appGroupId);
    } catch (_) {
      return; // 插件未就绪 (如 extension 未配好), 静默跳过
    }
    // 行情 + 巨鲸: 启动即拉一次, 之后定时刷 (小组件本身 15min timeline 兜底).
    await _refreshPrices();
    await _refreshWhales();
    _priceTimer =
        Timer.periodic(const Duration(minutes: 5), (_) => _refreshPrices());
    _whaleTimer =
        Timer.periodic(const Duration(minutes: 5), (_) => _refreshWhales());
  }

  Future<void> _refreshPrices() async {
    try {
      final resp = await McApi.get('/api/widget/prices');
      final list = resp['prices'];
      if (list is! List || list.isEmpty) return;
      final out = [
        for (final e in list)
          {
            'symbol': (e as Map)['symbol'] ?? '',
            'price': (e['price'] as num?)?.toDouble() ?? 0,
            'change_pct': (e['change_pct'] as num?)?.toDouble() ?? 0,
          }
      ];
      await HomeWidget.saveWidgetData<String>('mc_prices', jsonEncode(out));
      await HomeWidget.updateWidget(name: 'MingcePriceWidget');
    } catch (_) {
      // 静默: 下次周期再试
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
    _priceTimer?.cancel();
    _whaleTimer?.cancel();
  }
}

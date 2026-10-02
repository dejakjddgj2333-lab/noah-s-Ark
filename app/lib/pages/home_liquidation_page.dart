import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/api.dart';
import '../services/data.dart';
import '../services/liquidation_ws.dart';

/// 多空爆仓 (Long/Short Liquidation) content body.
/// Palette overrides from stitch_ref/home_liquidation.html.
///
/// 总爆仓/交易所统计/热力分布尝试接
/// `/api/market-overview/liquidations/exchange-list?range=24h`; 失败(未配置
/// CoinGlass/上游错误/后端未启动)时静默保留内置 mock, 永不红屏.
class HomeLiquidationPage extends StatefulWidget {
  const HomeLiquidationPage({super.key});

  @override
  State<HomeLiquidationPage> createState() => _HomeLiquidationPageState();
}

class _HomeLiquidationPageState extends State<HomeLiquidationPage> {
  // Screen-specific palette (home_liquidation.html tailwind overrides).
  static const _bull = Color(0xFF10B981);
  static const _bullLight = Color(0xFF34D399);
  static const _bullDark = Color(0xFF059669);
  static const _bear = Color(0xFFEF4444);
  static const _bearLight = Color(0xFFF87171);
  static const _surfaceContainer = Color(0xFF151921);
  static const _onSurfaceVariant = Color(0xFF949AA8);
  static const _primaryLight = Color(0xFF688DFF);

  static const _hairline = Color(0x0FFFFFFF); // white/5

  // 24H 总爆仓卡: 首屏展示 mock.
  String _total24 = '\$3.3亿';
  String _long24 = '\$2.7亿';
  String _short24 = '\$6682万';
  String _liqCount = '87,865'; // 爆仓人数 (coin-list 无人数字段时保留 mock)
  String _liqTotalText = '\$3.35亿';

  // 实时监控卡: range -> (total, long, short) 原始值, mock 默认, 拉取成功覆盖.
  final Map<String, (double, double, double)> _sums = {
    '1h': (301e4, 167.6e4, 133.4e4),
    '4h': (1120.7e4, 454.6e4, 666.1e4),
    '24h': (3.35e8, 2.7e8, 6682e4),
  };
  String _monitorRange = '24h'; // 监控卡当前时段

  // 顶部币种快捷过滤 ('全部' 或 BTC/ETH/...).
  String _symbol = '全部';
  // 实时 feed 最小金额过滤 (0=全部).
  double _feedMinUsd = 0;
  // 交易所统计当前时段.
  String _statsRange = '24h';

  // 分时段爆仓 (1h/4h/12h): 首屏 mock, 拉取成功后覆盖.
  String _total1h = '\$301万';
  String _long1h = '\$167.6万';
  String _short1h = '\$133.4万';
  String _total4h = '\$1120.7万';
  String _long4h = '\$454.6万';
  String _short4h = '\$666.1万';
  String _total12h = '\$7150万';
  String _long12h = '\$4469万';
  String _short12h = '\$2681万';

  // 实时爆仓 feed: 首屏 mock 占位, Binance WS 推送后逐条前置覆盖.
  final List<_FeedItem> _feedItems = _mockFeedItems();
  StreamSubscription<LiqPush>? _liqSub;

  static List<_FeedItem> _mockFeedItems() => const [
        _FeedItem(
          avatarBg: Color(0x26F3BA2F),
          avatarLabel: '❖',
          avatarColor: Color(0xFFF3BA2F),
          name: 'Binance',
          symbol: 'FLOCKUSDT',
          price: '\$0.03982',
          long: true,
          amount: '\$1,984.16',
          amountUsd: 1984.16,
          amountColor: Colors.white,
          qty: '≈4.98万 FLOCK',
          time: '16:09:42',
        ),
        _FeedItem(
          avatarBg: Color(0x26F3BA2F),
          avatarLabel: '❖',
          avatarColor: Color(0xFFF3BA2F),
          name: 'Binance',
          symbol: 'USELESS',
          price: '\$0.11759',
          long: false,
          amount: '\$1,877.84',
          amountUsd: 1877.84,
          amountColor: Colors.white,
          qty: '≈1.6万 USELESS',
          time: '16:09:28',
        ),
        _FeedItem(
          avatarBg: Color(0x1AFFFFFF),
          avatarLabel: 'OK',
          avatarColor: Colors.white,
          name: 'OKX',
          symbol: 'BTC-SWAP',
          price: '\$66,420.5',
          long: true,
          amount: '\$48.29万',
          amountUsd: 482900,
          amountColor: Color(0xFF10B981),
          qty: '7.27 BTC',
          time: '16:08:50',
        ),
        _FeedItem(
          avatarBg: Color(0x2610B981),
          avatarLabel: 'HL',
          avatarColor: Color(0xFF10B981),
          name: 'Hyperliquid',
          symbol: 'ETH-PERP',
          price: '\$3,418.90',
          long: true,
          amount: '\$128.50万',
          amountUsd: 1285000,
          amountColor: Color(0xFF10B981),
          qty: '375.8 ETH',
          time: '16:08:12',
        ),
        _FeedItem(
          avatarBg: Color(0x1AF7A600),
          avatarLabel: 'BY',
          avatarColor: Color(0xFFF7A600),
          name: 'Bybit',
          symbol: 'SOLUSDT',
          price: '\$148.20',
          long: false,
          amount: '\$21.35万',
          amountUsd: 213500,
          amountColor: Colors.white,
          qty: '1,440.6 SOL',
          time: '16:07:45',
          showDivider: false,
        ),
      ];

  // 交易所统计行: 首屏展示 mock, 成功后按名称覆盖.
  late List<_ExStat> _exStats = _mockExStats();

  static List<_ExStat> _mockExStats() => const [
        _ExStat(
          avatarBg: McColors.surfaceContainerHighest,
          avatarLabel: '全',
          avatarColor: _primaryLight,
          name: '全部',
          total: '\$3.3亿',
          pct: '100.00%',
          longFrac: 0.802,
          longText: '\$2.7亿',
          shortText: '\$6682万',
          boldName: true,
        ),
        _ExStat(
          avatarBg: Color(0x1AF3BA2F),
          avatarLabel: '❖',
          avatarColor: Color(0xFFF3BA2F),
          name: 'Binance',
          total: '\$1.6亿',
          pct: '46.48%',
          longFrac: 0.794,
          longText: '\$1.2亿',
          shortText: '\$3108.3万',
        ),
        _ExStat(
          avatarBg: Color(0x2610B981),
          avatarLabel: 'HL',
          avatarColor: _bull,
          name: 'Hyperliquid',
          total: '\$5423.5万',
          pct: '16.20%',
          longFrac: 0.934,
          longText: '\$5066.3万',
          shortText: '\$357.2万',
        ),
        _ExStat(
          avatarBg: Color(0x1AFFFFFF),
          avatarLabel: 'OK',
          avatarColor: Colors.white,
          name: 'OKX',
          total: '\$3734.6万',
          pct: '11.15%',
          longFrac: 0.695,
          longText: '\$2596.3万',
          shortText: '\$1138.2万',
        ),
        _ExStat(
          avatarBg: Color(0x1AF7A600),
          avatarLabel: 'BY',
          avatarColor: Color(0xFFF7A600),
          name: 'Bybit',
          total: '\$3233.2万',
          pct: '9.65%',
          longFrac: 0.799,
          longText: '\$2583.1万',
          shortText: '\$650.2万',
        ),
        _ExStat(
          avatarBg: Color(0x260052FF),
          avatarLabel: 'GT',
          avatarColor: Color(0xFF0052FF),
          name: 'Gate',
          total: '\$2708.5万',
          pct: '8.09%',
          longFrac: 0.794,
          longText: '\$2152.1万',
          shortText: '\$556.4万',
        ),
        _ExStat(
          avatarBg: Color(0x2600F0FF),
          avatarLabel: 'BG',
          avatarColor: Color(0xFF00F0FF),
          name: 'Bitget',
          total: '\$1577.5万',
          pct: '4.71%',
          longFrac: 0.833,
          longText: '\$1313.9万',
          shortText: '\$263.6万',
          showDivider: false,
        ),
      ];

  @override
  void initState() {
    super.initState();
    _subscribeLiqWs();
    _load();
  }

  @override
  void dispose() {
    _liqSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    await Future.wait([
      _load24h(),
      _loadTimeframes(),
      _loadLiqCount(),
    ]);
  }

  Future<void> _load24h() => _loadRangeStats(_statsRange);

  // 交易所统计按时段拉取; 仅 24h 时顺带更新总爆仓卡与监控卡.
  Future<void> _loadRangeStats(String range) async {
    try {
      final resp =
          await McData.overview('liquidations/exchange-list?range=$range');
      final parsed = _parseExchangeList(resp['data']);
      if (parsed == null || !mounted) return;
      setState(() => _applyParsed(parsed, range));
    } on ApiException {
      // 503 未配置 / 502 上游错误 — 保留 mock.
    } catch (_) {
      // 网络/解析异常 — 保留 mock.
    }
  }

  // 1h/4h/12h 分时段: 并行拉取, 各所求和 -> 总爆仓+多单+空单. 任一失败保留 mock.
  Future<void> _loadTimeframes() async {
    final results = await Future.wait([
      _sumRange('1h'),
      _sumRange('4h'),
      _sumRange('12h'),
    ]);
    if (!mounted) return;
    setState(() {
      final r1 = results[0];
      if (r1 != null) {
        _sums['1h'] = r1;
        _total1h = _fmtUsdZh(r1.$1);
        _long1h = _fmtUsdZh(r1.$2);
        _short1h = _fmtUsdZh(r1.$3);
      }
      final r4 = results[1];
      if (r4 != null) {
        _sums['4h'] = r4;
        _total4h = _fmtUsdZh(r4.$1);
        _long4h = _fmtUsdZh(r4.$2);
        _short4h = _fmtUsdZh(r4.$3);
      }
      final r12 = results[2];
      if (r12 != null) {
        _total12h = _fmtUsdZh(r12.$1);
        _long12h = _fmtUsdZh(r12.$2);
        _short12h = _fmtUsdZh(r12.$3);
      }
    });
  }

  /// 某 range 各交易所爆仓求和: (total, long, short); 失败返回 null.
  static Future<(double, double, double)?> _sumRange(String range) async {
    try {
      final resp =
          await McData.overview('liquidations/exchange-list?range=$range');
      final parsed = _parseExchangeList(resp['data']);
      if (parsed == null) return null;
      double total = 0, long = 0, short = 0;
      for (final r in parsed) {
        // 排除 "All" 汇总行, 避免重复计数.
        if (_normName(r.name) == 'all') continue;
        total += r.total;
        long += r.long;
        short += r.short;
      }
      return total > 0 ? (total, long, short) : null;
    } on ApiException {
      return null;
    } catch (_) {
      return null;
    }
  }

  // 实时爆仓 feed: 改用 Binance 合约强平 WS (免费/无 key), 替代 CoinGlass
  // orders 接口 (当前套餐 502 plan-gated, 无法返回实时流).
  void _subscribeLiqWs() {
    _liqSub = LiquidationWs.instance.stream.listen((p) {
      if (!mounted) return;
      setState(() {
        _feedItems.insert(0, _toFeedItem(p));
        if (_feedItems.length > 50) _feedItems.removeLast();
      });
    });
  }

  static _FeedItem _toFeedItem(LiqPush p) {
    final isLong = p.side == 'long';
    return _FeedItem(
      avatarBg: const Color(0x26F3BA2F),
      avatarLabel: '❖',
      avatarColor: const Color(0xFFF3BA2F),
      name: 'Binance',
      symbol: p.symbol,
      price: '\$${_fmtPrice(p.price)}',
      long: isLong,
      amount: _fmtUsdZh(p.notionalUsd),
      amountUsd: p.notionalUsd,
      amountColor: isLong ? _bull : _bear,
      qty: '≈${_fmtQty(p.qty)} ${p.baseCcy}',
      time: _fmtClock(p.ts),
      showDivider: false,
    );
  }

  // 爆仓人数: 尝试 /overview/liquidations/coin-list, 查每币种是否有
  // 人数类字段 (liquidation_count/num/...). CoinGlass v4 coin-list 实际只返回
  // 金额/价格类字段, 无人数字段 — 故通常保留 mock, 有则求和覆盖.
  Future<void> _loadLiqCount() async {
    try {
      final resp = await McData.overview('liquidations/coin-list');
      final list = _asList(resp['coins']);
      double sum = 0;
      var found = false;
      for (final e in list) {
        if (e is! Map) continue;
        final m = e.cast<String, dynamic>();
        final n = _num(m['liquidation_count'] ??
            m['liquidationCount'] ??
            m['liqCount'] ??
            m['num'] ??
            m['count'] ??
            m['personCount'] ??
            m['liquidatedPersonCount']);
        if (n > 0) {
          found = true;
          sum += n;
        }
      }
      if (!found || sum <= 0 || !mounted) return;
      setState(() => _liqCount = _comma(sum.toStringAsFixed(0)));
    } on ApiException {
      // 503 未配置 / 502 上游错误 — 保留 mock.
    } catch (_) {
      // 网络/解析异常 — 保留 mock.
    }
  }

  static String _fmtPrice(double v) {
    if (v >= 1000) return _comma(v.toStringAsFixed(1));
    if (v >= 1) return v.toStringAsFixed(2);
    return v.toStringAsFixed(5);
  }

  static String _comma(String numStr) {
    final parts = numStr.split('.');
    final intPart = parts[0];
    final buf = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      buf.write(intPart[i]);
      final rem = intPart.length - i - 1;
      if (rem > 0 && rem % 3 == 0) buf.write(',');
    }
    return parts.length > 1 ? '$buf.${parts[1]}' : buf.toString();
  }

  static String _fmtQty(double v) {
    if (v >= 1e4) return '${(v / 1e4).toStringAsFixed(1)}万';
    if (v >= 100) return v.toStringAsFixed(0);
    if (v >= 1) return v.toStringAsFixed(1);
    return v.toStringAsFixed(3);
  }

  static String _fmtClock(dynamic ts) {
    final ms = ts is num ? ts.toInt() : int.tryParse('$ts') ?? 0;
    if (ms <= 0) return '--:--:--';
    final dt =
        DateTime.fromMillisecondsSinceEpoch(ms > 100000000000 ? ms : ms * 1000);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  // 应用解析结果: 覆盖已知名称的交易所行, 重算该时段「全部」行;
  // range=24h 时同步更新总爆仓卡与监控卡原始值.
  void _applyParsed(List<_RawEx> raw, [String range = '24h']) {
    double sumTotal = 0, sumLong = 0, sumShort = 0;
    for (final r in raw) {
      if (_normName(r.name) == 'all') continue; // 聚合行, 跳过避免重复计数
      sumTotal += r.total;
      sumLong += r.long;
      sumShort += r.short;
    }
    if (sumTotal <= 0) return;

    // 按名称匹配更新 (保留 mock 的头像/配色与未知名称).
    final updated = <_ExStat>[];
    for (final stat in _exStats) {
      if (stat.name == '全部') continue; // 末尾统一重算
      final match = _matchRaw(raw, stat.name);
      if (match == null) {
        updated.add(stat);
      } else {
        updated.add(stat.copyWith(
          total: _fmtUsdZh(match.total),
          pct: '${(match.total / sumTotal * 100).toStringAsFixed(2)}%',
          longFrac: _frac(match.long, match.short),
          longText: _fmtUsdZh(match.long),
          shortText: _fmtUsdZh(match.short),
        ));
      }
    }
    // 「全部」行置顶重算.
    updated.insert(
      0,
      _exStats.first.copyWith(
        total: _fmtUsdZh(sumTotal),
        pct: '100.00%',
        longFrac: _frac(sumLong, sumShort),
        longText: _fmtUsdZh(sumLong),
        shortText: _fmtUsdZh(sumShort),
      ),
    );
    _exStats = updated;

    _sums[range] = (sumTotal, sumLong, sumShort);
    if (range == '24h') {
      _total24 = _fmtUsdZh(sumTotal);
      _long24 = _fmtUsdZh(sumLong);
      _short24 = _fmtUsdZh(sumShort);
      _liqTotalText = _fmtUsdZh(sumTotal);
    }
  }

  static double _frac(double long, double short) {
    final d = long + short;
    return d <= 0 ? 0.5 : (long / d).clamp(0.0, 1.0);
  }

  static _RawEx? _matchRaw(List<_RawEx> raw, String name) {
    final key = _normName(name);
    for (final r in raw) {
      if (_normName(r.name) == key) return r;
    }
    return null;
  }

  static String _normName(String n) {
    var s = n.toLowerCase().replaceAll(RegExp(r'[\s.\-_]'), '');
    if (s == 'gateio') s = 'gate';
    return s;
  }

  // CoinGlass liquidation/exchange-list → 原始数值列表.
  static List<_RawEx>? _parseExchangeList(dynamic raw) {
    final list = _asList(raw);
    if (list.isEmpty) return null;
    final out = <_RawEx>[];
    for (final e in list) {
      if (e is! Map) continue;
      final m = e.cast<String, dynamic>();
      final name = _str(m,
          ['exchangeName', 'exchange_name', 'exchange', 'name'], '');
      if (name.isEmpty) continue;
      final long = _num(m['longLiquidationUsd'] ??
          m['longLiquidation_usd'] ??
          m['long_liquidation_usd'] ??
          m['longLiquidation'] ??
          m['longVolUsd'] ??
          m['long_vol_usd']);
      final short = _num(m['shortLiquidationUsd'] ??
          m['shortLiquidation_usd'] ??
          m['short_liquidation_usd'] ??
          m['shortLiquidation'] ??
          m['shortVolUsd'] ??
          m['short_vol_usd']);
      var total = _num(m['liquidationUsd'] ??
          m['liquidation_usd'] ??
          m['totalLiquidationUsd'] ??
          m['volUsd'] ??
          m['vol_usd']);
      if (total <= 0) total = long + short;
      if (total <= 0) continue;
      out.add(_RawEx(name: name, total: total, long: long, short: short));
    }
    return out.isEmpty ? null : out;
  }

  // ---- 解析/格式化辅助 ----
  static List<dynamic> _asList(dynamic v) {
    if (v is List) return v;
    if (v is Map) {
      for (final e in v.values) {
        if (e is List) return e;
      }
    }
    return const [];
  }

  static double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  static String _str(Map<String, dynamic> m, List<String> keys, String dflt) {
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.isNotEmpty) return v;
      if (v is num) return '$v';
    }
    return dflt;
  }

  static String _fmtUsdZh(double v) {
    final a = v.abs();
    if (a >= 1e8) return '\$${_trim(v / 1e8)}亿';
    if (a >= 1e4) return '\$${_trim(v / 1e4)}万';
    return '\$${v.toStringAsFixed(2)}';
  }

  static String _trim(double v) {
    if (v >= 1000) return v.toStringAsFixed(0);
    if (v >= 100) return v.toStringAsFixed(1);
    if (v >= 10) return v.toStringAsFixed(2);
    return v.toStringAsFixed(2);
  }

  // 热力分布文本查询: 优先真实数据, 缺失回退到传入的 mock 默认.
  String _heatAmt(String name, String dflt) {
    final s = _find(name);
    return s == null ? dflt : s.total;
  }

  String _heatPct(String name, String dflt) {
    final s = _find(name);
    return s == null ? dflt : s.pct;
  }

  _ExStat? _find(String name) {
    for (final e in _exStats) {
      if (e.name == name) return e;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      color: McColors.primaryContainer,
      backgroundColor: _surfaceContainer,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 32),
        children: [
          _buildAssetFilter(),
          const SizedBox(height: 16),
          _buildMonitorCard(),
          const SizedBox(height: 16),
          _buildTotalLiquidation(),
          const SizedBox(height: 16),
          _buildHeatmap(),
          const SizedBox(height: 16),
          _buildExchangeStats(),
          const SizedBox(height: 16),
          _buildRealtimeFeed(),
        ],
      ),
    );
  }

  // ---- Asset quick filter bar ----
  Widget _buildAssetFilter() {
    Widget chip(String label) {
      final active = _symbol == label;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _symbol = label),
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: EdgeInsets.symmetric(horizontal: active ? 14 : 12, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? McColors.primaryContainer
                : McColors.surfaceContainerHigh.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(999),
            border: active ? null : Border.all(color: _hairline),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: McColors.primaryContainer.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Text(
            label,
            style: McText.sans(
              size: 13,
              weight: active ? FontWeight.w600 : FontWeight.w500,
              color: active ? Colors.white : _onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('全部'),
          chip('BTC'),
          chip('ETH'),
          chip('SOL'),
          chip('HYPE'),
          chip('XRP'),
        ],
      ),
    );
  }

  // ---- 全网多空爆仓实时监控卡 (1H/4H/24H 可切换) ----
  Widget _buildMonitorCard() {
    final (total, long, short) =
        _sums[_monitorRange] ?? _sums['24h']!;
    final longPct = total > 0 ? (long / total * 100).round() : 50;

    Widget tf(String label, String range) {
      final active = _monitorRange == range;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _monitorRange = range),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: active ? McColors.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: McText.mono(
              size: 11,
              weight: active ? FontWeight.w700 : FontWeight.w400,
              color: active ? Colors.white : _onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return McCard(
      color: McColors.surfaceContainerLow,
      padding: const EdgeInsets.all(14),
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const McGlowDot(color: _bear, size: 8),
                  const SizedBox(width: 6),
                  Text('全网多空爆仓实时监控',
                      style: McText.sans(size: 13, weight: FontWeight.w600, color: Colors.white)),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: McColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _hairline),
                ),
                child: Row(
                  children: [tf('1H', '1h'), tf('4H', '4h'), tf('24H', '24h')],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmtUsdZh(total),
                  style: McText.mono(size: 20, weight: FontWeight.w800, color: _bear)),
              Text('多单 $longPct% · 空单 ${100 - longPct}%',
                  style: McText.mono(size: 12, color: _onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          // 多空爆仓比例条
          Container(
            height: 8,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: McColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: longPct.clamp(1, 99),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _bear,
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(4)),
                      boxShadow: [BoxShadow(color: _bear.withValues(alpha: 0.5), blurRadius: 8)],
                    ),
                  ),
                ),
                Expanded(
                  flex: (100 - longPct).clamp(1, 99),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _bull,
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                      boxShadow: [BoxShadow(color: _bull.withValues(alpha: 0.5), blurRadius: 8)],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('多头爆仓 ${_fmtUsdZh(long)}',
                  style: McText.mono(size: 12, color: _bear)),
              Text('空头爆仓 ${_fmtUsdZh(short)}',
                  style: McText.mono(size: 12, color: _bull)),
            ],
          ),
        ],
      ),
    );
  }

  // ---- Section header ----
  Widget _sectionHeader(String title, {String? trailing, Widget? trailingWidget, Widget? titleExtra}) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, right: 2, bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                title,
                style: McText.sans(size: 18, weight: FontWeight.w700, color: Colors.white),
              ),
              if (titleExtra != null) ...[const SizedBox(width: 8), titleExtra],
            ],
          ),
          if (trailingWidget != null)
            trailingWidget
          else if (trailing != null)
            Text(trailing, style: McText.sans(size: 12, color: _onSurfaceVariant)),
        ],
      ),
    );
  }

  // ---- SECTION 1: 总爆仓 ----
  Widget _buildTotalLiquidation() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          '总爆仓',
          trailingWidget: Row(
            children: [
              const McGlowDot(color: _bull, size: 6),
              const SizedBox(width: 4),
              Text('全网多空清洗测度', style: McText.mono(size: 12, color: _onSurfaceVariant)),
            ],
          ),
        ),
        McCard(
          color: McColors.surfaceContainerLow,
          padding: const EdgeInsets.all(16),
          radius: 16,
          child: Column(
            children: [
              _liqTimeRow(label: '1小时爆仓', total: _total1h, long: _long1h, short: _short1h),
              const SizedBox(height: 10),
              _liqTimeRow(label: '4小时爆仓', total: _total4h, long: _long4h, short: _short4h),
              const SizedBox(height: 10),
              _liqTimeRow(label: '12小时爆仓', total: _total12h, long: _long12h, short: _short12h),
              const SizedBox(height: 10),
              _liqTimeRow(
                label: '24小时爆仓',
                total: _total24,
                long: _long24,
                short: _short24,
                core: true,
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.only(top: 10),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: _hairline)),
                ),
                child: Column(
                  children: [
                    _bullet(
                      RichText(
                        text: TextSpan(
                          style: McText.sans(size: 12, color: _onSurfaceVariant, height: 1.5),
                          children: [
                            const TextSpan(text: '最近24小时，全球共有 '),
                            TextSpan(
                              text: _liqCount,
                              style: McText.mono(size: 12, weight: FontWeight.w600, color: _primaryLight),
                            ),
                            const TextSpan(text: ' 人被爆仓，爆仓总金额为 '),
                            TextSpan(
                              text: _liqTotalText,
                              style: McText.mono(size: 12, weight: FontWeight.w600, color: _primaryLight),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _bullet(
                      RichText(
                        text: TextSpan(
                          style: McText.sans(size: 12, color: _onSurfaceVariant, height: 1.5),
                          children: [
                            const TextSpan(text: '最大单笔爆仓单发生在 '),
                            TextSpan(
                              text: 'Binance-ETH',
                              style: McText.sans(size: 12, weight: FontWeight.w500, color: Colors.white),
                            ),
                            const TextSpan(text: ' 价值 '),
                            TextSpan(
                              text: '\$1,199.47万',
                              style: McText.mono(size: 12, weight: FontWeight.w600, color: _primaryLight),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bullet(Widget child) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: 6),
          decoration: const BoxDecoration(color: McColors.primaryContainer, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(child: child),
      ],
    );
  }

  Widget _liqTimeRow({
    required String label,
    required String total,
    required String long,
    required String short,
    bool core = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _hairline),
        gradient: core
            ? LinearGradient(
                colors: [
                  _surfaceContainer.withValues(alpha: 0.9),
                  McColors.primaryContainer.withValues(alpha: 0.1),
                ],
              )
            : null,
        color: core ? null : _surfaceContainer.withValues(alpha: 0.7),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    label,
                    style: McText.sans(
                      size: 12,
                      weight: core ? FontWeight.w600 : FontWeight.w400,
                      color: core ? Colors.white : _onSurfaceVariant,
                    ),
                  ),
                  if (core) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: McColors.primaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'CORE',
                        style: McText.sans(size: 12, weight: FontWeight.w700, color: _primaryLight),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                total,
                style: McText.mono(
                  size: core ? 19 : 17,
                  weight: core ? FontWeight.w800 : FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          Row(
            children: [
              _longShortCol('多单爆仓', long, _bullLight),
              const SizedBox(width: 24),
              SizedBox(width: 70, child: _longShortCol('空单爆仓', short, _bearLight)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _longShortCol(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: McText.sans(size: 12, color: _onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(value, style: McText.mono(size: 14, weight: FontWeight.w700, color: color)),
      ],
    );
  }

  // ---- SECTION 2: 交易所爆仓热力分布 (treemap) ----
  Widget _buildHeatmap() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('交易所爆仓热力分布', trailing: '合约全网体量图'),
        McCard(
          color: McColors.surfaceContainerLow,
          padding: const EdgeInsets.all(16),
          radius: 16,
          child: Column(
            children: [
              SizedBox(
                height: 250,
                child: Row(
                  children: [
                    // Binance big block
                    Expanded(
                      flex: 48,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              _bull.withValues(alpha: 0.9),
                              _bullDark.withValues(alpha: 0.95),
                            ],
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Binance',
                                    style: McText.sans(size: 17, weight: FontWeight.w700, color: Colors.white)),
                                Text('币安合约',
                                    style: McText.sans(
                                        size: 12,
                                        weight: FontWeight.w500,
                                        color: Colors.white.withValues(alpha: 0.8))),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_heatAmt('Binance', '\$1.6亿'),
                                    maxLines: 1, softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                    style: McText.mono(
                                        size: 21, weight: FontWeight.w800, color: Colors.white, height: 1)),
                                const SizedBox(height: 2),
                                Text('占比 ${_heatPct('Binance', '46.48%')}',
                                    style: McText.sans(
                                        size: 12,
                                        weight: FontWeight.w500,
                                        color: Colors.white.withValues(alpha: 0.9))),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Right column
                    Expanded(
                      flex: 52,
                      child: Column(
                        children: [
                          // Hyperliquid
                          Expanded(
                            flex: 36,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                gradient: LinearGradient(
                                  colors: [
                                    _bull.withValues(alpha: 0.85),
                                    _bullDark.withValues(alpha: 0.9),
                                  ],
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Hyperliquid',
                                          style: McText.sans(
                                              size: 14, weight: FontWeight.w700, color: Colors.white)),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(_heatPct('Hyperliquid', '16.2%'),
                                            maxLines: 1, softWrap: false,
                                            overflow: TextOverflow.ellipsis,
                                            style: McText.mono(size: 12, color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                  Text(_heatAmt('Hyperliquid', '\$5423.5万'),
                                      maxLines: 1, softWrap: false,
                                      overflow: TextOverflow.ellipsis,
                                      style: McText.mono(
                                          size: 15, weight: FontWeight.w700, color: Colors.white)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          // Middle & bottom split
                          Expanded(
                            flex: 64,
                            child: Row(
                              children: [
                                // OKX
                                Expanded(
                                  flex: 38,
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: _bull.withValues(alpha: 0.8),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('OKX',
                                                style: McText.sans(
                                                    size: 12, weight: FontWeight.w700, color: Colors.white)),
                                            Text('欧易',
                                                style: McText.sans(
                                                    size: 12,
                                                    color: Colors.white.withValues(alpha: 0.8))),
                                          ],
                                        ),
                                        Text(_heatAmt('OKX', '\$3734.6万'),
                                            maxLines: 1, softWrap: false,
                                            overflow: TextOverflow.ellipsis,
                                            style: McText.mono(
                                                size: 12, weight: FontWeight.w700, color: Colors.white)),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Bybit + Gate/Bitget
                                Expanded(
                                  flex: 62,
                                  child: Column(
                                    children: [
                                      Expanded(
                                        flex: 46,
                                        child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: _bull.withValues(alpha: 0.75),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('Bybit',
                                                  style: McText.sans(
                                                      size: 12, weight: FontWeight.w700, color: Colors.white)),
                                              Text(_heatAmt('Bybit', '\$3233.2万'),
                                                  maxLines: 1, softWrap: false,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: McText.mono(
                                                      size: 12, weight: FontWeight.w700, color: Colors.white)),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Expanded(
                                        flex: 54,
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Container(
                                                padding: const EdgeInsets.all(6),
                                                decoration: BoxDecoration(
                                                  color: _bull.withValues(alpha: 0.7),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Column(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text('Gate',
                                                        style: McText.sans(
                                                            size: 12,
                                                            weight: FontWeight.w700,
                                                            color: Colors.white)),
                                                    Text(_heatAmt('Gate', '\$2708万'),
                                                        maxLines: 1, softWrap: false,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: McText.mono(
                                                            size: 12,
                                                            weight: FontWeight.w700,
                                                            color: Colors.white)),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Column(
                                                children: [
                                                  Expanded(
                                                    child: Container(
                                                      width: double.infinity,
                                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                                      decoration: BoxDecoration(
                                                        color: _bull.withValues(alpha: 0.65),
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Column(
                                                        mainAxisAlignment: MainAxisAlignment.center,
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text('Bitget',
                                                              style: McText.sans(
                                                                  size: 12,
                                                                  weight: FontWeight.w700,
                                                                  color: Colors.white)),
                                                          Text(_heatAmt('Bitget', '\$1577万'),
                                                              maxLines: 1, softWrap: false,
                                                              overflow: TextOverflow.ellipsis,
                                                              style: McText.mono(
                                                                  size: 12,
                                                                  color: Colors.white.withValues(alpha: 0.9))),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  SizedBox(
                                                    height: 20,
                                                    child: Row(
                                                      children: [
                                                        Expanded(
                                                          child: Container(
                                                            decoration: BoxDecoration(
                                                              color: _bull.withValues(alpha: 0.5),
                                                              borderRadius: BorderRadius.circular(4),
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 4),
                                                        Expanded(
                                                          child: Container(
                                                            decoration: BoxDecoration(
                                                              color: _bear.withValues(alpha: 0.9),
                                                              borderRadius: BorderRadius.circular(4),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _legendDot(_bull, '多头清算主导'),
                    _legendDot(_bear, '空头清算主导'),
                    Text('实时根据成交刷新', style: McText.mono(size: 12, color: McColors.outline)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(label, style: McText.sans(size: 12, color: _onSurfaceVariant)),
      ],
    );
  }

  // ---- SECTION 3: 交易所爆仓统计 ----
  Widget _buildExchangeStats() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('交易所爆仓统计'),
        McCard(
          color: McColors.surfaceContainerLow,
          padding: const EdgeInsets.all(16),
          radius: 16,
          child: Column(
            children: [
              // Filter toolbar: 时段切换 (1h/4h/12h/24h)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  PopupMenuButton<String>(
                    color: _surfaceContainer,
                    initialValue: _statsRange,
                    onSelected: (v) {
                      setState(() => _statsRange = v);
                      _loadRangeStats(v);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: '1h', child: Text('1小时')),
                      PopupMenuItem(value: '4h', child: Text('4小时')),
                      PopupMenuItem(value: '12h', child: Text('12小时')),
                      PopupMenuItem(value: '24h', child: Text('24小时')),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: McColors.surfaceContainerHigh.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _hairline),
                      ),
                      child: Row(
                        children: [
                          Text(
                            const {
                              '1h': '1小时',
                              '4h': '4小时',
                              '12h': '12小时',
                              '24h': '24小时',
                            }[_statsRange]!,
                            style: McText.sans(size: 12, weight: FontWeight.w500, color: Colors.white),
                          ),
                          const Icon(Icons.arrow_drop_down, size: 16, color: _onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Column headers
              Container(
                padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _hairline))),
                child: Row(
                  children: [
                    Expanded(flex: 4, child: Text('交易所', style: _thStyle())),
                    Expanded(
                      flex: 3,
                      child: Align(alignment: Alignment.centerRight, child: Text('占比', style: _thStyle())),
                    ),
                    Expanded(
                      flex: 5,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('多单爆仓', style: _thStyle()),
                            Text('空单爆仓', style: _thStyle()),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              for (final s in _exStats) _statRow(s),
            ],
          ),
        ),
      ],
    );
  }

  TextStyle _thStyle() => McText.sans(size: 12, weight: FontWeight.w500, color: _onSurfaceVariant);

  Widget _statRow(_ExStat s) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: s.showDivider ? const Border(bottom: BorderSide(color: _hairline)) : null,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(color: s.avatarBg, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text(s.avatarLabel,
                      style: McText.sans(size: 12, weight: FontWeight.w700, color: s.avatarColor)),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    s.name,
                    overflow: TextOverflow.ellipsis,
                    style: McText.sans(
                      size: 13,
                      weight: s.boldName ? FontWeight.w700 : FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(s.total, style: McText.mono(size: 13, weight: FontWeight.w700, color: Colors.white)),
                Text(s.pct, style: McText.mono(size: 12, color: _onSurfaceVariant)),
              ],
            ),
          ),
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      height: 10,
                      color: McColors.surfaceContainerHighest,
                      child: Row(
                        children: [
                          Expanded(flex: (s.longFrac * 1000).round(), child: Container(color: _bullLight)),
                          Expanded(flex: ((1 - s.longFrac) * 1000).round(), child: Container(color: _bearLight)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(s.longText,
                            style: McText.mono(size: 12, weight: FontWeight.w500, color: _bull),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      Flexible(
                        child: Text(s.shortText,
                            style: McText.mono(size: 12, weight: FontWeight.w500, color: _bear),
                            maxLines: 1,
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- SECTION 4: 实时爆仓 ----
  Widget _buildRealtimeFeed() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          '实时爆仓',
          titleExtra: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: McColors.primaryContainer.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('LIVE', style: McText.mono(size: 12, weight: FontWeight.w600, color: _primaryLight)),
          ),
        ),
        McCard(
          color: McColors.surfaceContainerLow,
          padding: const EdgeInsets.all(16),
          radius: 16,
          child: Column(
            children: [
              // Filter toolbar: 金额阈值 + 刷新
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  PopupMenuButton<double>(
                    color: _surfaceContainer,
                    initialValue: _feedMinUsd,
                    onSelected: (v) => setState(() => _feedMinUsd = v),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 0, child: Text('全部')),
                      PopupMenuItem(value: 1000, child: Text('≥ 1千')),
                      PopupMenuItem(value: 10000, child: Text('≥ 1万')),
                      PopupMenuItem(value: 100000, child: Text('≥ 10万')),
                      PopupMenuItem(value: 1000000, child: Text('≥ 100万')),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: McColors.surfaceContainerHigh.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _hairline),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _feedMinUsd <= 0
                                ? '全部'
                                : '≥ ${_fmtUsdZh(_feedMinUsd).replaceAll('\$', '')}',
                            style: McText.sans(size: 12, weight: FontWeight.w500, color: Colors.white),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_drop_down, size: 16, color: _onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _load,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: McColors.surfaceContainerHigh.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _hairline),
                      ),
                      child: const Icon(Icons.refresh, size: 18, color: _onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Column headers
              Container(
                padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _hairline))),
                child: Row(
                  children: [
                    Expanded(flex: 4, child: Text('交易所', style: _thStyle())),
                    Expanded(
                      flex: 3,
                      child: Center(child: Text('价格', style: _thStyle())),
                    ),
                    Expanded(
                      flex: 3,
                      child: Align(alignment: Alignment.centerRight, child: Text('爆仓金额', style: _thStyle())),
                    ),
                    Expanded(
                      flex: 2,
                      child: Align(alignment: Alignment.centerRight, child: Text('时间', style: _thStyle())),
                    ),
                  ],
                ),
              ),
              // 币种 + 金额阈值过滤
              Builder(builder: (context) {
                final visible = _feedItems.where((f) {
                  if (_symbol != '全部' &&
                      !f.symbol.toUpperCase().contains(_symbol)) {
                    return false;
                  }
                  return f.amountUsd >= _feedMinUsd;
                }).toList();
                if (visible.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text('暂无符合筛选的爆仓单',
                          style: McText.sans(size: 12, color: _onSurfaceVariant)),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (var i = 0; i < visible.length; i++)
                      _feedRow(visible[i], showDivider: i < visible.length - 1),
                  ],
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _feedRow(_FeedItem item, {bool showDivider = true}) {
    final sideColor = item.long ? _bull : _bear;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: showDivider ? const Border(bottom: BorderSide(color: _hairline)) : null,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(color: item.avatarBg, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text(item.avatarLabel,
                      style: McText.sans(size: 12, weight: FontWeight.w700, color: item.avatarColor)),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name,
                          overflow: TextOverflow.ellipsis,
                          style: McText.sans(size: 13, weight: FontWeight.w600, color: Colors.white)),
                      Text(item.symbol, style: McText.mono(size: 12, color: _onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Text(item.price, style: McText.mono(size: 12, weight: FontWeight.w700, color: Colors.white)),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: sideColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.long ? '做多强平' : '做空强平',
                    style: McText.sans(size: 12, weight: FontWeight.w600, color: sideColor),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(item.amount,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: McText.mono(size: 13, weight: FontWeight.w700, color: item.amountColor)),
                Text(item.qty,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: McText.mono(size: 12, color: _onSurfaceVariant)),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(item.time, style: McText.mono(size: 12, color: _onSurfaceVariant)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 交易所爆仓统计行的不可变数据模型 (mock 与真实数据共用).
class _ExStat {
  const _ExStat({
    required this.avatarBg,
    required this.avatarLabel,
    required this.avatarColor,
    required this.name,
    required this.total,
    required this.pct,
    required this.longFrac,
    required this.longText,
    required this.shortText,
    this.boldName = false,
    this.showDivider = true,
  });

  final Color avatarBg;
  final String avatarLabel;
  final Color avatarColor;
  final String name;
  final String total;
  final String pct;
  final double longFrac;
  final String longText;
  final String shortText;
  final bool boldName;
  final bool showDivider;

  _ExStat copyWith({
    String? total,
    String? pct,
    double? longFrac,
    String? longText,
    String? shortText,
  }) {
    return _ExStat(
      avatarBg: avatarBg,
      avatarLabel: avatarLabel,
      avatarColor: avatarColor,
      name: name,
      total: total ?? this.total,
      pct: pct ?? this.pct,
      longFrac: longFrac ?? this.longFrac,
      longText: longText ?? this.longText,
      shortText: shortText ?? this.shortText,
      boldName: boldName,
      showDivider: showDivider,
    );
  }
}

/// 实时爆仓 feed 行的不可变数据模型 (mock 与真实数据共用).
class _FeedItem {
  const _FeedItem({
    required this.avatarBg,
    required this.avatarLabel,
    required this.avatarColor,
    required this.name,
    required this.symbol,
    required this.price,
    required this.long,
    required this.amount,
    required this.amountColor,
    required this.qty,
    required this.time,
    this.amountUsd = 0,
    this.showDivider = true,
  });

  final Color avatarBg;
  final String avatarLabel;
  final Color avatarColor;
  final String name;
  final String symbol;
  final String price;
  final bool long;
  final String amount;
  final Color amountColor;
  final String qty;
  final String time;
  final double amountUsd; // 原始美元值, 过滤用
  final bool showDivider;
}

/// 解析阶段的原始数值 (未格式化).
class _RawEx {
  const _RawEx({
    required this.name,
    required this.total,
    required this.long,
    required this.short,
  });

  final String name;
  final double total;
  final double long;
  final double short;
}

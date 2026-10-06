import 'dart:async';

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/api.dart';
import '../services/data.dart';

/// 多空爆仓 (Long/Short Liquidation) content body.
/// Palette overrides from stitch_ref/home_liquidation.html.
///
/// 总爆仓/交易所统计/热力分布尝试接
/// `/api/market-overview/liquidations/exchange-list?range=24h`; 首屏为骨架屏,
/// 失败(未配置 CoinGlass/上游错误/后端未启动)时显示 '--' 占位, 永不红屏也不显示假数字.
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

  // 首轮数据加载(成功或失败)完成后置 true, 控制首屏骨架屏.
  bool _loaded = false;

  // 24H 总爆仓卡: 首屏骨架, 数据到达后覆盖, 加载失败保持 '--'.
  String _total24 = '--';
  String _long24 = '--';
  String _short24 = '--';
  String _liqCount = '--'; // 爆仓笔数 (exchange-list count 求和)
  String _liqCountUnit = tr('liq_unit_orders');
  String _liqTotalText = '--';

  // 实时监控卡: range -> (total, long, short) 原始值, 拉取成功填充, 无数据显示 '--'.
  final Map<String, (double, double, double)> _sums = {};
  String _monitorRange = '24h'; // 监控卡当前时段

  // 顶部币种快捷过滤 ('全部' 或 BTC/ETH/...). 内部值固定中文, 显示经 liqSymbolLabel.
  String _symbol = '全部';
  // 实时 feed 最小金额过滤 (0=全部).
  double _feedMinUsd = 0;
  // 交易所统计当前时段.
  String _statsRange = '24h';

  // 分时段爆仓 (1h/4h/12h): 首屏骨架, 拉取成功后覆盖, 失败保持 '--'.
  String _total1h = '--';
  String _long1h = '--';
  String _short1h = '--';
  String _total4h = '--';
  String _long4h = '--';
  String _short4h = '--';
  String _total12h = '--';
  String _long12h = '--';
  String _short12h = '--';

  // 实时爆仓 feed: 首屏骨架, 轮询服务端聚合流 (Binance/Bybit/OKX 落库) 填充.
  // 不走手机直连 Binance WS — 国内网络对 fstream.binance.com 常被静默黑洞.
  final List<_FeedItem> _feedItems = [];
  Timer? _feedTimer;

  // 交易所统计行: 首屏骨架, 成功后按真实数据构建.
  List<_ExStat>? _exStats;

  // 已知交易所的展示元数据 (头像/配色); 数值全部来自接口, 无内置假数字.
  static const List<_ExMeta> _exMeta = [
    _ExMeta('Binance', Color(0x1AF3BA2F), '❖', Color(0xFFF3BA2F)),
    _ExMeta('Hyperliquid', Color(0x2610B981), 'HL', _bull),
    _ExMeta('OKX', Color(0x1AFFFFFF), 'OK', Colors.white),
    _ExMeta('Bybit', Color(0x1AF7A600), 'BY', Color(0xFFF7A600)),
    _ExMeta('Gate', Color(0x260052FF), 'GT', Color(0xFF0052FF)),
    _ExMeta('Bitget', Color(0x2600F0FF), 'BG', Color(0xFF00F0FF)),
  ];

  @override
  void initState() {
    super.initState();
    _startFeedPoll();
    _load();
  }

  @override
  void dispose() {
    _feedTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    // 各子加载内部均已捕获异常, 不会抛出; 成败都视为首轮完成.
    await Future.wait([
      _load24h(),
      _loadTimeframes(),
      _loadLiqCount(),
    ]);
    if (!mounted) return;
    setState(() => _loaded = true);
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
      // 503 未配置 / 502 上游错误 — 保持 '--' 占位.
    } catch (_) {
      // 网络/解析异常 — 保持 '--' 占位.
    }
  }

  // 1h/4h/12h 分时段: 并行拉取, 各所求和 -> 总爆仓+多单+空单. 任一失败保持 '--'.
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

  // 实时爆仓 feed: 轮询服务端 /liquidations/recent (Binance/Bybit/OKX
  // 强平 WS 已落库聚合), 每 10s 整体刷新. 替代手机直连 Binance WS
  // (国内网络常被黑洞, 且自建聚合覆盖面更大).
  void _startFeedPoll() {
    _loadFeed();
    _feedTimer = Timer.periodic(
        const Duration(seconds: 10), (_) => _loadFeed());
  }

  Future<void> _loadFeed() async {
    try {
      final resp = await McData.overview('liquidations/recent?limit=50');
      final list = _asList(resp['data']);
      final items = <_FeedItem>[];
      for (final e in list) {
        if (e is! Map) continue;
        final item = _toFeedItem(e.cast<String, dynamic>());
        if (item != null) items.add(item);
      }
      if (!mounted || items.isEmpty) return;
      setState(() {
        _feedItems
          ..clear()
          ..addAll(items);
      });
    } on ApiException {
      // 后端/上游异常 — 保持现有列表.
    } catch (_) {
      // 网络/解析异常 — 保持现有列表.
    }
  }

  static _FeedItem? _toFeedItem(Map<String, dynamic> m) {
    final exchange = (m['exchange'] ?? '').toString();
    final symbol = (m['symbol'] ?? '').toString();
    final usd = _num(m['notional_usd']);
    if (symbol.isEmpty || usd <= 0) return null;
    final isLong = m['side'] == 'long';
    final meta = _exMeta.firstWhere(
      (x) => x.name == exchange,
      orElse: () => _ExMeta(
        exchange.isEmpty ? tr('liq_unknown_ex') : exchange,
        const Color(0x1AFFFFFF),
        exchange.isEmpty ? '?' : exchange.substring(0, 1).toUpperCase(),
        Colors.white,
      ),
    );
    final ts = m['ts'] is num ? (m['ts'] as num).toInt() : 0;
    // 各所 symbol 形态不一: BTCUSDT / BTC-USDT, 统一剥计价币得基础币.
    final base = symbol
        .replaceAll('-USDT-SWAP', '')
        .replaceAll('-USDT', '')
        .replaceAll('USDT', '')
        .replaceAll('USDC', '');
    return _FeedItem(
      avatarBg: meta.avatarBg,
      avatarLabel: meta.avatarLabel,
      avatarColor: meta.avatarColor,
      name: meta.name,
      symbol: base,
      price: '\$${_fmtPrice(_num(m['price']))}',
      long: isLong,
      amount: _fmtUsdZh(usd),
      amountUsd: usd,
      amountColor: isLong ? _bull : _bear,
      qty: '≈${_fmtQty(_num(m['qty']))} $base',
      time: ts > 0 ? _fmtClock(ts) : '',
      showDivider: false,
    );
  }

  // 爆仓笔数: 自建聚合 exchange-list 的 count 字段求和 (OKX/Bybit 实时强平流).
  // free 模式有真实值; coinglass 模式无 count 时回退 coin-list 人数字段尝试.
  Future<void> _loadLiqCount() async {
    try {
      final resp = await McData.overview('liquidations/exchange-list?range=24h');
      final list = _asList(resp['data']);
      var sum = 0;
      for (final e in list) {
        if (e is! Map) continue;
        final c = e.cast<String, dynamic>()['count'];
        if (c is num) sum += c.toInt();
      }
      if (sum > 0 && mounted) {
        setState(() {
          _liqCount = _comma('$sum');
          _liqCountUnit = tr('liq_unit_orders');
        });
        return;
      }
    } on ApiException {
      // 落到 coin-list 尝试.
    } catch (_) {
      return;
    }
    // coinglass 模式回退: coin-list 人数字段 (多数套餐无此字段, 保持 --).
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
      setState(() {
        _liqCount = _comma(sum.toStringAsFixed(0));
        _liqCountUnit = tr('liq_unit_people');
      });
    } on ApiException {
      // 保留 --.
    } catch (_) {}
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

  // 应用解析结果: 按真实数据 + 已知交易所元数据构建统计行, 重算「全部」行;
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

    _ExStat buildRow({
      required Color avatarBg,
      required String avatarLabel,
      required Color avatarColor,
      required String name,
      required _RawEx match,
      bool boldName = false,
    }) {
      return _ExStat(
        avatarBg: avatarBg,
        avatarLabel: avatarLabel,
        avatarColor: avatarColor,
        name: name,
        total: _fmtUsdZh(match.total),
        pct: '${(match.total / sumTotal * 100).toStringAsFixed(2)}%',
        longFrac: _frac(match.long, match.short),
        longText: _fmtUsdZh(match.long),
        shortText: _fmtUsdZh(match.short),
        boldName: boldName,
      );
    }

    final rows = <_ExStat>[];
    final used = <String>{}; // 已匹配的规范化名称
    // 已知交易所: 按模板顺序, 仅展示接口实际返回的.
    for (final meta in _exMeta) {
      final match = _matchRaw(raw, meta.name);
      if (match == null) continue;
      used.add(_normName(meta.name));
      rows.add(buildRow(
        avatarBg: meta.avatarBg,
        avatarLabel: meta.avatarLabel,
        avatarColor: meta.avatarColor,
        name: meta.name,
        match: match,
      ));
    }
    // 未知交易所: 追加, 用首字母头像.
    for (final r in raw) {
      final key = _normName(r.name);
      if (key == 'all' || used.contains(key)) continue;
      rows.add(buildRow(
        avatarBg: McColors.surfaceContainerHighest,
        avatarLabel: r.name.isEmpty ? '?' : r.name[0].toUpperCase(),
        avatarColor: _primaryLight,
        name: r.name,
        match: r,
      ));
    }

    // 「全部」行置顶 (聚合值).
    final agg = _RawEx(name: '全部', total: sumTotal, long: sumLong, short: sumShort);
    final updated = <_ExStat>[
      buildRow(
        avatarBg: McColors.surfaceContainerHighest,
        avatarLabel: tr('liq_all_short'),
        avatarColor: _primaryLight,
        name: tr('liq_all'),
        match: agg,
        boldName: true,
      ),
      ...rows,
    ];
    // 末行不画分隔线.
    _exStats = [
      for (var i = 0; i < updated.length; i++)
        i == updated.length - 1
            ? updated[i].copyWith(showDivider: false)
            : updated[i],
    ];

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

  // 热力分布文本查询: 真实数据, 缺失(未加载/接口无该所)显示 '--'.
  String _heatAmt(String name) => _find(name)?.total ?? '--';

  String _heatPct(String name) => _find(name)?.pct ?? '--';

  _ExStat? _find(String name) {
    final list = _exStats;
    if (list == null) return null;
    for (final e in list) {
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
            label == '全部' ? tr('liq_all') : label,
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
    if (!_loaded) return McSkeleton.card(lines: 3, height: 16);
    final sums = _sums[_monitorRange] ?? _sums['24h'];
    final hasData = sums != null && sums.$1 > 0;
    final total = sums?.$1 ?? 0;
    final long = sums?.$2 ?? 0;
    final short = sums?.$3 ?? 0;
    final longPct = hasData ? (long / total * 100).round() : 50;

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
                  Text(tr('liq_monitor_title'),
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
              Text(hasData ? _fmtUsdZh(total) : '--',
                  style: McText.mono(size: 20, weight: FontWeight.w800, color: _bear)),
              Text(tr('liq_long_short_pct')
                  .replaceAll('{long}', '$longPct')
                  .replaceAll('{short}', '${100 - longPct}'),
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
              Text('${tr('liq_long_liq')} ${hasData ? _fmtUsdZh(long) : '--'}',
                  style: McText.mono(size: 12, color: _bear)),
              Text('${tr('liq_short_liq')} ${hasData ? _fmtUsdZh(short) : '--'}',
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
    if (!_loaded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(tr('liq_total_title')),
          McSkeleton.card(lines: 5, height: 16),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          tr('liq_total_title'),
          trailingWidget: Row(
            children: [
              const McGlowDot(color: _bull, size: 6),
              const SizedBox(width: 4),
              Text(tr('liq_total_trailing'), style: McText.mono(size: 12, color: _onSurfaceVariant)),
            ],
          ),
        ),
        McCard(
          color: McColors.surfaceContainerLow,
          padding: const EdgeInsets.all(16),
          radius: 16,
          child: Column(
            children: [
              _liqTimeRow(label: tr('liq_1h'), total: _total1h, long: _long1h, short: _short1h),
              const SizedBox(height: 10),
              _liqTimeRow(label: tr('liq_4h'), total: _total4h, long: _long4h, short: _short4h),
              const SizedBox(height: 10),
              _liqTimeRow(label: tr('liq_12h'), total: _total12h, long: _long12h, short: _short12h),
              const SizedBox(height: 10),
              _liqTimeRow(
                label: tr('liq_24h'),
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
                            TextSpan(text: tr('liq_summary_24h_pre')),
                            TextSpan(
                              text: _liqCount,
                              style: McText.mono(size: 12, weight: FontWeight.w600, color: _primaryLight),
                            ),
                            TextSpan(text: ' $_liqCountUnit${tr('liq_summary_24h_mid')}'),
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
                            TextSpan(text: tr('liq_largest_pre')),
                            TextSpan(
                              text: '--',
                              style: McText.sans(size: 12, weight: FontWeight.w500, color: Colors.white),
                            ),
                            TextSpan(text: tr('liq_largest_mid')),
                            TextSpan(
                              text: '--',
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
              _longShortCol(tr('liq_long_pos'), long, _bullLight),
              const SizedBox(width: 24),
              SizedBox(width: 70, child: _longShortCol(tr('liq_short_pos'), short, _bearLight)),
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
    if (!_loaded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(tr('liq_heatmap_title'), trailing: tr('liq_heatmap_trailing')),
          const McSkeleton(height: 250, radius: 16),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(tr('liq_heatmap_title'), trailing: tr('liq_heatmap_trailing')),
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
                                Text(tr('liq_binance_sub'),
                                    style: McText.sans(
                                        size: 12,
                                        weight: FontWeight.w500,
                                        color: Colors.white.withValues(alpha: 0.8))),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_heatAmt('Binance'),
                                    maxLines: 1, softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                    style: McText.mono(
                                        size: 21, weight: FontWeight.w800, color: Colors.white, height: 1)),
                                const SizedBox(height: 2),
                                Text('${tr('liq_share')} ${_heatPct('Binance')}',
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
                                        child: Text(_heatPct('Hyperliquid'),
                                            maxLines: 1, softWrap: false,
                                            overflow: TextOverflow.ellipsis,
                                            style: McText.mono(size: 12, color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                  Text(_heatAmt('Hyperliquid'),
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
                                            Text(tr('liq_okx_sub'),
                                                style: McText.sans(
                                                    size: 12,
                                                    color: Colors.white.withValues(alpha: 0.8))),
                                          ],
                                        ),
                                        Text(_heatAmt('OKX'),
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
                                              Text(_heatAmt('Bybit'),
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
                                                    Text(_heatAmt('Gate'),
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
                                                          Text(_heatAmt('Bitget'),
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
                    _legendDot(_bull, tr('liq_long_dominant')),
                    _legendDot(_bear, tr('liq_short_dominant')),
                    Text(tr('liq_realtime_note'), style: McText.mono(size: 12, color: McColors.outline)),
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
    if (!_loaded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(tr('liq_exchange_stats')),
          McSkeleton.card(lines: 5, height: 16),
        ],
      );
    }
    final stats = _exStats ?? const <_ExStat>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(tr('liq_exchange_stats')),
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
                    itemBuilder: (_) => [
                      PopupMenuItem(value: '1h', child: Text(tr('liq_range_1h'))),
                      PopupMenuItem(value: '4h', child: Text(tr('liq_range_4h'))),
                      PopupMenuItem(value: '12h', child: Text(tr('liq_range_12h'))),
                      PopupMenuItem(value: '24h', child: Text(tr('liq_range_24h'))),
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
                            {
                              '1h': tr('liq_range_1h'),
                              '4h': tr('liq_range_4h'),
                              '12h': tr('liq_range_12h'),
                              '24h': tr('liq_range_24h'),
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
                    Expanded(flex: 4, child: Text(tr('liq_col_exchange'), style: _thStyle())),
                    Expanded(
                      flex: 3,
                      child: Align(alignment: Alignment.centerRight, child: Text(tr('liq_col_share'), style: _thStyle())),
                    ),
                    Expanded(
                      flex: 5,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(tr('liq_long_pos'), style: _thStyle()),
                            Text(tr('liq_short_pos'), style: _thStyle()),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (stats.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(tr('no_data'), style: McText.sans(size: 12, color: _onSurfaceVariant)),
                  ),
                )
              else
                for (final s in stats) _statRow(s),
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
          tr('liq_realtime_title'),
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
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 0, child: Text(tr('liq_all'))),
                      PopupMenuItem(value: 1000, child: Text(tr('liq_ge_1k'))),
                      PopupMenuItem(value: 10000, child: Text(tr('liq_ge_1w'))),
                      PopupMenuItem(value: 100000, child: Text(tr('liq_ge_10w'))),
                      PopupMenuItem(value: 1000000, child: Text(tr('liq_ge_100w'))),
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
                                ? tr('liq_all')
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
                    Expanded(flex: 4, child: Text(tr('liq_col_exchange'), style: _thStyle())),
                    Expanded(
                      flex: 3,
                      child: Center(child: Text(tr('liq_col_price'), style: _thStyle())),
                    ),
                    Expanded(
                      flex: 3,
                      child: Align(alignment: Alignment.centerRight, child: Text(tr('liq_col_amount'), style: _thStyle())),
                    ),
                    Expanded(
                      flex: 2,
                      child: Align(alignment: Alignment.centerRight, child: Text(tr('liq_col_time'), style: _thStyle())),
                    ),
                  ],
                ),
              ),
              // 币种 + 金额阈值过滤
              if (!_loaded)
                const Column(
                  children: [
                    McSkeleton(height: 40, radius: 8),
                    SizedBox(height: 10),
                    McSkeleton(height: 40, radius: 8),
                    SizedBox(height: 10),
                    McSkeleton(height: 40, radius: 8),
                  ],
                )
              else
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
                        child: Text(tr('liq_no_match'),
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
                    item.long ? tr('liq_long_forced') : tr('liq_short_forced'),
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
    bool? showDivider,
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
      showDivider: showDivider ?? this.showDivider,
    );
  }
}

/// 已知交易所的展示元数据 (头像/配色), 不含任何数值.
class _ExMeta {
  const _ExMeta(this.name, this.avatarBg, this.avatarLabel, this.avatarColor);

  final String name;
  final Color avatarBg;
  final String avatarLabel;
  final Color avatarColor;
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

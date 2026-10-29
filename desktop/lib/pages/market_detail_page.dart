import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/kit.dart';

/// 行情详情页: 报价头(资金费率/自选/预警) + 蜡烛K线(MA/成交量/高低点/最新价线)
/// + 右栏 L2 盘口深度 + 逐笔成交 + 基础信息。8S 轮询刷新, 对齐网页版 MarketDetail。
class MarketDetailPage extends StatefulWidget {
  const MarketDetailPage({super.key, required this.instId});

  final String instId;

  @override
  State<MarketDetailPage> createState() => _MarketDetailPageState();
}

/// 单根 K 线 (OKX 数组 [ts,o,h,l,c,vol], 时间正序存储)。
class _Candle {
  const _Candle(this.ts, this.o, this.h, this.l, this.c, this.vol);
  final int ts;
  final double o, h, l, c, vol;
}

class _MarketDetailPageState extends State<MarketDetailPage> {
  /// 常见币种英文全名(纯展示,对齐网页版报价条)
  static const _coinNames = {
    'BTC': 'Bitcoin',
    'ETH': 'Ethereum',
    'SOL': 'Solana',
    'BNB': 'BNB',
    'XRP': 'Ripple',
    'DOGE': 'Dogecoin',
    'ADA': 'Cardano',
    'AVAX': 'Avalanche',
    'LINK': 'Chainlink',
    'TON': 'Toncoin',
  };

  static const _bars = ['15m', '1H', '4H', '1D', '1W'];
  static const _precisions = [0.01, 0.1, 1.0];
  static const _watchKey = 'mc_watchlist';

  // MA 系列色, 对齐网页版 (MA5=amber / MA10=浅蓝 / MA20=紫)
  static const _ma5Color = Mc.amber;
  static const _ma10Color = Color(0xFFB8C3FF);
  static const _ma20Color = Color(0xFFC26BFF);

  Timer? _timer;
  Timer? _cdTimer;
  String _bar = '1H';

  /// 当前币种 (页内切换币种会改写并全量重载)
  late String _instId;

  Map<String, dynamic>? _ticker;
  List<_Candle> _candles = [];
  Map<String, dynamic>? _funding;
  String _fCountdown = '--';
  List<List<dynamic>> _bids = const [];
  List<List<dynamic>> _asks = const []; // 已反转为价格高→低同 web
  List<Map<String, dynamic>> _trades = const [];

  double _precision = 0.1;
  bool _watched = false;
  bool _crossOn = false;
  int _resetTick = 0;

  bool _tickerLoading = true;
  String? _tickerError;
  bool _chartLoading = true;
  String? _chartError;

  String get _coin => _instId.split('-').first;
  bool get _isSwap => _instId.endsWith('-SWAP');

  /// 价格自适应小数位 (照抄 web pxDec)
  int get _dec => _pxDec(_candles.isEmpty ? 1 : _candles.last.c);

  static int _pxDec(double v) {
    final n = v.abs();
    if (n >= 1000) return 2;
    if (n >= 1) return n >= 100 ? 2 : 4;
    return 6;
  }

  static String _fmtFixed(num? v, int dec) {
    if (v == null) return '--';
    final pattern =
        dec <= 0 ? '#,##0' : '#,##0.${List.filled(dec, '0').join()}';
    return NumberFormat(pattern).format(v);
  }

  @override
  void initState() {
    super.initState();
    _instId = widget.instId;
    _loadTicker();
    _loadCandles();
    _loadBooks();
    _loadTrades();
    _loadFunding();
    _initWatch();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      _loadTicker(silent: true);
      _loadBooks(silent: true);
      _loadTrades(silent: true);
    });
    _cdTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickCountdown());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cdTimer?.cancel();
    super.dispose();
  }

  // ---------- 数据加载 ----------

  Future<void> _loadTicker({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _tickerLoading = true;
        _tickerError = null;
      });
    }
    try {
      final res = await ApiClient.I.ticker(_instId);
      final data = res is Map ? res['data'] : null;
      final ticker = data is List
          ? (data.isNotEmpty && data.first is Map
              ? Map<String, dynamic>.from(data.first as Map)
              : null)
          : (data is Map ? Map<String, dynamic>.from(data) : null);
      if (!mounted) return;
      setState(() {
        _ticker = ticker;
        _tickerLoading = false;
        _tickerError = ticker == null ? '暂无行情数据' : null;
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _tickerLoading = false;
        _tickerError = e is ApiException ? e.message : '行情加载失败';
      });
    }
  }

  Future<void> _loadCandles({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _chartLoading = true;
        _chartError = null;
      });
    }
    try {
      final res =
          await ApiClient.I.candles(_instId, bar: _bar, limit: 120);
      final raw = (res is Map ? res['data'] : null) as List? ?? const [];
      // OKX [ts,o,h,l,c,vol,...], 最新在前, 反转为时间正序
      final candles = <_Candle>[];
      for (final c in raw.reversed.whereType<List>()) {
        final ts = Fmt.toNum(c.isNotEmpty ? c[0] : null)?.toInt() ?? 0;
        final o = Fmt.toNum(c.length > 1 ? c[1] : null)?.toDouble();
        final h = Fmt.toNum(c.length > 2 ? c[2] : null)?.toDouble();
        final l = Fmt.toNum(c.length > 3 ? c[3] : null)?.toDouble();
        final cl = Fmt.toNum(c.length > 4 ? c[4] : null)?.toDouble();
        final vol = Fmt.toNum(c.length > 5 ? c[5] : null)?.toDouble() ?? 0;
        if (o == null || h == null || l == null || cl == null) continue;
        candles.add(_Candle(ts, o, h, l, cl, vol));
      }
      if (!mounted) return;
      setState(() {
        _candles = candles;
        _chartLoading = false;
        _chartError = null;
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _chartLoading = false;
        _chartError = e is ApiException ? e.message : 'K线加载失败';
      });
    }
  }

  Future<void> _loadBooks({bool silent = false}) async {
    try {
      final res = await ApiClient.I.books(_instId, sz: 14);
      final data = res is Map ? res['data'] : null;
      final d = data is List && data.isNotEmpty && data.first is Map
          ? data.first as Map
          : null;
      if (d == null || !mounted) return;
      final bids = (d['bids'] as List? ?? const []).whereType<List>().toList();
      // web: asks 反转 (最佳卖一在最下)
      final asks =
          (d['asks'] as List? ?? const []).whereType<List>().toList().reversed.toList();
      setState(() {
        _bids = bids;
        _asks = asks;
      });
    } catch (_) {
      /* 保留旧值 */
    }
  }

  Future<void> _loadTrades({bool silent = false}) async {
    try {
      final res = await ApiClient.I.trades(_instId, limit: 30);
      final data = (res is Map ? res['data'] : null) as List? ?? const [];
      final trades = data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted) return;
      setState(() => _trades = trades);
    } catch (_) {
      /* 保留旧值 */
    }
  }

  Future<void> _loadFunding() async {
    if (!_isSwap) return;
    try {
      final res = await ApiClient.I.fundingRate(_instId);
      final data = res is Map ? res['data'] : null;
      final f = data is List && data.isNotEmpty && data.first is Map
          ? Map<String, dynamic>.from(data.first as Map)
          : null;
      if (!mounted) return;
      setState(() => _funding = f);
    } catch (_) {
      /* 静默降级 */
    }
  }

  /// 资金费结算倒计时 (照抄 web tickCountdown)
  void _tickCountdown() {
    final t = Fmt.toNum(_funding?['nextFundingTime'])?.toInt() ?? 0;
    String v;
    if (t == 0) {
      v = '--';
    } else {
      var d = math.max(0, t - DateTime.now().millisecondsSinceEpoch);
      String p(int x) => x.toString().padLeft(2, '0');
      final h = d ~/ 3600000;
      d %= 3600000;
      final m = d ~/ 60000;
      final s = (d % 60000) ~/ 1000;
      v = '${p(h)}:${p(m)}:${p(s)}';
    }
    if (v != _fCountdown && mounted) setState(() => _fCountdown = v);
  }

  String get _fundingText {
    if (!_isSwap) return '--';
    final r = Fmt.toNum(_funding?['fundingRate']);
    if (r == null) return '--';
    return '${r >= 0 ? '+' : ''}${(r * 100).toStringAsFixed(4)}%';
  }

  // ---------- 自选 (shared_preferences, key 'mc_watchlist', StringList 存 instId) ----------

  Future<void> _initWatch() async {
    final sp = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _watched =
        (sp.getStringList(_watchKey) ?? const []).contains(_instId));
  }

  Future<void> _toggleWatch() async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList(_watchKey) ?? <String>[];
    if (list.contains(_instId)) {
      list.remove(_instId);
    } else {
      list.add(_instId);
    }
    await sp.setStringList(_watchKey, list);
    if (!mounted) return;
    setState(() => _watched = list.contains(_instId));
  }

  void _comingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('价格预警功能即将上线'),
      duration: Duration(seconds: 2),
    ));
  }

  void _switchBar(String bar) {
    if (bar == _bar) return;
    setState(() => _bar = bar);
    _loadCandles();
  }

  /// 页内切换币种: 清空全部数据并重载, 重置 K 线缩放, 轮询定时器继续复用。
  void _switchCoin(String instId) {
    if (instId == _instId) return;
    setState(() {
      _instId = instId;
      _ticker = null;
      _candles = [];
      _funding = null;
      _fCountdown = '--';
      _bids = const [];
      _asks = const [];
      _trades = const [];
      _watched = false;
      _tickerLoading = true;
      _chartLoading = true;
      _tickerError = null;
      _chartError = null;
      _resetTick++;
    });
    _loadTicker();
    _loadCandles();
    _loadBooks();
    _loadTrades();
    _loadFunding();
    _initWatch();
  }

  num _pct() {
    final t = _ticker;
    if (t == null) return 0;
    final open = Fmt.toNum(t['open24h']) ?? 0;
    if (open == 0) return 0;
    return ((Fmt.toNum(t['last']) ?? 0) - open) / open * 100;
  }

  // ---------- 盘口聚合 (照抄 web: 卖向上取整 / 买向下取整, 同档合并) ----------

  List<(double, double)> _aggLevels(List<List<dynamic>> levels, String side) {
    final p = _precision;
    final map = <String, double>{};
    for (final lv in levels) {
      final n = Fmt.toNum(lv.isNotEmpty ? lv[0] : null)?.toDouble();
      if (n == null) continue;
      final bucket =
          side == 'ask' ? (n / p).ceil() * p : (n / p).floor() * p;
      final key = bucket.toStringAsFixed(8);
      final sz = Fmt.toNum(lv.length > 1 ? lv[1] : null)?.toDouble() ?? 0;
      map[key] = (map[key] ?? 0) + sz;
    }
    final arr =
        map.entries.map((e) => (double.parse(e.key), e.value)).toList();
    arr.sort((a, b) =>
        side == 'ask' ? a.$1.compareTo(b.$1) : b.$1.compareTo(a.$1));
    return arr;
  }

  int get _pxDecimals =>
      _precision >= 1 ? 0 : (_precision >= 0.1 ? 1 : 2);

  static String _precLabel(double p) => p == 1.0 ? '1.0' : p.toString();

  // ---------- 页面骨架 ----------

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 20),
        McSection(
          '行情详情',
          tag: 'MARKET · ${_instId.toUpperCase()}',
          trailing: Text('8S AUTO REFRESH', style: Mc.tag()),
        ),
        const SizedBox(height: 14),
        _buildHeader(),
        const SizedBox(height: 14),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _buildChartCard()),
            const SizedBox(width: 14),
            SizedBox(
              width: 360,
              child: Column(children: [
                Expanded(flex: 5, child: _buildBookCard()),
                const SizedBox(height: 14),
                Expanded(flex: 4, child: _buildTradesCard()),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        _buildInfoCard(),
        const SizedBox(height: 20),
      ]),
    );
  }

  // ---------- A. 报价头: 币种 + 大价 + 涨跌 + 指标 + 费率倒计时 + 自选/预警按钮 ----------

  Widget _buildHeader() {
    final t = _ticker;
    final pct = _pct();
    final up = pct >= 0;
    final coinName = _coinNames[_coin] ?? _coin;
    final stats = <(String, String)>[
      ('24H最高', Fmt.num_(t?['high24h'])),
      ('24H最低', Fmt.num_(t?['low24h'])),
      ('24H成交量($_coin)', Fmt.compact(t?['vol24h'])),
      ('24H成交额(USDT)', Fmt.compact(t?['volCcy24h'])),
      if (_isSwap) ('资金费率/倒计时', '$_fundingText  $_fCountdown'),
    ];
    return McCard(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(children: [
          // 币种图标 + 名称 + 现货/永续徽标; 点击弹出切换币种面板
          _CoinSwitcher(
            instId: _instId,
            onSelect: _switchCoin,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Mc.cobalt.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: Mc.cobalt.withValues(alpha: 0.4)),
                ),
                child: Text(
                  _coin.isEmpty ? '?' : _coin.substring(0, 1),
                  style: Mc.mono(14, w: FontWeight.w700, color: Mc.cobaltSoft),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(coinName, style: Mc.display(18)),
                    const SizedBox(height: 2),
                    Row(children: [
                      Text('$_coin/USDT',
                          style: Mc.mono(11, color: Mc.muted)),
                      const SizedBox(width: 6),
                      McBadge('现货 SPOT',
                          color: _isSwap ? Mc.muted : Mc.cobaltSoft),
                      const SizedBox(width: 4),
                      McBadge('PERP 永续',
                          color: _isSwap ? Mc.cobaltSoft : Mc.muted),
                    ]),
                  ]),
              const SizedBox(width: 6),
              const Icon(Icons.unfold_more, size: 16, color: Mc.muted),
            ]),
          ),
          const SizedBox(width: 24),
          Container(width: 1, height: 40, color: Mc.hairline),
          const SizedBox(width: 24),
          // 大价 + 涨跌徽章
          if (_tickerLoading && t == null)
            const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Mc.cobaltSoft))
          else if (_tickerError != null && t == null)
            Text(_tickerError!, style: Mc.body(12, color: Mc.bear))
          else if (t != null) ...[
            Text(Fmt.num_(t['last']),
                style: Mc.mono(26,
                    w: FontWeight.w700, color: up ? Mc.up : Mc.down)),
            const SizedBox(width: 10),
            McBadge(Fmt.pct(pct), color: Mc.upDown(pct)),
          ],
          const Spacer(),
          McButton(
            _watched ? '已自选' : '加入自选',
            kind: McBtnKind.ghost,
            height: 36,
            icon: _watched ? Icons.star : Icons.star_border,
            onPressed: _toggleWatch,
          ),
          const SizedBox(width: 10),
          McButton(
            '设置价格预警',
            height: 36,
            icon: Icons.notifications_active_outlined,
            onPressed: _comingSoon,
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0) Container(width: 1, height: 30, color: Mc.hairline),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      McTag(stats[i].$1),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(stats[i].$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Mc.mono(13, w: FontWeight.w600)),
                      ),
                    ]),
              ),
            ),
          ],
        ]),
      ]),
    );
  }

  // ---------- B. K线卡: 周期 tabs + MA 读数 + 十字光标/重置缩放 + CustomPaint 蜡烛图 ----------

  Widget _buildChartCard() {
    return McCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(
            color: Mc.surface,
            border: Border(bottom: BorderSide(color: Mc.hairline)),
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(Mc.cardRadius)),
          ),
          child: Row(children: [
            for (final b in _bars) _barTab(b),
            const SizedBox(width: 8),
            // MA 指标读数
            Expanded(
              child: Row(children: [
                Container(width: 1, height: 18, color: Mc.hairline),
                const SizedBox(width: 10),
                for (final (i, m) in _maLegend().indexed) ...[
                  if (i > 0) const SizedBox(width: 16),
                  Flexible(
                    child: Text('${m.$1}  ${m.$3}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Mc.mono(10,
                            w: FontWeight.w600, color: m.$2)),
                  ),
                ],
              ]),
            ),
            const SizedBox(width: 8),
            Text('OKX · $_bar', style: Mc.mono(11, color: Mc.muted)),
            const SizedBox(width: 8),
            _toolBtn(
              Icons.adjust,
              tip: '十字光标',
              active: _crossOn,
              onTap: () => setState(() => _crossOn = !_crossOn),
            ),
            _toolBtn(
              Icons.restart_alt,
              tip: '重置缩放',
              onTap: () => setState(() => _resetTick++),
            ),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: _buildChartBody(),
          ),
        ),
      ]),
    );
  }

  Widget _toolBtn(IconData icon,
      {required String tip, required VoidCallback onTap, bool active = false}) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon,
              size: 18, color: active ? Mc.cobaltSoft : Mc.muted),
        ),
      ),
    );
  }

  /// MA 最新读数 (名称, 颜色, 值)
  List<(String, Color, String)> _maLegend() {
    final cs = _candles;
    if (cs.isEmpty) return const [];
    const defs = [
      ('MA5', 5, _ma5Color),
      ('MA10', 10, _ma10Color),
      ('MA20', 20, _ma20Color),
    ];
    return [
      for (final d in defs)
        (d.$1, d.$3, _fmtFixed(_maLast(cs, d.$2), _dec)),
    ];
  }

  static double? _maLast(List<_Candle> cs, int n) {
    if (cs.length < n) return null;
    var s = 0.0;
    for (var i = cs.length - n; i < cs.length; i++) {
      s += cs[i].c;
    }
    return s / n;
  }

  Widget _barTab(String bar) {
    final active = bar == _bar;
    return InkWell(
      onTap: () => _switchBar(bar),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? Mc.card : Colors.transparent,
          border: Border(
            bottom: BorderSide(
                color: active ? Mc.cobalt : Colors.transparent, width: 2),
          ),
        ),
        alignment: Alignment.center,
        child: Text(bar,
            style: Mc.body(12,
                w: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? Mc.ink : Mc.muted)),
      ),
    );
  }

  Widget _buildChartBody() {
    if (_chartLoading && _candles.isEmpty) {
      return const McLoading(label: 'K线加载中');
    }
    if (_chartError != null && _candles.isEmpty) {
      return McError(_chartError!, onRetry: _loadCandles);
    }
    if (_candles.length < 2) return const McEmpty('暂无走势数据');
    return _KlineChart(
      candles: _candles,
      bar: _bar,
      dec: _dec,
      crossOn: _crossOn,
      resetTick: _resetTick,
    );
  }

  // ---------- C1. 盘口深度卡 ----------

  Widget _buildBookCard() {
    final asks8 = _aggLevels(_asks, 'ask').take(6).toList().reversed.toList();
    final bids8 = _aggLevels(_bids, 'bid').take(6).toList();

    // 卖盘累计: 从最佳卖一(底部)向上累加
    final askCum = List<double>.filled(asks8.length, 0);
    var s = 0.0;
    for (var i = asks8.length - 1; i >= 0; i--) {
      s += asks8[i].$2;
      askCum[i] = s;
    }
    final askMax = askCum.isNotEmpty && askCum[0] > 0 ? askCum[0] : 1.0;
    // 买盘累计: 从最佳买一(顶部)向下累加
    final bidCum = <double>[];
    s = 0;
    for (final b in bids8) {
      s += b.$2;
      bidCum.add(s);
    }
    final bidMax = s > 0 ? s : 1.0;

    final bidSum = bids8.fold<double>(0, (a, b) => a + b.$2);
    final askSum = asks8.fold<double>(0, (a, b) => a + b.$2);
    final buyPct = (bidSum == 0 && askSum == 0)
        ? 50
        : (bidSum / (bidSum + askSum) * 100).round();
    final spread = asks8.isNotEmpty && bids8.isNotEmpty
        ? asks8.last.$1 - bids8.first.$1
        : null;

    final pct = _pct();
    final up = pct >= 0;

    return McCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        // 头: 标题 + 精度切换 + 买卖百分比条
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: const BoxDecoration(
            color: Mc.surface,
            border: Border(bottom: BorderSide(color: Mc.hairline)),
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(Mc.cardRadius)),
          ),
          child: Column(children: [
            Row(children: [
              Text('盘口深度', style: Mc.display(14)),
              const SizedBox(width: 8),
              const McTag('L2 ORDERBOOK'),
              const Spacer(),
              // 精度切换
              Container(
                decoration: BoxDecoration(
                  color: Mc.surface,
                  border: Border.all(color: Mc.hairline),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (final p in _precisions) _precBtn(p),
                ]),
              ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Text('买 $buyPct%',
                  style: Mc.mono(10, w: FontWeight.w600, color: Mc.up)),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 6,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Row(children: [
                      Expanded(
                          flex: buyPct, child: Container(color: Mc.up)),
                      Expanded(
                          flex: 100 - buyPct,
                          child: Container(color: Mc.down)),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('${100 - buyPct}% 卖',
                  style: Mc.mono(10, w: FontWeight.w600, color: Mc.down)),
            ]),
          ]),
        ),
        // 列头
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Mc.surface.withValues(alpha: 0.5),
            border: const Border(bottom: BorderSide(color: Mc.hairline)),
          ),
          child: Row(children: [
            Expanded(child: McTag('价格 (USD)')),
            Expanded(
                child: Align(
                    alignment: Alignment.centerRight,
                    child: McTag('数量 ($_coin)'))),
            Expanded(
                child: Align(
                    alignment: Alignment.centerRight,
                    child: McTag('累计深度'))),
          ]),
        ),
        // 卖盘 (高价在上, 贴底); 行数随可用高度自适应, 防矮屏溢出
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            if (asks8.isEmpty) return const McEmpty('暂无盘口数据');
            final fit = (c.maxHeight / 18).floor().clamp(1, asks8.length);
            final rows = asks8.sublist(asks8.length - fit);
            final off = asks8.length - fit;
            return Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (var i = 0; i < rows.length; i++)
                  _depthRow(rows[i].$1, rows[i].$2, askCum[off + i],
                      askCum[off + i] / askMax, Mc.down),
              ],
            );
          }),
        ),
        // 中间价差条
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            color: Mc.surface,
            border: Border.symmetric(
                horizontal: BorderSide(color: Mc.hairline)),
          ),
          child: Row(children: [
            Text(Fmt.num_(_ticker?['last']),
                style: Mc.mono(14,
                    w: FontWeight.w700, color: up ? Mc.up : Mc.down)),
            const SizedBox(width: 6),
            Icon(up ? Icons.north : Icons.south,
                size: 14, color: up ? Mc.up : Mc.down),
            const SizedBox(width: 4),
            Text(Fmt.pct(pct),
                style: Mc.mono(11, color: up ? Mc.up : Mc.down)),
            const Spacer(),
            Text('价差: ', style: Mc.mono(11, color: Mc.muted)),
            Text(
                spread != null
                    ? _fmtFixed(spread, _pxDecimals)
                    : '--',
                style: Mc.mono(11)),
          ]),
        ),
        // 买盘; 行数随可用高度自适应
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            if (bids8.isEmpty) return const SizedBox.shrink();
            final fit = (c.maxHeight / 18).floor().clamp(1, bids8.length);
            return Column(children: [
              for (var i = 0; i < fit; i++)
                _depthRow(bids8[i].$1, bids8[i].$2, bidCum[i],
                    bidCum[i] / bidMax, Mc.up),
            ]);
          }),
        ),
      ]),
    );
  }

  Widget _precBtn(double p) {
    final active = _precision == p;
    return InkWell(
      onTap: () => setState(() => _precision = p),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        color: active ? Mc.cardHigh : Colors.transparent,
        child: Text(_precLabel(p),
            style: Mc.mono(10,
                w: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? Mc.ink : Mc.muted)),
      ),
    );
  }

  /// 盘口单行: 右侧累计深度背景条 + 价格/数量/累计
  Widget _depthRow(
      double px, double sz, double cum, double ratio, Color color) {
    return SizedBox(
      height: 18,
      child: Stack(children: [
        Positioned.fill(
          child: Align(
            alignment: Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: ratio.clamp(0.0, 1.0),
              child: Container(color: color.withValues(alpha: 0.15)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Expanded(
                child: Text(_fmtFixed(px, _pxDecimals),
                    style: Mc.mono(11, w: FontWeight.w600, color: color))),
            Expanded(
                child: Text(sz.toStringAsFixed(3),
                    textAlign: TextAlign.right, style: Mc.mono(11))),
            Expanded(
                child: Text(cum.toStringAsFixed(3),
                    textAlign: TextAlign.right,
                    style: Mc.mono(11, color: Mc.muted))),
          ]),
        ),
      ]),
    );
  }

  // ---------- C2. 最新逐笔成交卡 ----------

  Widget _buildTradesCard() {
    final list = _trades.take(30).toList();
    // 大额单阈值: 均值 x4 (照抄 web whaleQty)
    var whaleQty = double.infinity;
    if (list.isNotEmpty) {
      final avg = list.fold<double>(
              0, (s, t) => s + (Fmt.toNum(t['sz'])?.toDouble() ?? 0)) /
          list.length;
      whaleQty = avg * 4;
    }
    return McCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(
            color: Mc.surface,
            border: Border(bottom: BorderSide(color: Mc.hairline)),
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(Mc.cardRadius)),
          ),
          child: Row(children: [
            Text('最新逐笔成交', style: Mc.display(14)),
            const SizedBox(width: 8),
            const McTag('RECENT TRADES'),
            const Spacer(),
            Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                    color: Mc.bull, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text('8S POLLING', style: Mc.mono(11, color: Mc.bull)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Mc.surface.withValues(alpha: 0.5),
            border: const Border(bottom: BorderSide(color: Mc.hairline)),
          ),
          child: Row(children: [
            const Expanded(child: McTag('时间')),
            const Expanded(
                child: Align(
                    alignment: Alignment.center, child: McTag('价格 (USD)'))),
            Expanded(
                child: Align(
                    alignment: Alignment.centerRight,
                    child: McTag('数量 ($_coin)'))),
          ]),
        ),
        Expanded(
          child: list.isEmpty
              ? const McEmpty('暂无成交数据')
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final t = list[i];
                    final sz = Fmt.toNum(t['sz'])?.toDouble() ?? 0;
                    final isBuy = t['side'] == 'buy';
                    final color = isBuy ? Mc.up : Mc.down;
                    final whale = sz >= whaleQty;
                    return Container(
                      color: whale ? color.withValues(alpha: 0.05) : null,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      child: Row(children: [
                        Expanded(
                            child: Text(_hms(t['ts']),
                                style: Mc.mono(11, color: Mc.muted))),
                        Expanded(
                            child: Text(Fmt.num_(t['px']),
                                textAlign: TextAlign.center,
                                style: Mc.mono(11,
                                    w: FontWeight.w600, color: color))),
                        Expanded(
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (whale) ...[
                                  McBadge('WHALE', color: color),
                                  const SizedBox(width: 4),
                                ],
                                Text(sz.toStringAsFixed(3),
                                    style: Mc.mono(11,
                                        w: whale
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: whale ? color : Mc.ink)),
                              ]),
                        ),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  /// HH:mm:ss (照抄 web fmtTime)
  static String _hms(dynamic v) {
    final t = Fmt.parseServerTime(v);
    if (t == null) return '--';
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(t.hour)}:${p(t.minute)}:${p(t.second)}';
  }

  // ---------- D. 基础信息 ----------

  Widget _buildInfoCard() {
    final t = _ticker;
    final items = <(String, String)>[
      ('24H开盘价', Fmt.num_(t?['open24h'])),
      ('UTC0开盘价', Fmt.num_(t?['sodUtc0'] ?? t?['openUtc0'])),
      ('UTC8开盘价', Fmt.num_(t?['sodUtc8'] ?? t?['openUtc8'])),
      ('买一价', Fmt.num_(t?['bidPx'])),
      ('卖一价', Fmt.num_(t?['askPx'])),
      ('数据时间', Fmt.mdHm(t?['ts'])),
    ];
    return McCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const McTag('BASIC INFO', color: Mc.cobaltSoft),
          const SizedBox(width: 10),
          Text('基础信息', style: Mc.display(16)),
        ]),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) Container(width: 1, height: 30, color: Mc.hairline),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        McTag(items[i].$1),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(items[i].$2,
                              style: Mc.mono(13, w: FontWeight.w600)),
                        ),
                      ]),
                ),
              ),
            ],
          ],
        ),
      ]),
    );
  }
}

/// 蜡烛 K 线图: CustomPaint 自绘 蜡烛+MA5/10/20+成交量副图+高低点标记+最新价标线,
/// 支持滚轮缩放 / 拖拽平移 / 十字光标。
class _KlineChart extends StatefulWidget {
  const _KlineChart({
    required this.candles,
    required this.bar,
    required this.dec,
    required this.crossOn,
    required this.resetTick,
  });

  final List<_Candle> candles;
  final String bar;
  final int dec;
  final bool crossOn;
  final int resetTick;

  @override
  State<_KlineChart> createState() => _KlineChartState();
}

class _KlineChartState extends State<_KlineChart> {
  double _visStart = 0;
  double _visCount = 72;
  bool _userZoomed = false;
  Offset? _hover;

  @override
  void initState() {
    super.initState();
    _resetWindow();
  }

  @override
  void didUpdateWidget(_KlineChart old) {
    super.didUpdateWidget(old);
    if (widget.resetTick != old.resetTick) {
      _userZoomed = false;
      _resetWindow();
    } else if (widget.candles != old.candles) {
      if (!_userZoomed) {
        _resetWindow();
      } else {
        _clampWindow();
      }
    }
  }

  /// 默认视窗: 展示最后 60% (对齐 web dataZoom start:40 end:100)
  void _resetWindow() {
    final n = widget.candles.length;
    final count = math.min(n, math.max(20, (n * 0.6).round())).toDouble();
    setState(() {
      _visCount = count;
      _visStart = math.max(0.0, n.toDouble() - count);
    });
  }

  void _clampWindow() {
    final n = widget.candles.length.toDouble();
    _visCount = _visCount.clamp(10.0, math.max(10.0, n)).toDouble();
    _visStart =
        _visStart.clamp(0.0, math.max(0.0, n - _visCount)).toDouble();
  }

  void _onDrag(DragUpdateDetails d) {
    final w = context.size?.width ?? 0;
    final plotW = w - _KlinePainter.leftPad - _KlinePainter.rightGutter;
    if (plotW <= 0) return;
    setState(() {
      _userZoomed = true;
      _visStart -= d.delta.dx * _visCount / plotW;
      _clampWindow();
    });
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final w = context.size?.width ?? 0;
    final plotW = w - _KlinePainter.leftPad - _KlinePainter.rightGutter;
    if (plotW <= 0) return;
    final factor = e.scrollDelta.dy > 0 ? 1.15 : 1 / 1.15;
    final anchor = ((e.localPosition.dx - _KlinePainter.leftPad) / plotW)
        .clamp(0.0, 1.0)
        .toDouble();
    final anchorIdx = _visStart + anchor * _visCount;
    final n = widget.candles.length.toDouble();
    setState(() {
      _userZoomed = true;
      _visCount *= factor;
      _clampWindow();
      _visStart = (anchorIdx - anchor * _visCount)
          .clamp(0.0, math.max(0.0, n - _visCount))
          .toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.candles;
    return Listener(
      onPointerSignal: _onSignal,
      child: MouseRegion(
        onHover: (e) => setState(() => _hover = e.localPosition),
        onExit: (_) => setState(() => _hover = null),
        child: GestureDetector(
          onHorizontalDragUpdate: _onDrag,
          child: CustomPaint(
            size: Size.infinite,
            painter: _KlinePainter(
              candles: cs,
              ma5: _calcMA(cs, 5),
              ma10: _calcMA(cs, 10),
              ma20: _calcMA(cs, 20),
              visStart: _visStart,
              visCount: _visCount,
              hover: _hover,
              crossOn: widget.crossOn,
              bar: widget.bar,
              dec: widget.dec,
            ),
          ),
        ),
      ),
    );
  }

  /// MA 序列 (照抄 web calcMA: 不足窗口为 null)
  static List<double?> _calcMA(List<_Candle> cs, int n) {
    final out = List<double?>.filled(cs.length, null);
    var s = 0.0;
    for (var i = 0; i < cs.length; i++) {
      s += cs[i].c;
      if (i >= n) s -= cs[i - n].c;
      if (i >= n - 1) out[i] = s / n;
    }
    return out;
  }
}

class _KlinePainter extends CustomPainter {
  _KlinePainter({
    required this.candles,
    required this.ma5,
    required this.ma10,
    required this.ma20,
    required this.visStart,
    required this.visCount,
    required this.hover,
    required this.crossOn,
    required this.bar,
    required this.dec,
  });

  final List<_Candle> candles;
  final List<double?> ma5, ma10, ma20;
  final double visStart, visCount;
  final Offset? hover;
  final bool crossOn;
  final String bar;
  final int dec;

  static const leftPad = 4.0;
  static const rightGutter = 64.0;
  static const _topPad = 10.0;
  static const _bottomAxisH = 18.0;

  String _fmtP(num v) {
    final pattern =
        dec <= 0 ? '#,##0' : '#,##0.${List.filled(dec, '0').join()}';
    return NumberFormat(pattern).format(v);
  }

  static String _md(int ts) {
    final t = DateTime.fromMillisecondsSinceEpoch(ts);
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(t.month)}-${p(t.day)}';
  }

  String _timeOf(int ts) =>
      (bar == '1D' || bar == '1W') ? _md(ts) : Fmt.hm(ts);

  void _dash(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0, gap = 4.0;
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final e = math.min(d + dash, total);
      canvas.drawLine(a + dir * d, a + dir * e, paint);
      d += dash + gap;
    }
  }

  TextPainter _tp(String text, TextStyle style,
      {TextAlign align = TextAlign.left}) {
    return TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = candles.length;
    if (n == 0) return;
    final up = Mc.up, down = Mc.down;

    final plotW = size.width - leftPad - rightGutter;
    final chartH = size.height - _topPad - _bottomAxisH;
    if (plotW <= 0 || chartH <= 0) return;
    final priceH = chartH * 0.66;
    final volTop = _topPad + chartH * 0.74;
    final volH = chartH * 0.24;

    final count = visCount.clamp(2.0, n.toDouble()).toDouble();
    final start = visStart.clamp(0.0, (n - 1).toDouble()).toDouble();
    final i0 = math.min(math.max(start.floor(), 0), n - 1);
    final i1 = math.min(math.max((start + count).ceil(), i0 + 1), n);

    var minY = double.infinity, maxY = double.negativeInfinity, maxVol = 0.0;
    for (var i = i0; i < i1; i++) {
      final c = candles[i];
      if (c.l < minY) minY = c.l;
      if (c.h > maxY) maxY = c.h;
      if (c.vol > maxVol) maxVol = c.vol;
    }
    if (!minY.isFinite || !maxY.isFinite) return;
    var pad = (maxY - minY) * 0.08;
    if (pad <= 0) pad = maxY.abs() * 0.001 + 1e-9;
    minY -= pad;
    maxY += pad;

    double xOf(int i) => leftPad + (i - start + 0.5) * plotW / count;
    double yOf(double v) => _topPad + (maxY - v) / (maxY - minY) * priceH;

    final gridPaint = Paint()
      ..color = Mc.hairline.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    // 水平网格 + 右侧价格轴 (4 格)
    for (var g = 0; g <= 4; g++) {
      final y = _topPad + priceH * g / 4;
      canvas.drawLine(Offset(leftPad, y), Offset(leftPad + plotW, y), gridPaint);
      final v = maxY - (maxY - minY) * g / 4;
      final tp = _tp(_fmtP(v), Mc.mono(10, color: Mc.muted));
      tp.paint(canvas, Offset(leftPad + plotW + 6, y - tp.height / 2));
    }

    // 底部时间轴 (5 格)
    for (var g = 0; g <= 4; g++) {
      final idx = math.min(
          math.max((i0 + (i1 - i0 - 1) * g / 4).round(), i0), i1 - 1);
      final label = _timeOf(candles[idx].ts);
      if (label == '--') continue;
      final tp = _tp(label, Mc.mono(10, color: Mc.muted));
      final x = (xOf(idx) - tp.width / 2)
          .clamp(leftPad, leftPad + plotW - tp.width)
          .toDouble();
      tp.paint(canvas, Offset(x, size.height - _bottomAxisH + 4));
    }

    // 成交量副图
    if (maxVol > 0) {
      final bw = math.max(1.0, plotW / count * 0.7);
      for (var i = i0; i < i1; i++) {
        final c = candles[i];
        final h = c.vol / maxVol * volH;
        final paint = Paint()
          ..color = (c.c >= c.o ? up : down).withValues(alpha: 0.5);
        canvas.drawRect(
            Rect.fromCenter(
                center: Offset(xOf(i), volTop + volH - h / 2),
                width: bw,
                height: h),
            paint);
      }
    }

    // 蜡烛
    final cw = (plotW / count * 0.7).clamp(1.0, 24.0).toDouble();
    for (var i = i0; i < i1; i++) {
      final c = candles[i];
      final color = c.c >= c.o ? up : down;
      final paint = Paint()..color = color;
      final x = xOf(i);
      canvas.drawLine(Offset(x, yOf(c.h)), Offset(x, yOf(c.l)),
          Paint()
            ..color = color
            ..strokeWidth = math.max(1.0, cw * 0.12));
      final yO = yOf(c.o), yC = yOf(c.c);
      final topY = math.min(yO, yC);
      final bodyH = math.max(1.0, (yC - yO).abs());
      canvas.drawRect(
          Rect.fromCenter(
              center: Offset(x, topY + bodyH / 2), width: cw, height: bodyH),
          paint);
    }

    // MA 线
    _paintMA(canvas, ma5, i0, i1, xOf, yOf, _MarketDetailPageState._ma5Color);
    _paintMA(canvas, ma10, i0, i1, xOf, yOf, _MarketDetailPageState._ma10Color);
    _paintMA(canvas, ma20, i0, i1, xOf, yOf, _MarketDetailPageState._ma20Color);

    // 最高/最低点标记: 基于当前视口可见K线, 随缩放/平移实时变化
    var hi = double.negativeInfinity, lo = double.infinity, hiI = -1, loI = -1;
    for (var i = i0; i < i1; i++) {
      if (candles[i].h > hi) {
        hi = candles[i].h;
        hiI = i;
      }
      if (candles[i].l < lo) {
        lo = candles[i].l;
        loI = i;
      }
    }
    if (hiI >= 0) {
      _marker(canvas, '高 ${_fmtP(hi)}', xOf(hiI), yOf(hi), above: true);
    }
    if (loI >= 0) {
      _marker(canvas, '低 ${_fmtP(lo)}', xOf(loI), yOf(lo), above: false);
    }

    // 最新价标线 (虚线 + 右侧价格标签)
    final last = candles[n - 1];
    final lastColor = last.c >= last.o ? up : down;
    final lastY = yOf(last.c).clamp(_topPad, _topPad + priceH).toDouble();
    _dash(canvas, Offset(leftPad, lastY), Offset(leftPad + plotW, lastY),
        Paint()
          ..color = lastColor.withValues(alpha: 0.8)
          ..strokeWidth = 1);
    final ltp = _tp(_fmtP(last.c),
        Mc.mono(10, w: FontWeight.w600, color: Mc.canvas));
    final lRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(leftPad + plotW + rightGutter / 2, lastY),
            width: ltp.width + 10,
            height: 16),
        const Radius.circular(2));
    canvas.drawRRect(lRect, Paint()..color = lastColor);
    ltp.paint(canvas, Offset(leftPad + plotW + rightGutter / 2 - ltp.width / 2,
        lastY - ltp.height / 2));

    // 十字光标 / 竖线光标
    final h = hover;
    if (h != null &&
        h.dx >= leftPad &&
        h.dx <= leftPad + plotW &&
        h.dy >= _topPad &&
        h.dy <= _topPad + chartH) {
      final hi2 = math.min(
          math.max(
              (start + (h.dx - leftPad) / plotW * count).round(), i0),
          i1 - 1);
      final cx = xOf(hi2);
      final cursorPaint = Paint()
        ..color = Mc.muted.withValues(alpha: 0.6)
        ..strokeWidth = 1;
      if (crossOn) {
        _dash(canvas, Offset(cx, _topPad), Offset(cx, volTop + volH),
            cursorPaint);
        final cy = h.dy.clamp(_topPad, _topPad + priceH).toDouble();
        _dash(canvas, Offset(leftPad, cy), Offset(leftPad + plotW, cy),
            cursorPaint);
        // 右侧价格标签
        final pv = maxY - (cy - _topPad) / priceH * (maxY - minY);
        final ptp = _tp(_fmtP(pv),
            Mc.mono(10, w: FontWeight.w600, color: Mc.ink));
        final pRect = RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(leftPad + plotW + rightGutter / 2, cy),
                width: ptp.width + 10,
                height: 16),
            const Radius.circular(2));
        canvas.drawRRect(pRect, Paint()..color = Mc.cardHigh);
        canvas.drawRRect(
            pRect,
            Paint()
              ..color = Mc.hairline
              ..style = PaintingStyle.stroke);
        ptp.paint(
            canvas,
            Offset(leftPad + plotW + rightGutter / 2 - ptp.width / 2,
                cy - ptp.height / 2));
        // 底部时间标签
        final ttp = _tp(Fmt.mdHm(candles[hi2].ts),
            Mc.mono(10, w: FontWeight.w600, color: Mc.ink));
        final tx = (cx - (ttp.width + 10) / 2)
            .clamp(leftPad, leftPad + plotW - ttp.width - 10)
            .toDouble();
        final tRect = RRect.fromRectAndRadius(
            Rect.fromCenter(
                center:
                    Offset(tx + (ttp.width + 10) / 2, size.height - _bottomAxisH / 2),
                width: ttp.width + 10,
                height: 16),
            const Radius.circular(2));
        canvas.drawRRect(tRect, Paint()..color = Mc.cardHigh);
        canvas.drawRRect(
            tRect,
            Paint()
              ..color = Mc.hairline
              ..style = PaintingStyle.stroke);
        ttp.paint(canvas,
            Offset(tx + 5, size.height - _bottomAxisH / 2 - ttp.height / 2));
      } else {
        canvas.drawLine(Offset(cx, _topPad), Offset(cx, volTop + volH),
            cursorPaint);
      }
      _infoBox(canvas, hi2, h, plotW, size.height - _bottomAxisH);
    }
  }

  void _paintMA(Canvas canvas, List<double?> ma, int i0, int i1,
      double Function(int) xOf, double Function(double) yOf, Color color) {
    final path = Path();
    var started = false;
    for (var i = i0; i < i1 && i < ma.length; i++) {
      final v = ma[i];
      if (v == null) continue;
      final p = Offset(xOf(i), yOf(v));
      if (!started) {
        path.moveTo(p.dx, p.dy);
        started = true;
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    if (!started) return;
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke);
  }

  /// 高低点文字标签 (对齐 web markPoint)
  void _marker(Canvas canvas, String text, double x, double y,
      {required bool above}) {
    final tp = _tp(text, Mc.mono(10, color: Mc.ink));
    final w = tp.width + 10, h = tp.height + 6;
    var rect = Rect.fromCenter(
        center: Offset(x, above ? y - h / 2 - 4 : y + h / 2 + 4),
        width: w,
        height: h);
    if (rect.top < 0) rect = rect.translate(0, -rect.top);
    final r = RRect.fromRectAndRadius(rect, const Radius.circular(3));
    canvas.drawRRect(r, Paint()..color = Mc.surface.withValues(alpha: 0.85));
    canvas.drawRRect(
        r,
        Paint()
          ..color = Mc.hairline
          ..style = PaintingStyle.stroke);
    tp.paint(canvas, Offset(rect.left + 5, rect.top + 3));
  }

  /// 悬停信息框: 时间 / 开收 / 高低 / 涨跌 / 量 (对齐 web tooltip)
  /// 悬停信息框: 跟随光标 (默认右下, 越界翻转左上), 夹在绘图区内。
  void _infoBox(Canvas canvas, int i, Offset hover, double plotW,
      double bottom) {
    final c = candles[i];
    final chg = c.o != 0 ? (c.c - c.o) / c.o * 100 : 0.0;
    final cc = chg >= 0 ? Mc.up : Mc.down;
    final muted = Mc.mono(10, color: Mc.muted);
    final ink = Mc.mono(10, w: FontWeight.w600);
    final tp = TextPainter(
      text: TextSpan(children: [
        TextSpan(text: '${Fmt.mdHm(c.ts)}\n', style: muted),
        TextSpan(text: '开 ', style: muted),
        TextSpan(text: _fmtP(c.o), style: ink),
        TextSpan(text: '   收 ', style: muted),
        TextSpan(text: '${_fmtP(c.c)}\n', style: ink.copyWith(color: cc)),
        TextSpan(text: '高 ', style: muted),
        TextSpan(text: _fmtP(c.h), style: ink.copyWith(color: Mc.up)),
        TextSpan(text: '   低 ', style: muted),
        TextSpan(text: '${_fmtP(c.l)}\n', style: ink.copyWith(color: Mc.down)),
        TextSpan(text: '涨跌 ', style: muted),
        TextSpan(
            text: '${chg >= 0 ? '+' : ''}${chg.toStringAsFixed(2)}%',
            style: ink.copyWith(color: cc)),
        TextSpan(text: '   量 ', style: muted),
        TextSpan(text: Fmt.compact(c.vol), style: ink),
      ]),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 340);
    const px0 = leftPad + 8, py0 = _topPad + 8;
    final w = tp.width + 16, hgt = tp.height + 12;
    final right = leftPad + plotW;
    // 默认光标右下 14px; 右侧放不下翻转到左, 底部放不下翻转到上
    var px = hover.dx + 14;
    if (px + w > right - 4) px = hover.dx - w - 14;
    px = px.clamp(px0, right - w - 4);
    var py = hover.dy + 14;
    if (py + hgt > bottom - 4) py = hover.dy - hgt - 14;
    py = py.clamp(py0, bottom - hgt - 4);
    final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(px, py, w, hgt), const Radius.circular(6));
    canvas.drawRRect(rect, Paint()..color = Mc.surface.withValues(alpha: 0.95));
    canvas.drawRRect(
        rect,
        Paint()
          ..color = Mc.hairline
          ..style = PaintingStyle.stroke);
    tp.paint(canvas, Offset(px + 8, py + 6));
  }

  @override
  bool shouldRepaint(_KlinePainter old) =>
      old.candles != candles ||
      old.visStart != visStart ||
      old.visCount != visCount ||
      old.hover != hover ||
      old.crossOn != crossOn ||
      old.bar != bar ||
      old.dec != dec;
}

/// 币种切换器: 点击报价头币种区弹出面板 (搜索 + 现货/永续 tab + 列表),
/// 选中后回调 onSelect 由详情页原地重载。Overlay 模式照抄 shell _NotifBell。
class _CoinSwitcher extends StatefulWidget {
  const _CoinSwitcher({
    required this.instId,
    required this.onSelect,
    required this.child,
  });

  final String instId;
  final ValueChanged<String> onSelect;
  final Widget child;

  @override
  State<_CoinSwitcher> createState() => _CoinSwitcherState();
}

class _CoinSwitcherState extends State<_CoinSwitcher> {
  final _link = LayerLink();
  final _search = TextEditingController();
  OverlayEntry? _entry;

  /// tab: false=现货 SPOT, true=永续 PERP
  bool _swap = false;
  List<Map<String, dynamic>> _spot = const [];
  List<Map<String, dynamic>> _swapRows = const [];
  bool _loading = false;
  bool _loaded = false;
  String? _error;

  @override
  void dispose() {
    _close();
    _search.dispose();
    super.dispose();
  }

  bool get _isCurrentSwap => widget.instId.endsWith('-SWAP');

  void _toggle() {
    if (_entry != null) {
      _close();
      return;
    }
    _swap = _isCurrentSwap;
    if (!_loaded && !_loading) _load();
    _entry = _buildEntry();
    Overlay.of(context).insert(_entry!);
  }

  void _close() {
    _entry?.remove();
    _entry = null;
  }

  Future<void> _load() async {
    _loading = true;
    _error = null;
    try {
      final res = await Future.wait([
        ApiClient.I.tickers(instType: 'SPOT'),
        ApiClient.I.tickers(instType: 'SWAP'),
      ]);
      List<Map<String, dynamic>> parse(dynamic r, String suffix) {
        final list = (r is Map ? r['data'] : null) as List? ?? const [];
        return list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where((t) => (t['instId'] as String? ?? '').endsWith(suffix))
            .toList()
          ..sort((a, b) => (Fmt.toNum(b['volCcy24h']) ?? 0)
              .compareTo(Fmt.toNum(a['volCcy24h']) ?? 0));
      }

      _spot = parse(res[0], '-USDT');
      _swapRows = parse(res[1], '-USDT-SWAP');
      _loaded = true;
    } catch (_) {
      _error = '币种列表加载失败';
    }
    _loading = false;
    if (mounted) setState(() {});
    _entry?.markNeedsBuild();
  }

  void _pick(String instId) {
    _close();
    widget.onSelect(instId);
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.text.trim().toUpperCase();
    final src = _swap ? _swapRows : _spot;
    if (q.isEmpty) return src;
    return src
        .where(
            (t) => (t['instId'] as String? ?? '').toUpperCase().contains(q))
        .toList();
  }

  OverlayEntry _buildEntry() {
    return OverlayEntry(builder: (context) {
      return Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 8),
          child: Material(color: Colors.transparent, child: _buildPanel()),
        ),
      ]);
    });
  }

  Widget _buildPanel() {
    return Container(
      width: 340,
      height: 440,
      decoration: BoxDecoration(
        color: Mc.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Mc.hairline),
        boxShadow: const [
          BoxShadow(
              color: Colors.black54, blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: Column(children: [
        // 搜索框
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: McInput(
            controller: _search,
            hint: '搜索币种 (如 BTC)',
            prefix: Icons.search,
            onChanged: (_) {
              setState(() {});
              _entry?.markNeedsBuild();
            },
          ),
        ),
        // 现货 / 永续 tab
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            _tabBtn('现货 SPOT', !_swap, () {
              _swap = false;
              setState(() {});
              _entry?.markNeedsBuild();
            }),
            const SizedBox(width: 8),
            _tabBtn('永续 PERP', _swap, () {
              _swap = true;
              setState(() {});
              _entry?.markNeedsBuild();
            }),
            const Spacer(),
            Text('${(_swap ? _swapRows : _spot).length} 个',
                style: Mc.mono(10, color: Mc.muted)),
          ]),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1, color: Mc.hairline),
        // 列表
        Expanded(child: _buildList()),
      ]),
    );
  }

  Widget _tabBtn(String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color:
              active ? Mc.cobalt.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color:
                  active ? Mc.cobalt.withValues(alpha: 0.5) : Mc.hairline),
        ),
        child: Text(label,
            style: Mc.body(11,
                w: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? Mc.cobaltSoft : Mc.muted)),
      ),
    );
  }

  Widget _buildList() {
    if (_loading && !_loaded) return const McLoading(label: '币种加载中');
    if (_error != null && !_loaded) {
      return McError(_error!, onRetry: () {
        _load();
        _entry?.markNeedsBuild();
      });
    }
    final rows = _filtered;
    if (rows.isEmpty) return const McEmpty('无匹配币种');
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: rows.length,
      itemBuilder: (_, i) {
        final t = rows[i];
        final id = t['instId'] as String? ?? '';
        final coin = id.split('-').first;
        final open = Fmt.toNum(t['open24h']) ?? 0;
        final last = Fmt.toNum(t['last']) ?? 0;
        final pct = open > 0 ? (last - open) / open * 100 : 0;
        final current = id == widget.instId;
        return InkWell(
          onTap: () => _pick(id),
          child: Container(
            color: current ? Mc.cardHigh.withValues(alpha: 0.6) : null,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Mc.cobalt.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Text(coin.isEmpty ? '?' : coin.substring(0, 1),
                    style: Mc.mono(10,
                        w: FontWeight.w700, color: Mc.cobaltSoft)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(coin,
                          style: Mc.body(13,
                              w: FontWeight.w600,
                              color: current ? Mc.cobaltSoft : Mc.ink)),
                      Text(id, style: Mc.mono(10, color: Mc.muted)),
                    ]),
              ),
              Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(Fmt.num_(t['last']), style: Mc.mono(12)),
                    Text(Fmt.pct(pct),
                        style: Mc.mono(10, color: Mc.upDown(pct))),
                  ]),
            ]),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
            padding: const EdgeInsets.all(4), child: widget.child),
      ),
    );
  }
}

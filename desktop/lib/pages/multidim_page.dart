import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/kit.dart';

/// 多维量化页: 多空比 / 恐慌贪婪仪表 / 未平仓持仓量 / 稳定币流向 /
/// 资金费率热力矩阵 / 多维量化指数卡。
/// 数据组织参考 web-terminal/src/views/MultiDim.vue。
class MultiDimPage extends StatefulWidget {
  const MultiDimPage({super.key});

  @override
  State<MultiDimPage> createState() => _MultiDimPageState();
}

class _MultiDimPageState extends State<MultiDimPage> {
  bool _loading = true;
  bool _fatal = false;

  Map<String, dynamic> _ls = const {};
  Map<String, dynamic> _oi = const {};
  Map<String, dynamic> _liquidity = const {};
  num? _sentiment;
  List<dynamic> _indicators = const [];
  List<dynamic> _allRates = const []; // [{symbol, stablecoin_margin_list:[...]}]
  int? _nextFundingTs; // OKX nextFundingTime (ms epoch), 权威结算时刻

  Timer? _pollTimer;
  Timer? _tickTimer;

  // ---------- 过滤状态 ----------
  static const _periods = ['15M', '1H', '4H', '1D', '7D', '30D'];
  static const _periodPoints = {
    '15M': 4, '1H': 8, '4H': 12, '1D': 18, '7D': 24, '30D': 30,
  };
  String _period = '4H';

  static const _ecoGroups = <String, List<String>>{
    '全部主流': ['BTC', 'ETH', 'SOL'],
    'BTC 系': ['BTC', 'BCH', 'LTC', 'BSV'],
    'ETH 生态': ['ETH', 'ARB', 'OP', 'LINK', 'UNI'],
    'Solana 系': ['SOL'],
    'DeFi 衍生品': ['UNI', 'AAVE', 'DYDX', 'CRV', 'LINK'],
  };
  String _eco = '全部主流';

  static const _heatExchanges = ['BINANCE', 'OKX', 'BYBIT'];

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 60), (_) => _load());
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    super.dispose();
  }

  Future<dynamic> _safe(Future<dynamic> f) async {
    try {
      return await f;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    final api = ApiClient.I;
    final r = await Future.wait([
      _safe(api.longShortRatio(symbol: 'BTC')),
      _safe(api.openInterest()),
      _safe(api.liquidity()),
      _safe(api.indicators()),
      _safe(api.sentiment()),
      _safe(api.fundingExchangeRates(symbol: 'BTC')), // 上游忽略 symbol, 返回全币种
      _safe(api.fundingRate('BTC-USDT-SWAP')), // nextFundingTime 权威口径
    ]);
    if (!mounted) return;
    setState(() {
      if (r[0] is Map) _ls = Map<String, dynamic>.from(r[0] as Map);
      if (r[1] is Map) _oi = Map<String, dynamic>.from(r[1] as Map);
      if (r[2] is Map) _liquidity = Map<String, dynamic>.from(r[2] as Map);
      if (r[3] is Map && (r[3] as Map)['indicators'] is List) {
        _indicators = (r[3] as Map)['indicators'] as List;
      }
      if (r[4] is Map) _sentiment = Fmt.toNum((r[4] as Map)['fear_greed']);
      if (r[5] is Map && (r[5] as Map)['data'] is List) {
        _allRates = (r[5] as Map)['data'] as List;
      }
      if (r[6] is Map && (r[6] as Map)['data'] is List) {
        final d = (r[6] as Map)['data'] as List;
        if (d.isNotEmpty) {
          final t = Fmt.toNum(d.first is Map ? d.first['nextFundingTime'] : null);
          if (t != null) _nextFundingTs = t.toInt();
        }
      }
      _fatal = _ls.isEmpty &&
          _oi.isEmpty &&
          _liquidity.isEmpty &&
          _sentiment == null &&
          _indicators.isEmpty &&
          _allRates.isEmpty;
      _loading = false;
    });
  }

  Future<void> _retry() async {
    setState(() {
      _loading = true;
      _fatal = false;
    });
    await _load();
  }

  // ---------- 多空比 ----------
  num? get _longPct => Fmt.toNum(_ls['long_pct']);
  num? get _shortPct => Fmt.toNum(_ls['short_pct']);

  String get _lsRatioText {
    final l = _longPct, s = _shortPct;
    if (l == null || s == null) return '-- : 1';
    return '${(l / math.max(s, 0.01)).toStringAsFixed(2)} : 1';
  }

  String get _lsBias {
    final l = _longPct, s = _shortPct;
    if (l == null || s == null) return '--';
    return l >= s ? '全网资金偏好偏多' : '全网资金偏好偏空';
  }

  // ---------- 恐慌贪婪 ----------
  String get _sentimentLabel {
    final v = _sentiment;
    if (v == null) return '--';
    if (v >= 75) return '极度贪婪 EXT GREED';
    if (v >= 50) return '贪婪 GREED';
    if (v >= 25) return '恐慌 FEAR';
    return '极度恐慌 EXT FEAR';
  }

  Color get _sentimentColor {
    final v = _sentiment;
    if (v == null) return Mc.muted;
    if (v >= 50) return Mc.bull;
    if (v >= 25) return Mc.amber;
    return Mc.bear;
  }

  // ---------- 稳定币 ----------
  num? get _stableTotal => Fmt.toNum(_liquidity['stable_total_usd']);
  num? get _stableChg => Fmt.toNum(_liquidity['stable_change_1d_pct']);
  num? get _stableDelta {
    final t = _stableTotal, c = _stableChg;
    if (t == null || c == null) return null;
    return t * c / 100;
  }

  Map<String, dynamic>? _stableOf(String sym) {
    final list = _liquidity['top_stables'];
    if (list is! List) return null;
    for (final s in list) {
      if (s is Map && s['name'] == sym) return Map<String, dynamic>.from(s);
    }
    return null;
  }

  num? _stableDeltaOf(String sym) {
    final s = _stableOf(sym);
    final cir = Fmt.toNum(s?['circulating_usd']);
    final chg = Fmt.toNum(s?['change_1d_pct']);
    if (cir == null || chg == null) return null;
    return cir * chg / 100;
  }

  // ---------- 资金费率热力 ----------
  num? _rateOf(String coin, String exchange) {
    for (final d in _allRates) {
      if (d is! Map || d['symbol'] != coin) continue;
      final list = d['stablecoin_margin_list'];
      if (list is! List) return null;
      for (final e in list) {
        if (e is Map &&
            (e['exchange'] ?? '').toString().toUpperCase() == exchange) {
          return Fmt.toNum(e['funding_rate'] ?? e['fundingRate'] ?? e['rate']);
        }
      }
      return null;
    }
    return null;
  }

  List<double> get _heatAllValues {
    final coins = _ecoGroups[_eco] ?? const <String>[];
    final out = <double>[];
    for (final c in coins) {
      for (final ex in _heatExchanges) {
        final v = _rateOf(c, ex);
        if (v != null) out.add(v.toDouble());
      }
    }
    return out;
  }

  double? get _avgAnnual {
    final vals = _heatAllValues;
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a + b) / vals.length * 3 * 365;
  }

  Color _heatBg(num? v) {
    if (v == null) return Colors.transparent;
    final a = math.min(v.abs() / 0.05, 1.0);
    final base = v >= 0 ? Mc.up : Mc.down;
    return base.withValues(alpha: 0.08 + a * 0.4);
  }

  static String _rateText(num? v) =>
      v == null ? '--' : '${v >= 0 ? '+' : ''}${v.toStringAsFixed(4)}%';

  static String _annualText(num? v) =>
      v == null ? '--' : '年化 ${(v * 3 * 365).toStringAsFixed(1)}%';

  // ---------- 结算倒计时 (优先 OKX nextFundingTime, 退化 UTC 00/08/16 本地推算) ----------
  String get _countdown {
    final now = DateTime.now();
    final DateTime next;
    final ts = _nextFundingTs;
    if (ts != null) {
      next = DateTime.fromMillisecondsSinceEpoch(ts);
    } else {
      final utc = now.toUtc();
      var h = (utc.hour ~/ 8 + 1) * 8;
      var day = utc.day;
      if (h >= 24) {
        h = 0;
        day += 1;
      }
      next = DateTime.utc(utc.year, utc.month, day, h).toLocal();
    }
    var d = next.difference(now);
    if (d.isNegative) d = Duration.zero;
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(d.inHours)}:${p(d.inMinutes % 60)}:${p(d.inSeconds % 60)}';
  }

  List<num> _sliced(dynamic series) {
    if (series is! List) return const [];
    final pts = series
        .map((v) => Fmt.toNum(v))
        .whereType<num>()
        .toList();
    final n = _periodPoints[_period] ?? 30;
    return pts.length > n ? pts.sublist(pts.length - n) : pts;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const McLoading(label: '多维数据加载中');
    if (_fatal) {
      return McError('多维数据暂时不可用，请稍后重试', onRetry: _retry);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const McSection('多维量化', tag: 'MULTI-DIM INTEL'),
        const SizedBox(height: 14),
        _toolbar(),
        const SizedBox(height: 16),
        _bentoGrid(),
        const SizedBox(height: 16),
        _statusBanner(),
      ]),
    );
  }

  // ---------- 工具栏 ----------
  Widget _toolbar() {
    return Container(
      padding: const EdgeInsets.only(bottom: 14),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Mc.hairline))),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _segGroup(
            _periods,
            _period,
            (v) => setState(() => _period = v),
            mono: true,
          ),
          ..._ecoGroups.keys.map((k) => _pill(
                k,
                k == _eco,
                () => setState(() => _eco = k),
              )),
        ],
      ),
    );
  }

  Widget _segGroup(List<String> items, String current,
      ValueChanged<String> onPick,
      {bool mono = false}) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Mc.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Mc.hairline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final it in items)
          GestureDetector(
            onTap: () => onPick(it),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: it == current ? Mc.cobalt : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(it,
                  style: mono
                      ? Mc.mono(11,
                          w: FontWeight.w600,
                          color: it == current ? Mc.ink : Mc.muted)
                      : Mc.body(11,
                          w: FontWeight.w600,
                          color: it == current ? Mc.ink : Mc.muted)),
            ),
          ),
      ]),
    );
  }

  Widget _pill(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Mc.card : Mc.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: active
                  ? Mc.cobalt.withValues(alpha: 0.5)
                  : Mc.hairline),
        ),
        child: Text(label,
            style: Mc.body(12,
                w: FontWeight.w500,
                color: active ? Mc.ink : Mc.muted)),
      ),
    );
  }

  // ---------- BENTO 网格 ----------
  Widget _bentoGrid() {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 1200 ? 3 : (c.maxWidth > 760 ? 2 : 1);
      final stretch = cols > 1;
      final cards = <Widget>[
        _lsCard(stretch: stretch),
        _sentimentCard(stretch: stretch),
        _oiCard(stretch: stretch),
        _stableCard(stretch: stretch),
        _heatCard(stretch: stretch),
        ..._indicators.map((d) => _indicatorCard(d, stretch: stretch)),
        if (_indicators.isEmpty) _indicatorFallback(),
      ];
      // 窄屏: 纵向堆叠 (无界高度, 卡片不加 Spacer)
      if (cols == 1) {
        return Column(children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            cards[i],
          ],
        ]);
      }
      // 宽屏: 每行一个 McRow, 同排卡片等高; 末行不足补空位保持列宽一致
      final span = 12 ~/ cols;
      return Column(children: [
        for (var i = 0; i < cards.length; i += cols) ...[
          if (i > 0) const SizedBox(height: 16),
          McRow(
            spans: List.filled(cols, span),
            children: [
              for (var j = i; j < math.min(i + cols, cards.length); j++)
                cards[j],
              for (var k = cards.length - i; k < cols; k++)
                const SizedBox.shrink(),
            ],
          ),
        ],
      ]);
    });
  }

  // ---------- CARD 1: 多空持仓比 ----------
  Widget _lsCard({bool stretch = false}) {
    final l = _longPct, s = _shortPct;
    final longLead = l != null && s != null && l >= s;
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const McSection('全网多空持仓比 (BTC 永续)', tag: 'DERIVATIVES INTEL'),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_lsRatioText,
                  style: Mc.mono(22, w: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(_lsBias, style: Mc.body(11, color: Mc.muted)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('多 ${l == null ? '--' : '${l.toStringAsFixed(1)}%'}',
                style: Mc.mono(12, w: FontWeight.w600, color: Mc.up)),
            Text('空 ${s == null ? '--' : '${s.toStringAsFixed(1)}%'}',
                style: Mc.mono(12, w: FontWeight.w600, color: Mc.down)),
          ]),
        ]),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 12,
            padding: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: Mc.surface,
              border: Border.all(color: Mc.hairline),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(children: [
              Expanded(
                  flex: ((l ?? 50) * 100).round(),
                  child: Container(color: Mc.up)),
              Container(width: 2, color: Mc.canvas),
              Expanded(
                  flex: ((s ?? 50) * 100).round(),
                  child: Container(color: Mc.down)),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Text('BULLISH BIAS (${l == null ? '--' : '${l.toStringAsFixed(1)}%'})',
              style: Mc.tag()),
          const Spacer(),
          Text('BEARISH BIAS (${s == null ? '--' : '${s.toStringAsFixed(1)}%'})',
              style: Mc.tag()),
        ]),
        const SizedBox(height: 14),
        if (stretch) const Spacer(),
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Mc.hairline))),
          child: Column(children: [
            Row(children: [
              const McTag('SOURCE'),
              const Spacer(),
              const McTag('RATIO'),
              const Spacer(),
              const McTag('PROPORTION'),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Text('Binance 全局账户',
                  style: Mc.body(11, w: FontWeight.w500)),
              const Spacer(),
              Text(_lsRatioText.replaceAll(' : 1', ''),
                  style: Mc.mono(11,
                      w: FontWeight.w600,
                      color: longLead ? Mc.up : Mc.down)),
              const Spacer(),
              SizedBox(
                width: 96,
                height: 6,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Row(children: [
                    Expanded(
                        flex: ((l ?? 50) * 100).round(),
                        child: Container(color: Mc.up)),
                    Expanded(
                        flex: ((s ?? 50) * 100).round(),
                        child: Container(color: Mc.down)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text('分平台明细需扩展数据源',
                style: Mc.body(10, color: Mc.muted.withValues(alpha: 0.7))),
          ]),
        ),
      ]),
    );
  }

  // ---------- CARD 2: 恐慌贪婪仪表 ----------
  Widget _sentimentCard({bool stretch = false}) {
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const McSection('全市场恐慌与贪婪指数', tag: 'SENTIMENT GAUGE'),
        const SizedBox(height: 14),
        Row(children: [
          Text(_sentiment?.toStringAsFixed(0) ?? '--',
              style: Mc.mono(28, w: FontWeight.w700)),
          const SizedBox(width: 10),
          if (_sentiment != null)
            McBadge(_sentimentLabel, color: _sentimentColor),
        ]),
        const SizedBox(height: 10),
        Center(
          child: SizedBox(
            width: 224,
            height: 120,
            child: CustomPaint(
              painter: _GaugePainter(value: (_sentiment ?? 50).toDouble()),
            ),
          ),
        ),
        Row(children: [
          Text('0 (极恐)', style: Mc.tag()),
          const Spacer(),
          Text('50 (中性)', style: Mc.tag(color: Mc.amber)),
          const Spacer(),
          Text('100 (极贪)', style: Mc.tag(color: Mc.bull)),
        ]),
        const SizedBox(height: 12),
        if (stretch) const Spacer(),
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Mc.hairline))),
          child: Row(children: [
            Text('数据源: alternative.me',
                style: Mc.mono(11, color: Mc.muted)),
            const Spacer(),
            Text('每日更新', style: Mc.mono(11, color: Mc.bull)),
          ]),
        ),
      ]),
    );
  }

  // ---------- CARD 3: 未平仓持仓量 ----------
  Widget _oiCard({bool stretch = false}) {
    final oi = Fmt.toNum(_oi['oi_usd']);
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const McSection('全网未平仓持仓量 (OI)', tag: 'GLOBAL AGGREGATION'),
        const SizedBox(height: 14),
        Text(Fmt.compact(oi, prefix: '\$'),
            style: Mc.mono(22, w: FontWeight.w700)),
        const SizedBox(height: 2),
        Text('BTC+ETH 永续名义额合计',
            style: Mc.mono(11, color: Mc.muted)),
        const SizedBox(height: 14),
        Container(
          height: 88,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Mc.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Mc.hairline),
          ),
          child: Text('24H 历史序列暂不可用 (需扩展数据源)',
              style: Mc.mono(11, color: Mc.muted)),
        ),
        const SizedBox(height: 14),
        if (stretch) const Spacer(),
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Mc.hairline))),
          child: Row(children: [
            Text('数据源: OKX 永续 oiUsd',
                style: Mc.mono(11, color: Mc.muted)),
            const Spacer(),
            Text('缓存 5M', style: Mc.mono(11, color: Mc.bull)),
          ]),
        ),
      ]),
    );
  }

  // ---------- CARD 4: 稳定币流向 ----------
  Widget _stableCard({bool stretch = false}) {
    final delta = _stableDelta;
    final chg = _stableChg;
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const McSection('稳定币流通量 24H 净变动', tag: 'LIQUIDITY DEPTH'),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                delta == null
                    ? '--'
                    : '${delta >= 0 ? '+' : ''}${Fmt.compact(delta, prefix: '\$')}',
                style: Mc.mono(22,
                    w: FontWeight.w700, color: Mc.upDown(delta)),
              ),
              const SizedBox(height: 2),
              Text(
                '总流通 ${Fmt.compact(_stableTotal, prefix: '\$')} · 24H ${Fmt.pct(chg)}',
                style: Mc.body(11, color: Mc.muted),
              ),
            ]),
          ),
          if (chg != null)
            McBadge(chg >= 0 ? '净增发驱动' : '净赎回收缩',
                color: Mc.upDown(chg)),
        ]),
        const SizedBox(height: 14),
        Container(
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Mc.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Mc.hairline),
          ),
          child: Text('7 日净流序列暂不可用 (仅提供总量)',
              style: Mc.mono(11, color: Mc.muted)),
        ),
        const SizedBox(height: 14),
        if (stretch) const Spacer(),
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Mc.hairline))),
          child: Column(children: [
            _stableRow('USDT', Mc.bull, 'Tether'),
            const SizedBox(height: 10),
            _stableRow('USDC', Mc.cobalt, 'Circle'),
          ]),
        ),
      ]),
    );
  }

  Widget _stableRow(String sym, Color dot, String issuer) {
    final s = _stableOf(sym);
    final delta = _stableDeltaOf(sym);
    return Row(children: [
      Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          '$sym ($issuer 流通 ${Fmt.compact(s?['circulating_usd'], prefix: '\$')})',
          style: Mc.mono(11, color: Mc.muted),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      Text(
        delta == null
            ? '--'
            : '${delta >= 0 ? '+' : ''}${Fmt.compact(delta, prefix: '\$')}',
        style: Mc.mono(11, w: FontWeight.w600, color: Mc.upDown(delta)),
      ),
    ]);
  }

  // ---------- CARD 5: 资金费率热力矩阵 ----------
  Widget _heatCard({bool stretch = false}) {
    final coins = _ecoGroups[_eco] ?? const ['BTC', 'ETH', 'SOL'];
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        McSection(
          '主流资产资金费率热力',
          tag: 'CROSS-PLATFORM',
          trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const McTag('结算倒计时'),
            Text(_countdown,
                style: Mc.mono(11, w: FontWeight.w600, color: Mc.amber)),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          const Expanded(child: McTag('ASSET')),
          for (final ex in _heatExchanges)
            Expanded(
                child: Text(ex,
                    textAlign: TextAlign.center, style: Mc.tag())),
        ]),
        const SizedBox(height: 6),
        for (var i = 0; i < coins.length; i++) ...[
          if (i > 0) const SizedBox(height: 4),
          _heatRow(coins[i]),
        ],
        const SizedBox(height: 14),
        if (stretch) const Spacer(),
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Mc.hairline))),
          child: Row(children: [
            Text(
              '样本平均年化: ${_avgAnnual == null ? '--' : '${_avgAnnual!.toStringAsFixed(1)}%'}',
              style: Mc.mono(11, color: Mc.muted),
            ),
            const Spacer(),
            Text('8H 结算周期',
                style: Mc.mono(11, w: FontWeight.w500, color: Mc.amber)),
          ]),
        ),
      ]),
    );
  }

  Widget _heatRow(String coin) {
    return Row(children: [
      Expanded(
          child: Text(coin,
              style: Mc.mono(12, w: FontWeight.w600))),
      for (final ex in _heatExchanges) ...[
        const SizedBox(width: 4),
        Expanded(child: _heatCell(_rateOf(coin, ex))),
      ],
    ]);
  }

  Widget _heatCell(num? v) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: _heatBg(v),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Mc.hairline),
      ),
      child: Column(children: [
        Text(_rateText(v),
            style: Mc.mono(11,
                w: FontWeight.w700,
                color: v == null ? Mc.muted : Mc.upDown(v))),
        Text(_annualText(v), style: Mc.mono(9, color: Mc.muted)),
      ]),
    );
  }

  // ---------- CARD 6+: 多维量化指数 ----------
  Widget _indicatorCard(dynamic raw, {bool stretch = false}) {
    final ind = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final chg = Fmt.toNum(ind['change_1d']);
    final val = Fmt.toNum(ind['value']);
    final pts = _sliced(ind['sparkline']);
    final n = _periodPoints[_period] ?? 30;
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        McSection(
          (ind['name'] ?? '--').toString(),
          tag: 'QUANT INDEX',
          trailing: Text(Fmt.pct(chg),
              style: Mc.mono(11, w: FontWeight.w600, color: Mc.upDown(chg))),
        ),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Text(
                val == null ? '--' : val.toStringAsFixed(2),
                style: Mc.mono(22, w: FontWeight.w700)),
          ),
          Text((ind['key'] ?? '').toString().toUpperCase(),
              style: Mc.tag()),
        ]),
        const SizedBox(height: 12),
        SizedBox(height: 80, child: _sparkline(pts, Mc.upDown(chg))),
        const SizedBox(height: 4),
        Row(children: [
          Text('T-$n ($_period)', style: Mc.tag()),
          const Spacer(),
          Text('当前 (${val == null ? '--' : val.toStringAsFixed(2)})',
              style: Mc.tag(color: Mc.cobaltSoft)),
        ]),
        const SizedBox(height: 12),
        if (stretch) const Spacer(),
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Mc.hairline))),
          child: Row(children: [
            Text('1D 变化: ${Fmt.pct(chg)}',
                style: Mc.mono(11, color: Mc.muted)),
            const Spacer(),
            Text('近 $n 期走势', style: Mc.mono(11, color: Mc.muted)),
          ]),
        ),
      ]),
    );
  }

  Widget _indicatorFallback() {
    return const McCard(
      child: SizedBox(
        height: 160,
        child: McEmpty('多维指数暂不可用 (数据源未配置)'),
      ),
    );
  }

  Widget _sparkline(List<num> pts, Color color) {
    if (pts.length < 2) {
      return Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Mc.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Mc.hairline),
        ),
        child: Text('历史序列不足', style: Mc.mono(11, color: Mc.muted)),
      );
    }
    final spots = <FlSpot>[
      for (var i = 0; i < pts.length; i++)
        FlSpot(i.toDouble(), pts[i].toDouble()),
    ];
    final mn = pts.reduce(math.min).toDouble();
    final mx = pts.reduce(math.max).toDouble();
    final pad = (mx - mn) * 0.08 + 1e-9;
    return LineChart(LineChartData(
      minY: mn - pad,
      maxY: mx + pad,
      gridData: const FlGridData(show: false),
      titlesData: const FlTitlesData(show: false),
      borderData: FlBorderData(show: false),
      lineTouchData: const LineTouchData(enabled: false),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          preventCurveOverShooting: true,
          color: color,
          barWidth: 1.5,
          dotData: const FlDotData(show: false),
          belowBarData:
              BarAreaData(show: true, color: color.withValues(alpha: 0.12)),
        ),
      ],
    ));
  }

  // ---------- 底部状态横幅 ----------
  Widget _statusBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Mc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Mc.hairline),
      ),
      child: Wrap(spacing: 14, runSpacing: 8, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                  color: Mc.bull, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text('行情聚合源已连接', style: Mc.mono(11, color: Mc.bull)),
        ]),
        Text('OKX / Binance / DefiLlama / alternative.me',
            style: Mc.mono(11, color: Mc.muted)),
        Text('轮询周期: 60S', style: Mc.mono(11, color: Mc.muted)),
        Text('BTC 永续结算: $_countdown',
            style: Mc.mono(11, color: Mc.ink)),
        McBadge('SYNCED', color: Mc.cobaltSoft),
      ]),
    );
  }
}

/// 恐慌贪婪仪表盘: 渐变弧线 + 指针 (值 50 指向正上方, 每点 1.8 度)。
class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.value});
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final center = Offset(size.width / 2, size.height - 16);
    final radius = math.min(size.width / 2 - 16, size.height - 28);
    final rect = Rect.fromCircle(center: center, radius: radius);

    // 轨道
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke + 2
      ..strokeCap = StrokeCap.round
      ..color = Mc.cardHigh;
    canvas.drawArc(rect, math.pi, math.pi, false, track);

    // 渐变弧 (恐慌 -> 中性 -> 贪婪 -> 极度贪婪)
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [Mc.bear, Mc.amber, Mc.bull, Mc.cobalt],
        stops: [0.0, 0.35, 0.7, 1.0],
      ).createShader(rect);
    canvas.drawArc(rect, math.pi, math.pi, false, arc);

    // 刻度
    final tick = Paint()
      ..color = Mc.hairline
      ..strokeWidth = 1.5;
    for (final f in [0.0, 0.25, 0.5, 0.75, 1.0]) {
      final a = math.pi + f * math.pi;
      final p1 = center + Offset(math.cos(a), math.sin(a)) * radius;
      final p2 =
          center + Offset(math.cos(a), math.sin(a)) * (radius + 9);
      canvas.drawLine(p1, p2, tick);
    }

    // 指针
    final v = value.clamp(0, 100);
    final angle = math.pi + (v / 100) * math.pi;
    final needle = Paint()
      ..color = Mc.ink
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final tip =
        center + Offset(math.cos(angle), math.sin(angle)) * (radius - 18);
    canvas.drawLine(center, tip, needle);
    canvas.drawCircle(center, 5, Paint()..color = Mc.cobalt);
    canvas.drawCircle(
        center,
        5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Mc.ink);
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value;
}

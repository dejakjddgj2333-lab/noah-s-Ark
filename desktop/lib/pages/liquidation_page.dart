import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/kit.dart';

/// 爆仓监控页: 24H 爆仓 KPI / 爆仓分布柱状图 / 多空比例环图 / 实时爆仓明细。
/// 数据组织参考 web-terminal/src/views/Liquidation.vue。
class LiquidationPage extends StatefulWidget {
  const LiquidationPage({super.key});

  @override
  State<LiquidationPage> createState() => _LiquidationPageState();
}

class _LiquidationPageState extends State<LiquidationPage> {
  bool _loading = true;
  bool _fatal = false;

  List<dynamic> _events = const [];
  List<dynamic> _coins = const [];

  String _gran = '24H'; // 1H | 4H | 24H
  String _filter = 'all'; // all | BTC | ETH | SOL | other

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
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
      _safe(api.liqRecent(limit: 50)),
      _safe(api.liqCoinList()),
    ]);
    if (!mounted) return;
    setState(() {
      if (r[0] is Map && r[0]['data'] is List) _events = r[0]['data'] as List;
      if (r[1] is Map && r[1]['coins'] is List) _coins = r[1]['coins'] as List;
      _fatal = _events.isEmpty && _coins.isEmpty;
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

  // ---------- 聚合 ----------
  static bool _isLong(dynamic e) => e['side'] == 'long' || e['side'] == 'buy';

  static String _coinOf(dynamic symbol) =>
      (symbol ?? '').toString().split('-').first;

  num get _total24h => _coins.fold<num>(
      0,
      (s, c) =>
          s + (Fmt.toNum(c['liquidation_usd_24h'] ?? c['liqUsd24h']) ?? 0));

  num get _longTotal => _coins.fold<num>(
      0,
      (s, c) =>
          s +
          (Fmt.toNum(c['long_liquidation_usd_24h'] ?? c['longLiqUsd24h']) ??
              0));

  num get _shortTotal => _coins.fold<num>(
      0,
      (s, c) =>
          s +
          (Fmt.toNum(c['short_liquidation_usd_24h'] ?? c['shortLiqUsd24h']) ??
              0));

  num? get _longPct =>
      _total24h > 0 ? _longTotal / _total24h * 100 : null;

  num? get _shortPct =>
      _total24h > 0 ? _shortTotal / _total24h * 100 : null;

  String? get _ratio => (_longTotal > 0 && _shortTotal > 0)
      ? (_longTotal / _shortTotal).toStringAsFixed(2)
      : null;

  dynamic get _maxEvent {
    dynamic best;
    for (final e in _events) {
      if (best == null ||
          (Fmt.toNum(e['notional_usd']) ?? 0) >
              (Fmt.toNum(best['notional_usd']) ?? 0)) {
        best = e;
      }
    }
    return best;
  }

  int get _longCount => _events.where(_isLong).length;

  int get _shortCount => _events.length - _longCount;

  List<dynamic> get _filteredEvents {
    if (_filter == 'all') return _events;
    if (_filter == 'other') {
      return _events
          .where((e) => !['BTC', 'ETH', 'SOL'].contains(_coinOf(e['symbol'])))
          .toList();
    }
    return _events.where((e) => _coinOf(e['symbol']) == _filter).toList();
  }

  // ---------- 分布分桶 ----------
  ({List<String> labels, List<double> longs, List<double> shorts}) _buckets() {
    final cfg = switch (_gran) {
      '1H' => (span: 3600e3, bucket: 5 * 60e3),
      '4H' => (span: 4 * 3600e3, bucket: 30 * 60e3),
      _ => (span: 24 * 3600e3, bucket: 3600e3),
    };
    final newest = _events.fold<num>(
        0, (m, e) => math.max(m, Fmt.toNum(e['ts']) ?? 0));
    final now = DateTime.now().millisecondsSinceEpoch.toDouble();
    final end = (newest > 0 && now - newest > cfg.span) ? newest : now;
    final start = end - cfg.span;
    final n = (cfg.span / cfg.bucket).ceil();
    final longs = List<double>.filled(n, 0);
    final shorts = List<double>.filled(n, 0);
    String p(int x) => x.toString().padLeft(2, '0');
    final labels = [
      for (var i = 0; i < n; i++)
        () {
          final t =
              DateTime.fromMillisecondsSinceEpoch((start + i * cfg.bucket).round());
          return '${p(t.hour)}:${p(t.minute)}';
        }(),
    ];
    for (final e in _events) {
      final t = Fmt.toNum(e['ts']);
      if (t == null || t < start) continue;
      final i = math.min(n - 1, ((t - start) / cfg.bucket).floor());
      final v = (Fmt.toNum(e['notional_usd']) ?? 0).toDouble();
      if (_isLong(e)) {
        longs[i] += v;
      } else {
        shorts[i] += v;
      }
    }
    return (labels: labels, longs: longs, shorts: shorts);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const McLoading(label: '爆仓数据加载中');
    if (_fatal) return McError('爆仓数据暂时不可用，请稍后重试', onRetry: _retry);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const McSection('爆仓监控', tag: 'LIQUIDATION MONITOR'),
        const SizedBox(height: 10),
        _contextBar(),
        const SizedBox(height: 16),
        _kpiGrid(),
        const SizedBox(height: 16),
        _chartRow(),
        const SizedBox(height: 16),
        _feedCard(),
      ]),
    );
  }

  // ---------- 上下文条 (对齐 web Liquidation 子标题) ----------
  Widget _contextBar() {
    return Container(
      padding: const EdgeInsets.only(bottom: 12),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Mc.hairline))),
      child: Row(children: [
        Text('市场监控范围:', style: Mc.tag(color: Mc.muted)),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
              color: Mc.surface,
              border: Border.all(color: Mc.hairline),
              borderRadius: BorderRadius.circular(4)),
          child: Text('全网永续 (USDT/COIN-M)', style: Mc.mono(11)),
        ),
        Text('  ·  ', style: Mc.mono(11, color: Mc.muted)),
        Flexible(
          child: Text('币安 · OKX · Bybit · Coinbase · Deribit',
              overflow: TextOverflow.ellipsis,
              style: Mc.mono(11, color: Mc.muted)),
        ),
        const Spacer(),
        Text('统计周期: ', style: Mc.tag(color: Mc.muted)),
        Text('过去 24 小时', style: Mc.mono(11)),
        const SizedBox(width: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
              color: Mc.bull.withValues(alpha: 0.10),
              border: Border.all(color: Mc.bull.withValues(alpha: 0.25)),
              borderRadius: BorderRadius.circular(4)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                    color: Mc.bull, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text('轮询活跃 POLLING', style: Mc.mono(10, color: Mc.bull)),
          ]),
        ),
      ]),
    );
  }

  // ---------- ROW 1: KPI ----------
  Widget _kpiGrid() {
    final maxE = _maxEvent;
    final cards = [
      _KpiCard(
        label: '24H 爆仓总额 TOTAL',
        value: Fmt.compact(_total24h, prefix: '\$'),
        footerLeft: '监控币种',
        footerRight: '${_coins.length} 个',
      ),
      _KpiCard(
        label: '多单爆仓 LONG',
        dot: Mc.up,
        badge: _longPct == null
            ? null
            : ('${_longPct!.toStringAsFixed(2)}%', Mc.up),
        value: Fmt.compact(_longTotal, prefix: '\$'),
        valueColor: Mc.up,
        footerLeft: '近期强平笔数',
        footerRight: '$_longCount 笔 (多头承压)',
      ),
      _KpiCard(
        label: '空单爆仓 SHORT',
        dot: Mc.down,
        badge: _shortPct == null
            ? null
            : ('${_shortPct!.toStringAsFixed(2)}%', Mc.down),
        value: Fmt.compact(_shortTotal, prefix: '\$'),
        valueColor: Mc.down,
        footerLeft: '近期强平笔数',
        footerRight: '$_shortCount 笔 (空头逼仓)',
      ),
      _KpiCard(
        label: '最大单笔爆仓 LARGEST',
        value: Fmt.compact(maxE?['notional_usd'], prefix: '\$'),
        footerLeft: maxE == null
            ? '--'
            : '${maxE['symbol'] ?? '--'} · ${maxE['exchange'] ?? '--'}',
        footerRight: maxE == null ? '--' : Fmt.hm(maxE['ts']),
      ),
    ];
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth > 1100) {
        return McRow(spans: const [3, 3, 3, 3], children: cards);
      }
      if (c.maxWidth > 620) {
        return Column(children: [
          McRow(spans: const [6, 6], children: [cards[0], cards[1]]),
          const SizedBox(height: 16),
          McRow(spans: const [6, 6], children: [cards[2], cards[3]]),
        ]);
      }
      return Column(children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          cards[i],
        ],
      ]);
    });
  }

  // ---------- ROW 2: 分布图 + 环图 ----------
  Widget _chartRow() {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > 980;
      final dist = _distCard();
      final donut = _donutCard();
      if (!wide) {
        return Column(children: [dist, const SizedBox(height: 16), donut]);
      }
      return McRow(spans: const [8, 4], children: [dist, donut]);
    });
  }

  Widget _distCard() {
    final b = _buckets();
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
            child: McSection('爆仓分布', tag: 'LIQUIDATION TIMELINE'),
          ),
          _Seg(
            items: const [('1H', '1H'), ('4H', '4H'), ('24H', '24H')],
            selected: _gran,
            onChanged: (v) => setState(() => _gran = v),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _LegendDot(Mc.up),
          const SizedBox(width: 4),
          Text('多单强平 ${Fmt.compact(_longTotal, prefix: '\$')}',
              style: Mc.mono(10, color: Mc.up)),
          const SizedBox(width: 12),
          _LegendDot(Mc.down),
          const SizedBox(width: 4),
          Text('空单强平 ${Fmt.compact(_shortTotal, prefix: '\$')}',
              style: Mc.mono(10, color: Mc.down)),
        ]),
        const SizedBox(height: 12),
        SizedBox(height: 220, child: _distChart(b)),
      ]),
    );
  }

  Widget _distChart(
      ({List<String> labels, List<double> longs, List<double> shorts}) b) {
    if (b.labels.isEmpty) return const McEmpty('暂无分布数据');
    var maxSum = 0.0;
    for (var i = 0; i < b.longs.length; i++) {
      maxSum = math.max(maxSum, b.longs[i] + b.shorts[i]);
    }
    if (maxSum <= 0) return const McEmpty('当前窗口暂无爆仓');
    final barW = switch (_gran) {
      '1H' => 14.0,
      '4H' => 10.0,
      _ => 7.0,
    };
    final labelEvery = (b.labels.length / 6).ceil();
    return BarChart(BarChartData(
      maxY: maxSum * 1.15,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (v) => FlLine(
            color: Mc.hairline.withValues(alpha: 0.3),
            strokeWidth: 0.5,
            dashArray: [4, 4]),
      ),
      borderData: FlBorderData(show: false),
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => Mc.card,
          getTooltipItem: (group, gi, rod, ri) {
            final i = group.x;
            if (i < 0 || i >= b.labels.length) return null;
            return BarTooltipItem(
              '${b.labels[i]}\n多单 ${Fmt.compact(b.longs[i], prefix: '\$')}\n空单 ${Fmt.compact(b.shorts[i], prefix: '\$')}',
              Mc.mono(10),
            );
          },
        ),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            getTitlesWidget: (v, meta) {
              final i = v.toInt();
              if (i < 0 || i >= b.labels.length || i % labelEvery != 0) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(b.labels[i], style: Mc.mono(9, color: Mc.muted)),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 44,
            getTitlesWidget: (v, meta) => Text(Fmt.compact(v),
                style: Mc.mono(9, color: Mc.muted)),
          ),
        ),
      ),
      barGroups: [
        for (var i = 0; i < b.longs.length; i++)
          BarChartGroupData(x: i, barRods: [
            BarChartRodData(
              toY: b.longs[i] + b.shorts[i],
              width: barW,
              color: Mc.up,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(2)),
              rodStackItems: [
                if (b.longs[i] > 0)
                  BarChartRodStackItem(0, b.longs[i], Mc.up),
                if (b.shorts[i] > 0)
                  BarChartRodStackItem(
                      b.longs[i], b.longs[i] + b.shorts[i], Mc.down),
              ],
            ),
          ]),
      ],
    ));
  }

  Widget _donutCard() {
    final lp = _longPct, sp = _shortPct;
    final longLead = (lp ?? 0) >= 50;
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const McSection('多空爆仓比例', tag: 'RATIO METER'),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: (_longTotal <= 0 && _shortTotal <= 0)
              ? const McEmpty('暂无数据')
              : Stack(alignment: Alignment.center, children: [
                  PieChart(PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 52,
                    sections: [
                      if (_longTotal > 0)
                        PieChartSectionData(
                            value: _longTotal.toDouble(),
                            color: Mc.up,
                            radius: 14,
                            showTitle: false),
                      if (_shortTotal > 0)
                        PieChartSectionData(
                            value: _shortTotal.toDouble(),
                            color: Mc.down,
                            radius: 14,
                            showTitle: false),
                    ],
                  )),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('多空对比', style: Mc.tag()),
                    Text(_ratio == null ? '--' : '$_ratio : 1',
                        style: Mc.mono(18, w: FontWeight.w600)),
                    const SizedBox(height: 4),
                    McBadge(longLead ? '多头承压略高' : '空头承压略高',
                        color: longLead ? Mc.up : Mc.down),
                  ]),
                ]),
        ),
        const SizedBox(height: 12),
        _donutLegendRow('多单强平', Mc.up, lp, _longCount),
        const SizedBox(height: 8),
        _donutLegendRow('空单强平', Mc.down, sp, _shortCount),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Mc.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Mc.hairline),
          ),
          child: Row(children: [
            Text('市场爆仓偏向:', style: Mc.mono(10, color: Mc.muted)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                lp == null
                    ? '--'
                    : (longLead ? '多头强平承压 · 注意回踩风险' : '空头逼仓 · 注意反弹风险'),
                textAlign: TextAlign.right,
                style: Mc.mono(10, w: FontWeight.w600),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _donutLegendRow(String label, Color color, num? pct, int count) {
    return Row(children: [
      _LegendDot(color),
      const SizedBox(width: 8),
      Text(label, style: Mc.body(12, color: Mc.muted)),
      const Spacer(),
      Text(pct == null ? '--' : '${pct.toStringAsFixed(1)}%',
          style: Mc.mono(12, w: FontWeight.w600)),
      const SizedBox(width: 8),
      Text('($count 笔)', style: Mc.mono(11, color: Mc.muted)),
    ]);
  }

  // ---------- ROW 3: 实时明细 ----------
  Widget _feedCard() {
    final rows = _filteredEvents;
    return McCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const McSection('实时爆仓明细', tag: 'LIVE LIQUIDATION FEED'),
              _Seg(
                items: const [
                  ('all', '全部'),
                  ('BTC', 'BTC'),
                  ('ETH', 'ETH'),
                  ('SOL', 'SOL'),
                  ('other', '其他'),
                ],
                selected: _filter,
                onChanged: (v) => setState(() => _filter = v),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Mc.hairline),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Row(children: [
            Expanded(flex: 2, child: McTh('时间')),
            Expanded(flex: 2, child: McTh('币种')),
            Expanded(flex: 4, child: McTh('标的与平台')),
            Expanded(flex: 3, child: McTh('方向', align: TextAlign.center)),
            Expanded(flex: 3, child: McTh('触发价格', align: TextAlign.right)),
            Expanded(flex: 3, child: McTh('强平数量', align: TextAlign.right)),
            Expanded(flex: 3, child: McTh('名义价值', align: TextAlign.right)),
            Expanded(flex: 2, child: McTh('类型', align: TextAlign.center)),
          ]),
        ),
        const Divider(height: 1, color: Mc.hairline),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: McEmpty('暂无爆仓事件'),
          )
        else
          for (var i = 0; i < rows.length; i++) ...[
            _feedRow(rows[i]),
            if (i != rows.length - 1)
              const Divider(height: 1, color: Mc.hairline),
          ],
        const Divider(height: 1, color: Mc.hairline),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(children: [
            Text('展示 ${rows.length} 条 / 缓存池 ${_events.length} 条',
                style: Mc.mono(10, color: Mc.muted)),
            const Spacer(),
            Text('自动刷新: 10S', style: Mc.mono(10, color: Mc.muted)),
          ]),
        ),
      ]),
    );
  }

  Widget _feedRow(dynamic e) {
    final isLong = _isLong(e);
    final coin = _coinOf(e['symbol']);
    return _HoverRow(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      children: [
        Expanded(
            flex: 2,
            child:
                Text(Fmt.hm(e['ts']), style: Mc.mono(12, color: Mc.muted))),
        Expanded(
            flex: 2,
            child: Text(coin, style: Mc.mono(12, w: FontWeight.w600))),
        Expanded(
          flex: 4,
          child: Row(children: [
            Flexible(
              child: Text((e['symbol'] ?? '--').toString(),
                  overflow: TextOverflow.ellipsis, style: Mc.mono(12)),
            ),
            const SizedBox(width: 6),
            McBadge('${e['exchange'] ?? '--'} 永续', color: Mc.muted),
          ]),
        ),
        Expanded(
          flex: 3,
          child: Center(
            child: McBadge(isLong ? '多单强平 LONG' : '空单强平 SHORT',
                color: isLong ? Mc.up : Mc.down),
          ),
        ),
        Expanded(
            flex: 3,
            child: Text('\$${Fmt.num_(e['price'])}',
                textAlign: TextAlign.right, style: Mc.mono(12))),
        Expanded(
            flex: 3,
            child: Text('${Fmt.compact(e['qty'])} $coin',
                textAlign: TextAlign.right,
                style: Mc.mono(12, color: Mc.muted))),
        Expanded(
            flex: 3,
            child: Text(Fmt.compact(e['notional_usd'], prefix: '\$'),
                textAlign: TextAlign.right,
                style: Mc.mono(12,
                    w: FontWeight.w600,
                    color: isLong ? Mc.up : Mc.down))),
        Expanded(
            flex: 2,
            child: Text('强平平仓',
                textAlign: TextAlign.center,
                style: Mc.mono(11, color: Mc.muted))),
      ],
    );
  }
}

// ---------- 私有组件 ----------

/// KPI 卡: 标签 + 大数字 + hairline 分隔的页脚。
class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.footerLeft,
    required this.footerRight,
    this.valueColor,
    this.dot,
    this.badge,
  });
  final String label;
  final String value;
  final String footerLeft;
  final String footerRight;
  final Color? valueColor;
  final Color? dot;
  final (String, Color)? badge;

  @override
  Widget build(BuildContext context) => McCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (dot != null) ...[
              Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 6),
            ],
            Expanded(child: McTag(label)),
            if (badge != null) McBadge(badge!.$1, color: badge!.$2),
          ]),
          const SizedBox(height: 12),
          Text(value,
              style:
                  Mc.mono(22, w: FontWeight.w600, color: valueColor ?? Mc.ink)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Mc.hairline))),
            child: Row(children: [
              Flexible(
                child: Text(footerLeft,
                    overflow: TextOverflow.ellipsis,
                    style: Mc.mono(10, color: Mc.muted)),
              ),
              const Spacer(),
              Flexible(
                child: Text(footerRight,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: Mc.mono(10, w: FontWeight.w600)),
              ),
            ]),
          ),
        ]),
      );
}

/// 分段选择器: surface 底 + hairline 边, 选中项 cardHigh。
class _Seg extends StatelessWidget {
  const _Seg(
      {required this.items, required this.selected, required this.onChanged});
  final List<(String, String)> items; // (key, label)
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Mc.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Mc.hairline),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final it in items)
            _SegItem(
              label: it.$2,
              selected: it.$1 == selected,
              onTap: () => onChanged(it.$1),
            ),
        ]),
      );
}

class _SegItem extends StatefulWidget {
  const _SegItem(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SegItem> createState() => _SegItemState();
}

class _SegItemState extends State<_SegItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: active
                ? Mc.cardHigh
                : (_hover
                    ? Mc.cardHigh.withValues(alpha: 0.5)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(widget.label,
              style: Mc.mono(11,
                  w: active ? FontWeight.w600 : FontWeight.w500,
                  color: active ? Mc.ink : Mc.muted)),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot(this.color);
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(2)));
}

/// 行悬停高亮 (Mc.cardHigh)，无斑马纹。
class _HoverRow extends StatefulWidget {
  const _HoverRow({required this.children, this.padding});
  final List<Widget> children;
  final EdgeInsets? padding;

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _hover ? Mc.cardHigh : Colors.transparent,
        padding: widget.padding ??
            const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(children: widget.children),
      ),
    );
  }
}

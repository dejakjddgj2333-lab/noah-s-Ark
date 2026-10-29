import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/kit.dart';

/// 巨鲸监控页: 筛选栏 / 大额成交流水表 / 币种分布环图 / 买卖净额与时序。
/// 数据组织参考 web-terminal/src/views/Whale.vue。
/// 字段坑: whale-alerts 金额字段是 positionSize 不是 usd。
class WhalePage extends StatefulWidget {
  const WhalePage({super.key});

  @override
  State<WhalePage> createState() => _WhalePageState();
}

class _WhalePageState extends State<WhalePage> {
  bool _loading = true;
  bool _fatal = false;

  List<dynamic> _alerts = const [];
  Map<String, dynamic> _status = const {};

  String _side = 'all'; // all | Buy | Sell
  double _threshold = 0;

  Timer? _timer;

  static const _distColors = [Mc.cobalt, Mc.cobaltSoft, Mc.bull, Mc.muted];

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
      _safe(api.whaleAlerts()),
      _safe(api.whaleStatus()),
    ]);
    if (!mounted) return;
    setState(() {
      if (r[0] is Map && r[0]['alerts'] is List) {
        _alerts = r[0]['alerts'] as List;
      }
      if (r[1] is Map) _status = Map<String, dynamic>.from(r[1] as Map);
      _fatal = _alerts.isEmpty && _status.isEmpty;
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
  static String _coinOf(dynamic symbol) =>
      (symbol ?? '').toString().split('-').first;

  static num _sizeOf(dynamic a) => Fmt.toNum(a['positionSize']) ?? 0;

  List<dynamic> get _filtered => _alerts
      .where((a) =>
          (_side == 'all' || a['side'] == _side) &&
          _sizeOf(a) >= _threshold)
      .toList();

  num get _totalUsd =>
      _alerts.fold<num>(0, (s, a) => s + _sizeOf(a));

  num get _buyUsd => _alerts
      .where((a) => a['side'] == 'Buy')
      .fold<num>(0, (s, a) => s + _sizeOf(a));

  num get _sellUsd => _alerts
      .where((a) => a['side'] == 'Sell')
      .fold<num>(0, (s, a) => s + _sizeOf(a));

  num get _netUsd => _buyUsd - _sellUsd;

  /// 币种分布 Top3 + 其他
  List<({String symbol, num value, Color color})> get _coinDist {
    final map = <String, num>{};
    for (final a in _alerts) {
      final c = _coinOf(a['symbol']);
      map[c] = (map[c] ?? 0) + _sizeOf(a);
    }
    final sorted = map.entries.toList()
      ..sort((x, y) => y.value.compareTo(x.value));
    final out = <({String symbol, num value, Color color})>[];
    for (var i = 0; i < math.min(3, sorted.length); i++) {
      out.add((
        symbol: sorted[i].key,
        value: sorted[i].value,
        color: _distColors[i],
      ));
    }
    final rest =
        sorted.skip(3).fold<num>(0, (s, e) => s + e.value);
    if (rest > 0) {
      out.add((symbol: '其他', value: rest, color: _distColors[3]));
    }
    return out;
  }

  /// 24H 方向时序: 6 个 4H 桶
  List<_TrendBar> get _trendBars {
    final now = DateTime.now().millisecondsSinceEpoch.toDouble();
    final start = now - 24 * 3600e3;
    final buckets = List.generate(6, (_) => (buy: 0.0, sell: 0.0));
    for (final a in _alerts) {
      final t = Fmt.toNum(a['time']);
      if (t == null || t < start) continue;
      final i = math.min(5, ((t - start) / (4 * 3600e3)).floor());
      final v = _sizeOf(a).toDouble();
      if (a['side'] == 'Buy') {
        buckets[i] = (buy: buckets[i].buy + v, sell: buckets[i].sell);
      } else {
        buckets[i] = (buy: buckets[i].buy, sell: buckets[i].sell + v);
      }
    }
    final maxV = buckets.fold<double>(
        1, (m, b) => math.max(m, math.max(b.buy, b.sell)));
    String p(int x) => x.toString().padLeft(2, '0');
    return [
      for (var i = 0; i < 6; i++)
        _TrendBar(
          label: i == 5
              ? 'Now'
              : '${p(DateTime.fromMillisecondsSinceEpoch((start + i * 4 * 3600e3).round()).hour)}h',
          frac: math.max(0.06, math.max(buckets[i].buy, buckets[i].sell) / maxV),
          isBuy: buckets[i].buy >= buckets[i].sell,
          isLast: i == 5,
        ),
    ];
  }

  Color _sourceColor(dynamic a) {
    final s = (a['source'] ?? '').toString().toLowerCase();
    if (s.contains('hyperliquid')) return Mc.cobaltSoft;
    if (s.contains('binance')) return Mc.amber;
    return Mc.muted;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const McLoading(label: '巨鲸数据加载中');
    if (_fatal) return McError('巨鲸数据暂时不可用，请稍后重试', onRetry: _retry);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const McSection('巨鲸监控', tag: 'WHALE WATCH'),
        const SizedBox(height: 16),
        _filterBar(),
        const SizedBox(height: 16),
        _mainRow(),
      ]),
    );
  }

  // ---------- 筛选栏 ----------
  Widget _filterBar() {
    final connected = _status['hl_connected'] == true;
    final age = Fmt.toNum(_status['last_msg_age_s']);
    return McCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _Seg(
            items: const [('all', '全部'), ('Buy', '买入'), ('Sell', '卖出')],
            selected: _side,
            onChanged: (v) => setState(() => _side = v),
          ),
          _Seg(
            items: const [
              ('0', '全部'),
              ('1000000', '≥\$1M'),
              ('5000000', '≥\$5M'),
              ('10000000', '≥\$10M'),
            ],
            selected: _threshold.toStringAsFixed(0),
            onChanged: (v) => setState(() => _threshold = double.parse(v)),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text('监控大额成交: ', style: Mc.mono(11, color: Mc.muted)),
            Text('${_alerts.length} 笔', style: Mc.mono(11, w: FontWeight.w600)),
          ]),
          Container(width: 1, height: 16, color: Mc.hairline),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                    color: connected ? Mc.bull : Mc.amber,
                    shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text('数据流: ', style: Mc.mono(11, color: Mc.muted)),
            Text(
              '${connected ? '已连接' : '重连中'}${age == null ? '' : ' · ${age.toStringAsFixed(0)}s 前'}',
              style: Mc.mono(11,
                  w: FontWeight.w600, color: connected ? Mc.bull : Mc.amber),
            ),
          ]),
        ],
      ),
    );
  }

  // ---------- 主区域 ----------
  Widget _mainRow() {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > 980;
      final table = _tableCard();
      final side = Column(children: [
        _distCard(),
        const SizedBox(height: 16),
        _netCard(),
      ]);
      if (!wide) {
        return Column(children: [table, const SizedBox(height: 16), side]);
      }
      return McRow(spans: const [8, 4], children: [table, side]);
    });
  }

  Widget _tableCard() {
    final rows = _filtered;
    return McCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: McSection('大额成交流水', tag: 'LARGE TRANSFERS'),
        ),
        const Divider(height: 1, color: Mc.hairline),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Row(children: [
            Expanded(flex: 2, child: McTh('时间')),
            Expanded(flex: 3, child: McTh('来源')),
            Expanded(flex: 4, child: McTh('账户方')),
            Expanded(flex: 2, child: McTh('币种')),
            Expanded(flex: 3, child: McTh('名义价值', align: TextAlign.right)),
            Expanded(flex: 3, child: McTh('资金动向', align: TextAlign.center)),
          ]),
        ),
        const Divider(height: 1, color: Mc.hairline),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: McEmpty('暂无大额成交'),
          )
        else
          for (var i = 0; i < rows.length; i++) ...[
            _tableRow(rows[i]),
            if (i != rows.length - 1)
              const Divider(height: 1, color: Mc.hairline),
          ],
        const Divider(height: 1, color: Mc.hairline),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(children: [
            Text('显示 ${rows.length} / 共 ${_alerts.length} 条异动',
                style: Mc.mono(10, color: Mc.muted)),
            const Spacer(),
            Text('HYPERLIQUID + BINANCE 双源',
                style: Mc.mono(10, color: Mc.muted)),
          ]),
        ),
      ]),
    );
  }

  Widget _tableRow(dynamic a) {
    final isBuy = a['side'] == 'Buy';
    return _HoverRow(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      children: [
        Expanded(
            flex: 2,
            child:
                Text(Fmt.hm(a['time']), style: Mc.mono(11, color: Mc.muted))),
        Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: McBadge((a['source'] ?? '链上').toString(),
                  color: _sourceColor(a)),
            )),
        Expanded(
            flex: 4,
            child: Text((a['user'] ?? '匿名大户').toString(),
                overflow: TextOverflow.ellipsis, style: Mc.body(12))),
        Expanded(
            flex: 2,
            child: Text(_coinOf(a['symbol']),
                style: Mc.mono(12, w: FontWeight.w600))),
        Expanded(
            flex: 3,
            child: Text(Fmt.compact(a['positionSize'], prefix: '\$'),
                textAlign: TextAlign.right,
                style: Mc.mono(12, w: FontWeight.w600))),
        Expanded(
            flex: 3,
            child: Center(
              child: McBadge(isBuy ? '大额买入 BUY' : '大额卖出 SELL',
                  color: isBuy ? Mc.up : Mc.down),
            )),
      ],
    );
  }

  // ---------- 右列 1: 币种分布 ----------
  Widget _distCard() {
    final dist = _coinDist;
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const McSection('大额成交币种分布', tag: 'COIN DISTRIBUTION'),
        const SizedBox(height: 12),
        SizedBox(
          height: 190,
          child: dist.isEmpty
              ? const McEmpty('暂无数据')
              : Stack(alignment: Alignment.center, children: [
                  PieChart(PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 56,
                    sections: [
                      for (final d in dist)
                        PieChartSectionData(
                            value: d.value.toDouble(),
                            color: d.color,
                            radius: 14,
                            showTitle: false),
                    ],
                  )),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('总成交名义', style: Mc.tag()),
                    Text(Fmt.compact(_totalUsd, prefix: '\$'),
                        style: Mc.mono(18, w: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('${_alerts.length} 笔监控中',
                        style: Mc.mono(10, color: Mc.bull)),
                  ]),
                ]),
        ),
        const SizedBox(height: 12),
        for (final d in dist) ...[
          _distRow(d),
          const SizedBox(height: 10),
        ],
        if (dist.isNotEmpty) ...[
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Mc.hairline))),
            child: Row(children: [
              Text('数据源:', style: Mc.mono(10, color: Mc.muted)),
              const Spacer(),
              Text('HYPERLIQUID + BINANCE',
                  style: Mc.mono(10, w: FontWeight.w600)),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _distRow(({String symbol, num value, Color color}) d) {
    final pct = _totalUsd > 0 ? d.value / _totalUsd : 0.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: d.color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(d.symbol, style: Mc.mono(12, w: FontWeight.w600)),
        const Spacer(),
        Text('${(pct * 100).toStringAsFixed(1)}%', style: Mc.mono(12)),
        const SizedBox(width: 8),
        Text('(${Fmt.compact(d.value, prefix: '\$')})',
            style: Mc.mono(10, color: Mc.muted)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: 6,
          child: Stack(children: [
            Container(color: Mc.surface),
            FractionallySizedBox(
              widthFactor: pct.clamp(0.0, 1.0).toDouble(),
              child: Container(color: d.color),
            ),
          ]),
        ),
      ),
    ]);
  }

  // ---------- 右列 2: 买卖净额 ----------
  Widget _netCard() {
    final net = _netUsd;
    final positive = net >= 0;
    final bars = _trendBars;
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const McSection('大额买卖净额', tag: 'NET WHALE FLOW'),
        const SizedBox(height: 12),
        Text('${positive ? '+' : '-'}${Fmt.compact(net.abs(), prefix: '\$')}',
            style: Mc.mono(26,
                w: FontWeight.w600, color: positive ? Mc.up : Mc.down)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: McBadge(
            positive ? '买盘占优 ACCUMULATION' : '卖盘占优 DISTRIBUTION',
            color: positive ? Mc.up : Mc.down,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Mc.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Mc.hairline),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('大额买入 (吸筹)',
                        style: Mc.mono(10, color: Mc.muted)),
                    const SizedBox(height: 4),
                    Text(Fmt.compact(_buyUsd, prefix: '\$'),
                        style: Mc.mono(13, w: FontWeight.w600, color: Mc.up)),
                  ]),
            ),
            Container(width: 1, height: 34, color: Mc.hairline),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('大额卖出 (抛压)',
                        style: Mc.mono(10, color: Mc.muted)),
                    const SizedBox(height: 4),
                    Text(Fmt.compact(_sellUsd, prefix: '\$'),
                        style: Mc.mono(13, w: FontWeight.w600, color: Mc.down)),
                  ]),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Text('24H 方向时序 (每4小时)',
              style: Mc.mono(10, color: Mc.muted)),
          const Spacer(),
          Text('基准线: 0 轴', style: Mc.mono(10, color: Mc.muted)),
        ]),
        const SizedBox(height: 8),
        _trendChart(bars),
      ]),
    );
  }

  Widget _trendChart(List<_TrendBar> bars) {
    return SizedBox(
      height: 104,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final b in bars)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: 4 + 72 * b.frac.clamp(0.0, 1.0),
                    decoration: BoxDecoration(
                      color: (b.isBuy ? Mc.up : Mc.down)
                          .withValues(alpha: 0.85),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(b.label,
                      style: Mc.mono(9,
                          w: b.isLast ? FontWeight.w600 : FontWeight.w500,
                          color: b.isLast ? Mc.bull : Mc.muted)),
                ],
              ),
            ),
          ),
      ]),
    );
  }
}

/// 时序柱数据。
class _TrendBar {
  const _TrendBar(
      {required this.label,
      required this.frac,
      required this.isBuy,
      required this.isLast});
  final String label;
  final double frac;
  final bool isBuy;
  final bool isLast;
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

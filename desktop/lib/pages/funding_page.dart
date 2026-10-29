import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/kit.dart';

/// 资金费率页: 全网费率 KPI / 跨平台热力图 / 费率明细全景表。
/// 数据组织参考 web-terminal/src/views/Funding.vue。
/// 注意: 后端费率已是 % 量纲 (0.0099 = 0.0099%)，且嵌套在
/// data[].stablecoin_margin_list 内。
class FundingPage extends StatefulWidget {
  const FundingPage({super.key});

  @override
  State<FundingPage> createState() => _FundingPageState();
}

class _FundingPageState extends State<FundingPage> {
  bool _loading = true;
  bool _fatal = false;

  List<dynamic> _allRates = const []; // [{symbol, stablecoin_margin_list:[...]}]
  List<dynamic> _history = const []; // BTC 历史 [{rate, ...}]

  Timer? _pollTimer;
  Timer? _tickTimer;
  DateTime _now = DateTime.now();

  static const _heatCoins = ['BTC', 'ETH', 'SOL', 'DOGE', 'XRP', 'ARB', 'BNB', 'LINK'];
  static const _heatExchanges = ['Binance', 'OKX', 'Bybit', 'Bitget', 'Gate'];
  static const _matrixExchanges = ['Binance', 'OKX', 'Bybit'];

  // 8H 当前 / 24H 均值 口径
  String _rateMode = '8h';
  final Map<String, double> _histAvg = {}; // symbol -> 近 3 期 (≈24H) 均值
  bool _histLoading = false;

  String? _expanded; // 行内展开的币种

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) => _load());
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ApiClient.I;
    final r = await Future.wait([
      _safe(api.fundingExchangeRates(symbol: 'BTC')), // 上游忽略 symbol, 返回全币种
      _safe(api.fundingHistory(symbol: 'BTC')),
    ]);
    if (!mounted) return;
    setState(() {
      if (r[0] is Map && (r[0] as Map)['data'] is List) {
        _allRates = (r[0] as Map)['data'] as List;
      }
      if (r[1] is Map && (r[1] as Map)['history'] is List) {
        _history = (r[1] as Map)['history'] as List;
      }
      _fatal = _allRates.isEmpty && _history.isEmpty;
      _loading = false;
    });
  }

  Future<dynamic> _safe(Future<dynamic> f) async {
    try {
      return await f;
    } catch (_) {
      return null;
    }
  }

  Future<void> _retry() async {
    setState(() {
      _loading = true;
      _fatal = false;
    });
    await _load();
  }

  // ---------- 口径切换: 24H 均值懒加载 ----------
  Future<void> _setMode(String mode) async {
    setState(() => _rateMode = mode);
    if (mode != '24h' || _histAvg.isNotEmpty || _histLoading) return;
    _histLoading = true;
    try {
      final api = ApiClient.I;
      final res = await Future.wait(
          _heatCoins.map((c) => _safe(api.fundingHistory(symbol: c))));
      if (!mounted) return;
      final map = <String, double>{};
      for (var i = 0; i < res.length; i++) {
        final r = res[i];
        if (r is! Map || r['history'] is! List) continue;
        final pts = (r['history'] as List)
            .map((h) => Fmt.toNum(h is Map ? h['rate'] : null))
            .whereType<num>()
            .toList();
        final last3 = pts.length > 3 ? pts.sublist(pts.length - 3) : pts;
        if (last3.isNotEmpty) {
          map[_heatCoins[i]] =
              last3.reduce((a, b) => a + b).toDouble() / last3.length;
        }
      }
      setState(() => _histAvg
        ..clear()
        ..addAll(map));
    } finally {
      _histLoading = false;
    }
  }

  // ---------- 取数 ----------
  num? _rateOfEntry(dynamic e) =>
      e is Map ? Fmt.toNum(e['funding_rate'] ?? e['fundingRate'] ?? e['rate']) : null;

  List<_FlatRate> get _flatRates {
    final out = <_FlatRate>[];
    for (final d in _allRates) {
      if (d is! Map) continue;
      final list = d['stablecoin_margin_list'];
      if (list is! List) continue;
      for (final e in list) {
        final v = _rateOfEntry(e);
        if (v == null) continue;
        out.add(_FlatRate(
          symbol: (d['symbol'] ?? '').toString(),
          exchange: (e['exchange'] ?? '').toString(),
          rate: v.toDouble(),
          nextTs: Fmt.toNum(e['next_funding_time'])?.toInt(),
        ));
      }
    }
    return out;
  }

  double? get _avgAll {
    final flat = _flatRates;
    if (flat.isEmpty) return null;
    return flat.fold<double>(0, (s, r) => s + r.rate) / flat.length;
  }

  _FlatRate? get _highest {
    _FlatRate? m;
    for (final r in _flatRates) {
      if (m == null || r.rate > m.rate) m = r;
    }
    return m;
  }

  _FlatRate? get _lowest {
    _FlatRate? m;
    for (final r in _flatRates) {
      if (m == null || r.rate < m.rate) m = r;
    }
    return m;
  }

  static double? _annualized(double? r) => r == null ? null : r * 3 * 365;

  num? _coinExRate(String coin, String exchange) {
    for (final d in _allRates) {
      if (d is! Map || d['symbol'] != coin) continue;
      final list = d['stablecoin_margin_list'];
      if (list is! List) return null;
      for (final e in list) {
        if (e is Map && e['exchange'] == exchange) return _rateOfEntry(e);
      }
    }
    return null;
  }

  /// 热力单元格口径: 24H 为币种级均值, 8H 为各平台当前费率。
  num? _cellRate(String coin, String exchange) {
    if (_rateMode == '24h') return _histAvg[coin];
    return _coinExRate(coin, exchange);
  }

  Color _heatBg(num? v) {
    if (v == null) return Colors.transparent;
    final a = math.min(v.abs() / 0.05, 1.0); // 0.05% 封顶饱和
    final base = v >= 0 ? Mc.up : Mc.down;
    return base.withValues(alpha: 0.1 + a * 0.6);
  }

  static String _pct(num? v, int dp) => v == null
      ? '--'
      : '${v > 0 ? '+' : ''}${v.toStringAsFixed(dp)}%';

  List<_MatrixRow> get _matrixRows {
    final flat = _flatRates;
    final out = <_MatrixRow>[];
    for (final c in _heatCoins) {
      final entries = flat.where((r) => r.symbol == c).toList();
      if (entries.isEmpty) continue;
      final rates = _matrixExchanges
          .map((ex) =>
              entries.where((r) => r.exchange == ex).firstOrNull?.rate)
          .toList();
      final vals = entries.map((r) => r.rate).toList();
      final avg = vals.reduce((a, b) => a + b) / vals.length;
      final spreadBps =
          (vals.reduce(math.max) - vals.reduce(math.min)) * 100; // % -> bps
      final future = entries
          .map((r) => r.nextTs)
          .whereType<int>()
          .where((t) => t > _now.millisecondsSinceEpoch)
          .toList()
        ..sort();
      out.add(_MatrixRow(
        symbol: c,
        rates: rates,
        avg: avg,
        spreadBps: spreadBps,
        nextTs: future.isEmpty ? null : future.first,
      ));
    }
    return out;
  }

  double? _avgOf(_MatrixRow row) =>
      _rateMode == '24h' ? (_histAvg[row.symbol]) : row.avg;

  String _countdown(int? targetMs) {
    if (targetMs == null) return '--:--:--';
    var s = ((targetMs - _now.millisecondsSinceEpoch) / 1000).floor();
    if (s < 0) s = 0;
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(s ~/ 3600)}:${p((s % 3600) ~/ 60)}:${p(s % 60)}';
  }

  _BasisDetail? _basisDetail(String symbol) {
    final entries = _flatRates.where((r) => r.symbol == symbol).toList();
    if (entries.isEmpty) return null;
    var hi = entries.first, lo = entries.first;
    for (final e in entries) {
      if (e.rate > hi.rate) hi = e;
      if (e.rate < lo.rate) lo = e;
    }
    return _BasisDetail(entries, hi, lo, (hi.rate - lo.rate) * 100);
  }

  List<num> get _histRates => _history
      .map((h) => Fmt.toNum(h is Map ? h['rate'] : null))
      .whereType<num>()
      .toList();

  @override
  Widget build(BuildContext context) {
    if (_loading) return const McLoading(label: '费率数据加载中');
    if (_fatal) {
      return McError('费率数据暂时不可用，请稍后重试', onRetry: _retry);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header(),
        const SizedBox(height: 16),
        _kpiRow(),
        const SizedBox(height: 16),
        _midRow(),
        const SizedBox(height: 16),
        _matrixCard(),
      ]),
    );
  }

  // ---------- 页头 ----------
  Widget _header() {
    return Container(
      padding: const EdgeInsets.only(bottom: 12),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Mc.hairline))),
      child: Row(children: [
        Expanded(
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const McTag('FUNDING MATRIX', color: Mc.cobaltSoft),
                Text('全网资金费率矩阵与套利引擎', style: Mc.display(16)),
              ]),
              McBadge('UTC 结算窗口: 00:00 / 08:00 / 16:00', color: Mc.muted),
            ],
          ),
        ),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                  color: Mc.bull, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text('聚合 ${_heatExchanges.length} 家主流平台节点',
              style: Mc.body(11, color: Mc.muted)),
        ]),
        const SizedBox(width: 12),
        McButton('强制重校',
            kind: McBtnKind.ghost,
            height: 30,
            icon: Icons.refresh,
            onPressed: _load),
      ]),
    );
  }

  // ---------- ROW 1: KPI ----------
  Widget _kpiRow() {
    final hi = _highest, lo = _lowest;
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth > 980) {
        return McRow(spans: const [4, 4, 4], children: [
          _avgCard(fill: true),
          _extremeCard(
            fill: true,
            tag: 'HIGHEST RATE',
            badge: '多头极度溢价',
            badgeColor: Mc.up,
            r: hi,
            foot1: '多空偏离度: 极度贴水 (多付空)',
            foot2: '参考策略: 现货多头 + 永续空头基差套利',
            icon: Icons.trending_up,
          ),
          _extremeCard(
            fill: true,
            tag: 'LOWEST RATE',
            badge: '反向套利敞口',
            badgeColor: Mc.down,
            r: lo,
            foot1: '状态: 空头支付多头 (空头挤压预警)',
            foot2: '参考策略: 多头持仓获取费率分红',
            icon: Icons.trending_down,
          ),
        ]);
      }
      final w = c.maxWidth;
      return Wrap(spacing: 16, runSpacing: 16, children: [
        SizedBox(width: w, child: _avgCard()),
        SizedBox(width: w, child: _extremeCard(
          tag: 'HIGHEST RATE',
          badge: '多头极度溢价',
          badgeColor: Mc.up,
          r: hi,
          foot1: '多空偏离度: 极度贴水 (多付空)',
          foot2: '参考策略: 现货多头 + 永续空头基差套利',
          icon: Icons.trending_up,
        )),
        SizedBox(width: w, child: _extremeCard(
          tag: 'LOWEST RATE',
          badge: '反向套利敞口',
          badgeColor: Mc.down,
          r: lo,
          foot1: '状态: 空头支付多头 (空头挤压预警)',
          foot2: '参考策略: 多头持仓获取费率分红',
          icon: Icons.trending_down,
        )),
      ]);
    });
  }

  Widget _avgCard({bool fill = false}) {
    final avg = _avgAll;
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
              child: McSection('全市场平均资金费率', tag: 'AVERAGE FUNDING RATE')),
          const Icon(Icons.query_stats, size: 20, color: Mc.amber),
        ]),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_pct(avg, 4),
                  style: Mc.mono(28, w: FontWeight.w700, color: Mc.amber)),
              const SizedBox(height: 4),
              Text('年化折算参考: ${_pct(_annualized(avg), 2)} p.a.',
                  style: Mc.body(11, color: Mc.muted)),
            ]),
          ),
          SizedBox(width: 96, height: 36, child: _miniSpark()),
        ]),
        if (fill) const Spacer() else const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Mc.hairline))),
          child: Column(children: [
            Row(children: [
              Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      color: Mc.amber, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  avg != null && avg >= 0
                      ? '多头持仓偏多 · 情绪轻微亢奋'
                      : '空头持仓偏多 · 情绪偏谨慎',
                  style: Mc.body(11, w: FontWeight.w500, color: Mc.amber),
                ),
              ),
              Text('基准 8H', style: Mc.mono(11, color: Mc.muted)),
            ]),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '监控标的: ${_allRates.length} 币种 · ${_flatRates.length} 个平台费率',
                style: Mc.mono(11, color: Mc.muted),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _miniSpark() {
    final pts = _histRates;
    if (pts.length < 2) return const SizedBox.shrink();
    final spots = <FlSpot>[
      for (var i = 0; i < pts.length; i++)
        FlSpot(i.toDouble(), pts[i].toDouble()),
    ];
    final mn = pts.reduce(math.min).toDouble();
    final mx = pts.reduce(math.max).toDouble();
    final pad = (mx - mn) * 0.1 + 1e-9;
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
          color: Mc.amber,
          barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData:
              BarAreaData(show: true, color: Mc.amber.withValues(alpha: 0.1)),
        ),
      ],
    ));
  }

  Widget _extremeCard({
    bool fill = false,
    required String tag,
    required String badge,
    required Color badgeColor,
    required _FlatRate? r,
    required String foot1,
    required String foot2,
    required IconData icon,
  }) {
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                McTag(tag),
                const SizedBox(width: 8),
                McBadge(badge, color: badgeColor),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Text(r == null ? '--' : '${r.symbol}USDT',
                    style: Mc.display(16)),
                const SizedBox(width: 6),
                Text('永续', style: Mc.body(11, color: Mc.muted)),
              ]),
            ]),
          ),
          Icon(icon, size: 20, color: badgeColor),
        ]),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_pct(r?.rate, 4),
                  style: Mc.mono(28, w: FontWeight.w700, color: badgeColor)),
              const SizedBox(height: 4),
              Text('年化折算: ${_pct(_annualized(r?.rate), 2)} p.a.',
                  style: Mc.body(11, color: Mc.muted)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            McBadge(r?.exchange ?? '--', color: Mc.ink),
            const SizedBox(height: 4),
            Text('深度流动性 T0', style: Mc.mono(10, color: Mc.muted)),
          ]),
        ]),
        if (fill) const Spacer() else const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Mc.hairline))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      color: badgeColor, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(foot1,
                      style: Mc.body(11,
                          w: FontWeight.w500, color: badgeColor))),
              Text('8H 一期', style: Mc.mono(11, color: Mc.muted)),
            ]),
            const SizedBox(height: 6),
            Text(foot2, style: Mc.mono(11, color: Mc.ink)),
          ]),
        ),
      ]),
    );
  }

  // ---------- ROW 2: 热力图 + 机制说明 ----------
  Widget _midRow() {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > 980;
      if (!wide) {
        return Column(children: [
          _heatmapCard(),
          const SizedBox(height: 16),
          _intelCard(),
        ]);
      }
      return McRow(spans: const [8, 4], children: [
        _heatmapCard(fill: true),
        _intelCard(fill: true),
      ]);
    });
  }

  Widget _heatmapCard({bool fill = false}) {
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
              child: McSection('全网费率热力图',
                  tag: 'CROSS-PLATFORM HEATMAP')),
          _modeSwitch(),
        ]),
        const Divider(height: 20, color: Mc.hairline),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: math.max(640, _heatCoins.length * 86.0 + 110),
            child: Column(children: [
              Row(children: [
                const SizedBox(
                    width: 110,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: McTag('PLATFORM'),
                    )),
                for (final c in _heatCoins)
                  Expanded(
                      child: Text(c,
                          textAlign: TextAlign.center,
                          style: Mc.mono(11,
                              w: FontWeight.w600, color: Mc.ink))),
              ]),
              const Divider(height: 1, color: Mc.hairline),
              for (var i = 0; i < _heatExchanges.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: Mc.hairline),
                _heatRow(_heatExchanges[i]),
              ],
            ]),
          ),
        ),
        if (fill) const Spacer() else const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Mc.hairline))),
          child: Wrap(spacing: 10, runSpacing: 6, children: [
            Text(
              '* 颜色饱和度绑定费率绝对值偏离度${_rateMode == '24h' ? ' · 当前为 24H 均值口径 (近 3 期结算均值)' : ''}',
              style: Mc.mono(11, color: Mc.muted),
            ),
            if (_highest != null && _lowest != null)
              Text(
                '高亮基差利差: ${_highest!.symbol} (${_pct(_highest!.rate, 3)}) / ${_lowest!.symbol} (${_pct(_lowest!.rate, 3)})',
                style: Mc.mono(11, color: Mc.muted),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _modeSwitch() {
    Widget btn(String label, String mode) {
      final active = _rateMode == mode;
      return GestureDetector(
        onTap: () => _setMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active ? Mc.card : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label,
              style: Mc.mono(11,
                  w: FontWeight.w500,
                  color: active ? Mc.ink : Mc.muted)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Mc.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Mc.hairline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn('8H 当前周期', '8h'),
        btn('24H 均值', '24h'),
      ]),
    );
  }

  Widget _heatRow(String exchange) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        SizedBox(
            width: 110,
            child: Text(exchange,
                style: Mc.body(13, w: FontWeight.w500))),
        for (final c in _heatCoins) ...[
          const SizedBox(width: 6),
          Expanded(child: _heatCell(c, exchange)),
        ],
      ]),
    );
  }

  Widget _heatCell(String coin, String exchange) {
    final v = _cellRate(coin, exchange);
    return Container(
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _heatBg(v),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Mc.hairline.withValues(alpha: 0.4)),
      ),
      child: Text(
        v == null ? '--' : _pct(v, 3),
        style: Mc.mono(12,
            w: v != null && v.abs() >= 0.035
                ? FontWeight.w700
                : FontWeight.w500,
            color: v == null ? Mc.muted : Mc.upDown(v)),
      ),
    );
  }

  Widget _intelCard({bool fill = false}) {
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const McSection('费率机制与套利说明', tag: 'INTEL & GUIDELINES'),
        const Divider(height: 20, color: Mc.hairline),
        _intelItem(
          icon: Icons.sync_alt,
          color: Mc.cobaltSoft,
          title: '1. 结算机制与资金流向',
          body:
              '资金费率每 8 小时（00:00, 08:00, 16:00 UTC）在多空持仓者之间直接结算，不经由平台收取。当费率为正，多头向空头支付；当费率为负，空头向多头支付。',
        ),
        const SizedBox(height: 12),
        _intelItem(
          icon: Icons.troubleshoot,
          color: Mc.amber,
          title: '2. 市场多空情绪锚定',
          body: '正费率溢价过高（>0.03%）反映多头情绪极度亢奋，伴随潜在多头挤压风险；深度负费率通常预示强支撑反弹或空头回补窗口。',
        ),
        const SizedBox(height: 12),
        _intelItem(
          icon: Icons.account_balance,
          color: Mc.bull,
          title: '3. 期现套利 (CASH & CARRY)',
          body:
              '利用不同平台费率差异进行跨平台套利（如在 A 平台做空同时在 B 平台做多相同标的），或买入现货同时做空高正费率永续，无方向性风险获取稳健年化资金费收益。',
        ),
        if (fill) const Spacer() else const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Mc.hairline))),
          child: Row(children: [
            Text('风险评级: 低至中性 (DELTA NEUTRAL)',
                style: Mc.mono(11, color: Mc.muted)),
          ]),
        ),
      ]),
    );
  }

  Widget _intelItem({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Mc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Mc.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
              child: Text(title,
                  style: Mc.body(13, w: FontWeight.w600, color: color))),
        ]),
        const SizedBox(height: 6),
        Text(body, style: Mc.body(12, color: Mc.muted)),
      ]),
    );
  }

  // ---------- ROW 3: 费率明细全景表 ----------
  Widget _matrixCard() {
    final rows = _matrixRows;
    return McCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: Row(children: [
            const Expanded(
                child: McSection('费率明细全景表',
                    tag: 'LIVE FUNDING ARBITRAGE MATRIX')),
            McBadge('${rows.length} 对核心标的', color: Mc.muted),
            const SizedBox(width: 12),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      color: Mc.bull, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('自动重拉取: 60S', style: Mc.mono(11, color: Mc.muted)),
            ]),
          ]),
        ),
        const Divider(height: 1, color: Mc.hairline),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(children: [
            const Expanded(flex: 3, child: McTh('标的资产 (PERP)')),
            for (final ex in _matrixExchanges)
              Expanded(
                  flex: 2,
                  child: McTh('$ex 费率', align: TextAlign.right)),
            Expanded(
                flex: 2,
                child: McTh(
                    _rateMode == '24h' ? '24H 均值' : '全网均值',
                    align: TextAlign.right)),
            const Expanded(
                flex: 3,
                child: McTh('下次结算倒计时', align: TextAlign.center)),
            const Expanded(
                flex: 2, child: McTh('预期年化', align: TextAlign.right)),
            const Expanded(
                flex: 3,
                child: McTh('跨平台基差 / 操作', align: TextAlign.center)),
          ]),
        ),
        const Divider(height: 1, color: Mc.hairline),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: McEmpty('暂无费率数据'),
          )
        else
          for (var i = 0; i < rows.length; i++) ...[
            _matrixRow(rows[i]),
            if (_expanded == rows[i].symbol) _basisPanel(rows[i].symbol),
            if (i != rows.length - 1)
              const Divider(height: 1, color: Mc.hairline),
          ],
        Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Mc.hairline))),
          child: Wrap(spacing: 14, runSpacing: 6, children: [
            Text('数据刷新间隔: 60S 轮询',
                style: Mc.mono(11, color: Mc.muted)),
            Text('已同步 ${_heatExchanges.length} 家平台节点',
                style: Mc.mono(11, color: Mc.muted)),
            Text('结算周期: 8H', style: Mc.mono(11, color: Mc.muted)),
            Text('显示 ${rows.length} 条核心标的',
                style: Mc.mono(11, color: Mc.muted)),
          ]),
        ),
      ]),
    );
  }

  Widget _matrixRow(_MatrixRow row) {
    final avg = _avgOf(row);
    final apr = _annualized(avg);
    return _HoverRow(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      children: [
        Expanded(
          flex: 3,
          child: Row(children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Mc.surface,
                shape: BoxShape.circle,
                border: Border.all(color: Mc.hairline),
              ),
              child: Text(row.symbol.substring(0, 1),
                  style: Mc.mono(10,
                      w: FontWeight.w700, color: Mc.cobaltSoft)),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${row.symbol}USDT',
                  style: Mc.body(13, w: FontWeight.w600)),
              Text('${row.symbol} 永续',
                  style: Mc.mono(10, color: Mc.muted)),
            ]),
          ]),
        ),
        for (final r in row.rates)
          Expanded(
            flex: 2,
            child: Text(_pct(r, 4),
                textAlign: TextAlign.right,
                style: Mc.mono(12, color: r == null ? Mc.muted : Mc.upDown(r))),
          ),
        Expanded(
          flex: 2,
          child: Text(_pct(avg, 4),
              textAlign: TextAlign.right,
              style: Mc.mono(12,
                  w: FontWeight.w600,
                  color: avg == null ? Mc.muted : Mc.upDown(avg))),
        ),
        Expanded(
          flex: 3,
          child: Center(child: _countdownChip(row)),
        ),
        Expanded(
          flex: 2,
          child: Text(_pct(apr, 2),
              textAlign: TextAlign.right,
              style: Mc.mono(12,
                  w: FontWeight.w700,
                  color: apr == null ? Mc.muted : Mc.upDown(apr))),
        ),
        Expanded(
          flex: 3,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(
              'Δ ${row.spreadBps.toStringAsFixed(1)} bps${row.spreadBps >= 5 ? ' (套利)' : ''}',
              style: Mc.mono(11,
                  color:
                      row.spreadBps >= 5 ? Mc.bear : Mc.muted),
            ),
            const SizedBox(width: 8),
            _basisButton(row.symbol),
          ]),
        ),
      ],
    );
  }

  Widget _countdownChip(_MatrixRow row) {
    final down = row.avg < 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Mc.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Mc.hairline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
                color: down ? Mc.down : Mc.up,
                shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(_countdown(row.nextTs),
            style: Mc.mono(11, color: Mc.ink)),
      ]),
    );
  }

  Widget _basisButton(String symbol) {
    final active = _expanded == symbol;
    return GestureDetector(
      onTap: () =>
          setState(() => _expanded = active ? null : symbol),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? Mc.cobalt : Mc.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
              color: active ? Mc.cobalt : Mc.hairline),
        ),
        child: Text(active ? '收起' : '查看基差',
            style: Mc.body(11,
                w: FontWeight.w600,
                color: active ? Colors.white : Mc.ink)),
      ),
    );
  }

  Widget _basisPanel(String symbol) {
    final detail = _basisDetail(symbol);
    return Container(
      color: Mc.surface.withValues(alpha: 0.4),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: detail == null
          ? Text('该币种暂无平台费率明细',
              style: Mc.mono(11, color: Mc.muted))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in detail.entries)
                  _basisChip(e, detail),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 6, children: [
                Text('价差最大两家: ',
                    style: Mc.mono(11, color: Mc.muted)),
                Text(detail.hi.exchange,
                    style: Mc.mono(11, color: Mc.up)),
                Text(' / ', style: Mc.mono(11, color: Mc.muted)),
                Text(detail.lo.exchange,
                    style: Mc.mono(11, color: Mc.down)),
                Text(
                    ' · Δ ${detail.spreadBps.toStringAsFixed(1)} bps',
                    style: Mc.mono(11, color: Mc.muted)),
                if (detail.spreadBps >= 5)
                  Text(' · 满足跨平台套利阈值',
                      style: Mc.mono(11, color: Mc.amber)),
              ]),
            ]),
    );
  }

  Widget _basisChip(_FlatRate e, _BasisDetail d) {
    final isHi = e.exchange == d.hi.exchange && e.rate == d.hi.rate;
    final isLo = e.exchange == d.lo.exchange && e.rate == d.lo.rate;
    final color = isHi ? Mc.up : (isLo ? Mc.down : Mc.ink);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: isHi || isLo
            ? color.withValues(alpha: 0.1)
            : Mc.card,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
            color: isHi || isLo
                ? color.withValues(alpha: 0.4)
                : Mc.hairline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(e.exchange,
            style: Mc.mono(11, w: FontWeight.w600, color: color)),
        const SizedBox(width: 6),
        Text(_pct(e.rate, 4), style: Mc.mono(11, color: color)),
        if (isHi)
          Text(' 最高', style: Mc.mono(9, color: color)),
        if (isLo)
          Text(' 最低', style: Mc.mono(9, color: color)),
      ]),
    );
  }
}

class _FlatRate {
  const _FlatRate({
    required this.symbol,
    required this.exchange,
    required this.rate,
    this.nextTs,
  });
  final String symbol;
  final String exchange;
  final double rate;
  final int? nextTs;
}

class _MatrixRow {
  const _MatrixRow({
    required this.symbol,
    required this.rates,
    required this.avg,
    required this.spreadBps,
    this.nextTs,
  });
  final String symbol;
  final List<double?> rates;
  final double avg;
  final double spreadBps;
  final int? nextTs;
}

class _BasisDetail {
  const _BasisDetail(this.entries, this.hi, this.lo, this.spreadBps);
  final List<_FlatRate> entries;
  final _FlatRate hi;
  final _FlatRate lo;
  final double spreadBps;
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

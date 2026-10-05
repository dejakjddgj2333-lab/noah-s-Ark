import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/api.dart';
import '../services/data.dart';

/// 资金费率 (Funding Rate) content body.
///
/// 费率矩阵与全网加权指数接 `/api/market-overview/funding/exchange-rates`.
/// 首屏在首轮加载完成前显示骨架屏, 不再展示 mock 假数据; 加载失败的字段
/// 显示 '--' 或空态, 永不红屏.
class HomeFundingPage extends StatefulWidget {
  const HomeFundingPage({super.key});

  @override
  State<HomeFundingPage> createState() => _HomeFundingPageState();
}

class _HomeFundingPageState extends State<HomeFundingPage> {
  // Screen-specific accents from home_funding.html.
  static const _error = Color(0xFFFF6B6B);
  static const _hairline = Color(0x0FFFFFFF); // white/5
  static const _hairlineSoft = Color(0x0FFFFFFF); // white/[0.06]

  // 首轮加载是否完成 (成功或失败都算): false 时首屏显示骨架屏.
  bool _loaded = false;

  // 全网加权指数 (BTC 行均值): 未加载/失败显示 '--', 不显示编造数字.
  String _indexApy = '--';
  String _indexRate8h = '--';

  // 费率矩阵筛选: pos=正费率 / neg=负费率 / hot=异动激增 (|rate|>=0.03).
  String _filter = 'pos';
  // 展开更多合约: 已加载的额外 symbol.
  bool _expanded = false;
  bool _expanding = false;

  // 下次 8H 结算倒计时 (UTC 00/08/16).
  String _countdown = '--:--:--';
  Timer? _cdTimer;
  // BTC 平均费率 (温度条游标, 默认 0 对应中性 50%).
  double _btcRate = 0;

  // BTC 费率近 7 日真实序列 (8H 一期); 空=未加载, 曲线回退示意.
  List<double> _trendRates = const [];

  // 头部健康标签: 由 BTC 费率符号与幅度推导.
  String get _healthLabel {
    if (_btcRate >= 0.03) return '多头过热·高溢价';
    if (_btcRate >= 0.005) return '健康多头·温和溢价';
    if (_btcRate > -0.005) return '多空均衡';
    if (_btcRate > -0.03) return '空头温和·贴水';
    return '空头拥挤·深度贴水';
  }

  // 费率矩阵行: 初始为空 (首屏骨架), 接口成功后按 symbol upsert.
  List<_FundingRow> _rows = const [];

  // 展示排序: 基础 6 个 + 展开额外合约, 保持设计稿顺序而非接口返回顺序.
  static const _symbolOrder = [
    'DOGE', 'SOL', 'BTC', 'ETH', 'XRP', 'XTZ',
    'BNB', 'ADA', 'AVAX', 'LINK', 'LTC', 'NEAR', 'TON', 'APT',
  ];

  static int _ord(String s) {
    final i = _symbolOrder.indexOf(s);
    return i < 0 ? 999 : i;
  }

  static List<_FundingRow> _sorted(List<_FundingRow> rows) =>
      [...rows]..sort((a, b) => _ord(a.symbol).compareTo(_ord(b.symbol)));

  // ---- Module 4 matrix rows: BTC/ETH/SOL/XRP/DOGE/XTZ 费率已接线, 现价由 tickers 填充 ----

  @override
  void initState() {
    super.initState();
    _tickCountdown();
    _cdTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _tickCountdown());
    _load();
  }

  @override
  void dispose() {
    _cdTimer?.cancel();
    super.dispose();
  }

  // 距下一个 UTC 00/08/16 整点.
  void _tickCountdown() {
    final now = DateTime.now().toUtc();
    var next = DateTime.utc(now.year, now.month, now.day,
        (now.hour ~/ 8 + 1) * 8 % 24);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    final d = next.difference(now);
    String two(int n) => n.toString().padLeft(2, '0');
    final text =
        '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
    if (mounted && text != _countdown) setState(() => _countdown = text);
  }

  Future<void> _load() async {
    // 各 symbol 独立并行尝试, 任一失败不影响其它行.
    await Future.wait([
      _fetchSymbol('BTC'),
      _fetchSymbol('ETH'),
      _fetchSymbol('SOL'),
      _fetchSymbol('XRP'),
      _fetchSymbol('DOGE'),
      _fetchSymbol('XTZ'),
      _loadPrices(),
      _loadTrend(),
    ]);
    // 首轮完成 (无论成败) 后撤出骨架屏; 下拉刷新时 _loaded 已为 true, 不回到骨架.
    if (mounted && !_loaded) setState(() => _loaded = true);
  }

  // BTC 费率 7D 真实历史 (OKX funding-rate-history).
  Future<void> _loadTrend() async {
    try {
      final resp = await McData.overview('funding/history?symbol=BTC');
      final list = resp['history'];
      if (list is! List || list.isEmpty || !mounted) return;
      final rates = <double>[
        for (final e in list)
          if (e is Map && e['rate'] is num) (e['rate'] as num).toDouble(),
      ];
      if (rates.length < 2) return;
      setState(() => _trendRates = rates);
    } catch (_) {/* 保留示意曲线 */}
  }

  // 现价缓存 (symbol → last): funding 行异步出现, 缓存保证后到行的价格也能覆盖.
  Map<String, double> _priceBySymbol = const {};

  // 现价: funding 接口不带现价, 用 OKX tickers 按 symbol 覆盖每行价格.
  Future<void> _loadPrices() async {
    try {
      final tickers = await McData.tickers(instType: 'SWAP');
      if (!mounted) return;
      setState(() {
        _priceBySymbol = {for (final t in tickers) t.symbol: t.last};
        _rows = [
          for (final r in _rows)
            if (_priceBySymbol.containsKey(r.symbol))
              r.copyWith(price: _fmtPrice(_priceBySymbol[r.symbol]!))
            else
              r,
        ];
      });
    } catch (_) {
      // 现价接口失败 — 价格保持 '--' 或已有值.
    }
  }

  // 现价格式化: 与行情页一致 (千分位 / 4 位小数 / 2 位小数).
  static String _fmtPrice(double p) {
    if (p >= 1000) return '\$${_comma(p)}';
    if (p > 0 && p < 10) return '\$${p.toStringAsFixed(4)}';
    return '\$${p.toStringAsFixed(2)}';
  }

  static String _comma(double v) {
    final fixed = v.toStringAsFixed(2);
    final dot = fixed.indexOf('.');
    final intPart = fixed.substring(0, dot);
    final buf = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      buf.write(intPart[i]);
      final remaining = intPart.length - i - 1;
      if (remaining > 0 && remaining % 3 == 0) buf.write(',');
    }
    return '$buf.${fixed.substring(dot + 1)}';
  }

  Future<void> _fetchSymbol(String symbol) async {
    try {
      final resp =
          await McData.overview('funding/exchange-rates?symbol=$symbol');
      // 接口无现价字段: 优先现价缓存, 其次已有行价格, 兜底 '--'.
      final existing = _rows.where((r) => r.symbol == symbol);
      final cached = _priceBySymbol[symbol];
      final fallbackPrice = cached != null
          ? _fmtPrice(cached)
          : (existing.isEmpty ? '--' : existing.first.price);
      final parsed = _parseExchangeRates(symbol, resp['data'],
          fallbackPrice: fallbackPrice);
      if (parsed == null || !mounted) return;
      final (row, avgRate) = parsed;
      setState(() {
        // upsert: 已有该 symbol 则覆盖, 否则追加; 再按设计稿顺序排序.
        final next = [
          for (final r in _rows)
            if (r.symbol == symbol) row else r,
        ];
        if (!_rows.any((r) => r.symbol == symbol)) next.add(row);
        _rows = _sorted(next);
        if (symbol == 'BTC' && avgRate != null) {
          _btcRate = avgRate;
          _indexRate8h = '${_fmtRate(avgRate, signed: false)} / 8h';
          _indexApy = _fmtApy(avgRate);
        }
      });
    } on ApiException {
      // 503 未配置 / 502 上游错误 — 该行留空.
    } catch (_) {
      // 网络/解析异常 — 该行留空.
    }
  }

  // CoinGlass funding-rate/exchange-list → (费率行, 平均费率).
  // 结构: [{symbol, stablecoin_margin_list: [{exchange, funding_rate, ...}]}].
  // 匹配目标 symbol, 聚合其各所费率. 返回 null 表示数据不可用 (保留 mock).
  static (_FundingRow, double?)? _parseExchangeRates(
      String symbol, dynamic raw, {String fallbackPrice = '--'}) {
    final list = _asList(raw);
    Map<String, dynamic>? target;
    for (final e in list) {
      if (e is! Map) continue;
      final m = e.cast<String, dynamic>();
      final s = (m['symbol'] ?? m['coin'] ?? '').toString().toUpperCase();
      if (s == symbol) {
        target = m;
        break;
      }
    }
    if (target == null) return null;

    // 各所费率: 优先 stablecoin 保证金列表, 其次 token 保证金.
    final rates = <double>[];
    for (final key in ['stablecoin_margin_list', 'token_margin_list']) {
      final ml = target[key];
      if (ml is! List) continue;
      for (final e in ml) {
        if (e is! Map) continue;
        final m = e.cast<String, dynamic>();
        final rate = _num(m['fundingRate'] ?? m['funding_rate'] ?? m['rate']);
        // CoinGlass 费率为百分数 (0.004477 = 0.004477%); 兼容小数形式 (0.0001).
        final pct = rate.abs() < 0.001 && rate != 0 ? rate * 100 : rate;
        rates.add(pct);
      }
      if (rates.isNotEmpty) break; // 有 stablecoin 即不再叠加 token 列表
    }
    if (rates.isEmpty) return null;
    final avg = rates.reduce((a, b) => a + b) / rates.length;

    // 取前 3 所作为三所聚合展示, 不足 3 用均值补齐.
    final sub = <String>[];
    for (var i = 0; i < 3; i++) {
      final v = i < rates.length ? rates[i] : avg;
      sub.add(v.toStringAsFixed(3));
    }
    final status = _statusOf(avg);
    final row = _FundingRow(
      symbol: symbol,
      rateNum: avg,
      price: fallbackPrice, // 接口无现价字段, 沿用现有价格 (真实现价由 tickers 覆盖)
      rate: _fmtRate(avg),
      rateColor: avg >= 0.03
          ? McColors.tertiary
          : (avg > 0.005
              ? McColors.tertiary
              : (avg >= -0.005 ? McColors.primary : _error)),
      sub: sub,
      subColor: avg >= 0 ? McColors.tertiary : _error,
      apy: _fmtApy(avg),
      apyColor: avg >= 0.03
          ? McColors.tertiary
          : (avg >= -0.005 ? McColors.primary : _error),
      status: status.$1,
      statusColor: status.$2,
      statusBg: status.$3,
      statusBold: status.$4,
    );
    return (row, avg);
  }

  // rate 为百分数 (0.01 = 0.01%); 8H 一结 → 年化 = rate * 3 * 365.
  static String _fmtApy(double ratePct) {
    final apy = ratePct * 1095;
    final sign = apy >= 0 ? '+' : '';
    return '$sign${apy.toStringAsFixed(1)}%';
  }

  static String _fmtRate(double ratePct, {bool signed = true}) {
    final sign = signed && ratePct >= 0 ? '+' : '';
    return '$sign${ratePct.toStringAsFixed(4)}%';
  }

  static (String, Color, Color, bool) _statusOf(double avg) {
    if (avg >= 0.03) {
      return ('多头过热', _error, const Color(0x664E0002), true);
    }
    if (avg > 0.005) {
      return ('适度看多', McColors.tertiary, const Color(0x66005A34), true);
    }
    if (avg >= -0.005) {
      return ('基准平稳', McColors.onSurfaceVariant,
          McColors.surfaceContainerHigh, false);
    }
    return ('空头拥挤', _error, const Color(0x664E0002), true);
  }

  // ---- 解析辅助 ----
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

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      color: McColors.primaryContainer,
      backgroundColor: McColors.surfaceContainer,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 32),
        // 首轮加载未完成前显示骨架屏, 不展示任何 mock 数字.
        children: _loaded
            ? [
                _buildIndexCard(),
                const SizedBox(height: 24),
                _buildArbitrage(),
                const SizedBox(height: 24),
                _buildTrend(),
                const SizedBox(height: 24),
                _buildMatrix(),
              ]
            : [
                McSkeleton.card(lines: 5, height: 18),
                const SizedBox(height: 24),
                McSkeleton.card(lines: 2, height: 16),
                const SizedBox(height: 24),
                McSkeleton.card(lines: 3, height: 14),
                const SizedBox(height: 24),
                McSkeleton.card(lines: 6, height: 16),
              ],
      ),
    );
  }

  // ---- Module 1: 全网加权资金费率指数 ----
  Widget _buildIndexCard() {
    return McCard(
      color: McColors.surfaceContainer,
      padding: const EdgeInsets.all(20),
      radius: 16,
      child: Column(
        children: [
          // Title bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  children: [
                    const Icon(Icons.hub, size: 20, color: McColors.primary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '全网加权资金费率指数',
                        overflow: TextOverflow.ellipsis,
                        style: McText.sans(size: 15, weight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF005A34).withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: McColors.tertiary.withValues(alpha: 0.2)),
                      ),
                      child: Text('8H结算',
                          style: McText.sans(size: 10, weight: FontWeight.w600, color: McColors.tertiary)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: McColors.surfaceContainerHigh.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _hairline),
                ),
                child: Row(
                  children: [
                    const McGlowDot(color: McColors.tertiary, size: 6),
                    const SizedBox(width: 6),
                    Text(_indexRate8h, style: McText.mono(size: 11, color: McColors.tertiary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Core data
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('综合加权年化 (APY)',
                        style: McText.sans(size: 12, weight: FontWeight.w500, color: McColors.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(_indexApy,
                            style: McText.mono(size: 30, weight: FontWeight.w800, color: McColors.tertiary)),
                        const SizedBox(width: 4),
                        Text('APR',
                            style: McText.sans(
                                size: 12,
                                weight: FontWeight.w600,
                                color: McColors.tertiary.withValues(alpha: 0.8))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: McColors.tertiary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: McColors.tertiary.withValues(alpha: 0.2)),
                      ),
                      child: Text(_healthLabel,
                          style: McText.sans(size: 11, weight: FontWeight.w500, color: McColors.tertiary)),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('距离下次结算',
                      style: McText.sans(size: 12, weight: FontWeight.w500, color: McColors.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: McColors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _hairline),
                    ),
                    child: Text(_countdown,
                        style: McText.mono(
                            size: 20, weight: FontWeight.w700, color: McColors.primary, letterSpacing: 2)),
                  ),
                  const SizedBox(height: 6),
                  Text('结算周期 UTC 00/08/16', style: McText.mono(size: 10, color: McColors.outline)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Sentiment temperature bar
          Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('极度恐慌贴水 (-100%)', style: McText.sans(size: 10, color: _error.withValues(alpha: 0.9))),
                    ),
                  ),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('中性基准 (0%)', style: McText.sans(size: 10, color: McColors.outline)),
                    ),
                  ),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text('极度过热溢价 (+100%)', style: McText.sans(size: 10, color: McColors.tertiary)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 14,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      height: 8,
                      margin: const EdgeInsets.only(top: 3),
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: McColors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _hairline),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [_error.withValues(alpha: 0.6), _error.withValues(alpha: 0.2)],
                                  ),
                                ),
                              ),
                            ),
                            Expanded(child: Container(color: McColors.outline.withValues(alpha: 0.2))),
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      McColors.tertiary.withValues(alpha: 0.2),
                                      McColors.tertiary.withValues(alpha: 0.7),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Cursor: BTC 费率映射 [-0.05%, +0.05%] -> [0, 1]
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final frac =
                              ((_btcRate + 0.05) / 0.1).clamp(0.02, 0.98);
                          final left = constraints.maxWidth * frac - 7;
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                left: left,
                                top: 0,
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: McColors.primaryContainer,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 1.5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: McColors.primaryContainer.withValues(alpha: 0.7),
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- Module 2: 期现套利年化推荐 (真实费率 top2 正值) ----
  Widget _buildArbitrage() {
    // 正费率行降序取前二; 期现套利年化 = 8H 费率 × 1095.
    final pos = _rows.where((r) => r.rateNum > 0).toList()
      ..sort((a, b) => b.rateNum.compareTo(a.rateNum));
    final picks = pos.take(2).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      const Icon(Icons.currency_exchange, size: 20, color: McColors.secondary),
                      const SizedBox(width: 8),
                      Text('期现套利年化推荐 (Basis Arbitrage)',
                          style: McText.sans(size: 15, weight: FontWeight.w700, color: Colors.white)),
                    ],
                  ),
                ),
              ),
              Text('年化 = 8H费率×1095', style: McText.sans(size: 12, weight: FontWeight.w500, color: McColors.outline)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (picks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('当前无正费率合约, 暂无套利机会',
                style: McText.sans(size: 12, color: McColors.outline)),
          )
        else
          Row(
            children: [
              for (var i = 0; i < picks.length; i++) ...[
                if (i > 0) const SizedBox(width: 14),
                Expanded(
                  child: _arbCard(
                    symbol: picks[i].symbol,
                    tag: i == 0 ? '首推' : '次选',
                    tagColor: i == 0 ? McColors.tertiary : McColors.primary,
                    tagBg: i == 0
                        ? const Color(0xFF005A34).withValues(alpha: 0.4)
                        : McColors.primaryContainer.withValues(alpha: 0.3),
                    apy: '+${(picks[i].rateNum * 1095).toStringAsFixed(2)}%',
                    rate: '8H: ${picks[i].rateNum.toStringAsFixed(4)}%',
                    depth: '三所费率均值',
                  ),
                ),
              ],
              if (picks.length == 1) const Expanded(child: SizedBox()),
            ],
          ),
      ],
    );
  }

  Widget _arbCard({
    required String symbol,
    required String tag,
    required Color tagColor,
    required Color tagBg,
    required String apy,
    required String rate,
    required String depth,
  }) {
    return McCard(
      color: McColors.surfaceContainer,
      padding: const EdgeInsets.all(16),
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Text(symbol, style: McText.sans(size: 14, weight: FontWeight.w700, color: Colors.white)),
                      const SizedBox(width: 6),
                      Text('基差对冲', style: McText.mono(size: 10, color: McColors.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: tagBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: tagColor.withValues(alpha: 0.3)),
                ),
                child: Text(tag, style: McText.sans(size: 10, weight: FontWeight.w700, color: tagColor)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('做多现货 + 做空永续', style: McText.sans(size: 10, color: McColors.outline)),
          const SizedBox(height: 12),
          Text(apy, style: McText.mono(size: 24, weight: FontWeight.w900, color: McColors.tertiary)),
          Text('预期 APY',
              style: McText.sans(size: 10, weight: FontWeight.w500, color: McColors.tertiary.withValues(alpha: 0.8))),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: _hairlineSoft))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(rate, style: McText.mono(size: 10, color: McColors.outline)),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(depth, style: McText.mono(size: 10, weight: FontWeight.w600, color: McColors.secondary)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- Module 3: 全网费率 7D 走势 ----
  Widget _buildTrend() {
    return McCard(
      color: McColors.surfaceContainer,
      padding: const EdgeInsets.all(20),
      radius: 16,
      child: Column(
        children: [
          SizedBox(
            height: 100,
            width: double.infinity,
            child: CustomPaint(painter: _FundingTrendPainter(_trendRates)),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: _hairlineSoft))),
            child: Builder(builder: (context) {
              // 近 7 天真实日期刻度 (曲线为示意, 日期不再硬编码)
              String md(DateTime d) =>
                  '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
              final now = DateTime.now();
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(md(now.subtract(const Duration(days: 6))),
                      style: McText.mono(size: 11, color: McColors.outline)),
                  Text(md(now.subtract(const Duration(days: 4))),
                      style: McText.mono(size: 11, color: McColors.outline)),
                  Text(md(now.subtract(const Duration(days: 2))),
                      style: McText.mono(size: 11, color: McColors.outline)),
                  Text('今日 (${md(now)})',
                      style: McText.mono(size: 11, weight: FontWeight.w700, color: McColors.primary)),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  // ---- Module 4: 全市场主流永续费率矩阵 ----
  Widget _buildMatrix() {
    return McCard(
      color: McColors.surfaceContainer,
      padding: const EdgeInsets.all(20),
      radius: 16,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('全市场主流永续费率矩阵',
                  style: McText.sans(size: 15, weight: FontWeight.w700, color: Colors.white)),
              Text('已聚合主流3大所', style: McText.mono(size: 11, color: McColors.outline)),
            ],
          ),
          const SizedBox(height: 16),
          // Filter pills
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: McColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _hairline),
            ),
            child: Row(
              children: [
                Expanded(child: _filterPill('正费率 (多头拥挤)', 'pos')),
                Expanded(child: _filterPill('负费率 (空头拥挤)', 'neg')),
                _filterPill('异动激增', 'hot'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Column headers
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(flex: 4, child: Text('交易对 / 现价', style: McText.sans(size: 11, weight: FontWeight.w500, color: McColors.outline))),
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      Text('8H费率 (三所聚合)', style: McText.sans(size: 11, weight: FontWeight.w500, color: McColors.outline)),
                      Text('BIN / OKX / BYB', style: McText.mono(size: 9, color: McColors.outline.withValues(alpha: 0.8))),
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text('年化 / 状态', style: McText.sans(size: 11, weight: FontWeight.w500, color: McColors.outline)),
                  ),
                ),
              ],
            ),
          ),
          // 按筛选过滤
          Builder(builder: (context) {
            final visible = _rows.where((r) {
              switch (_filter) {
                case 'pos':
                  return r.rateNum > 0;
                case 'neg':
                  return r.rateNum < 0;
                case 'hot':
                  return r.rateNum.abs() >= 0.03;
                default:
                  return true;
              }
            }).toList();
            if (visible.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text('该分类下暂无合约',
                      style: McText.sans(size: 12, color: McColors.outline)),
                ),
              );
            }
            return Column(
              children: [
                for (var i = 0; i < visible.length; i++)
                  _matrixRow(visible[i], showDivider: i < visible.length - 1),
              ],
            );
          }),
          const SizedBox(height: 8),
          // Expand button
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _expanding ? null : _toggleExpand,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: McColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _hairline),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _expanding
                        ? '加载中...'
                        : _expanded
                            ? '收起额外合约'
                            : '展开更多合约费率',
                    style: McText.sans(size: 12, weight: FontWeight.w600, color: McColors.onSurfaceVariant)),
                  const SizedBox(width: 6),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16, color: McColors.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterPill(String label, String value) {
    final active = _filter == value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _filter = active ? '' : value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: active ? McColors.surfaceContainerHighest : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: McText.sans(
            size: 12,
            weight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? McColors.primary : McColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  // 额外展开的合约 (失败的不出现, 已有 6 个不重复).
  static const _extraSymbols = [
    'BNB', 'ADA', 'AVAX', 'LINK', 'LTC', 'NEAR', 'TON', 'APT',
  ];

  Future<void> _toggleExpand() async {
    if (_expanded) {
      setState(() {
        _expanded = false;
        _rows = _rows
            .where((r) => !_extraSymbols.contains(r.symbol))
            .toList();
      });
      return;
    }
    setState(() => _expanding = true);
    await Future.wait([for (final s in _extraSymbols) _fetchExtra(s)]);
    if (!mounted) return;
    setState(() {
      _expanding = false;
      _expanded = true;
    });
  }

  // 拉取额外 symbol: 成功才追加 (appendOnly, 不覆盖已有行).
  Future<void> _fetchExtra(String symbol) async {
    try {
      final resp =
          await McData.overview('funding/exchange-rates?symbol=$symbol');
      final cached = _priceBySymbol[symbol];
      final parsed = _parseExchangeRates(symbol, resp['data'],
          fallbackPrice: cached != null ? _fmtPrice(cached) : '--');
      if (parsed == null || !mounted) return;
      final (row, _) = parsed;
      setState(() {
        if (_rows.any((r) => r.symbol == symbol)) return;
        _rows = _sorted([..._rows, row]);
      });
    } catch (_) {
      // 上游无该 symbol / 网络异常 — 跳过.
    }
  }

  Widget _matrixRow(_FundingRow r, {bool showDivider = true}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        border: showDivider ? const Border(bottom: BorderSide(color: _hairlineSoft)) : null,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(r.symbol, style: McText.sans(size: 14, weight: FontWeight.w700, color: Colors.white)),
                    const SizedBox(width: 4),
                    Text('/USDT', style: McText.mono(size: 10, color: McColors.outline)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(r.price, style: McText.mono(size: 12, color: McColors.onSurfaceVariant)),
              ],
            ),
          ),
          Expanded(
            flex: 5,
            child: Column(
              children: [
                Text(r.rate, style: McText.mono(size: 14, weight: FontWeight.w700, color: r.rateColor)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(r.sub[0], style: McText.mono(size: 11, color: r.subColor)),
                      Text(' / ', style: McText.mono(size: 11, color: McColors.outline)),
                      Text(r.sub[1], style: McText.mono(size: 11, color: r.subColor)),
                      Text(' / ', style: McText.mono(size: 11, color: McColors.outline)),
                      Text(r.sub[2], style: McText.mono(size: 11, color: r.subColor)),
                    ],
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
                Text(r.apy, style: McText.mono(size: 14, weight: FontWeight.w700, color: r.apyColor)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: r.statusBg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: r.statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    r.status,
                    style: McText.sans(
                      size: 10,
                      weight: r.statusBold ? FontWeight.w700 : FontWeight.w500,
                      color: r.statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 费率矩阵行的不可变数据模型 (mock 与真实数据共用).
class _FundingRow {
  const _FundingRow({
    required this.symbol,
    required this.price,
    required this.rate,
    required this.rateColor,
    required this.sub,
    required this.subColor,
    required this.apy,
    required this.apyColor,
    required this.status,
    required this.statusColor,
    required this.statusBg,
    required this.statusBold,
    this.rateNum = 0,
    this.showDivider = true,
  });

  final String symbol;
  final String price;
  final String rate;
  final Color rateColor;
  final List<String> sub;
  final Color subColor;
  final String apy;
  final Color apyColor;
  final String status;
  final Color statusColor;
  final Color statusBg;
  final bool statusBold;
  final double rateNum; // 原始费率百分数, 筛选用
  final bool showDivider;

  _FundingRow copyWith({String? price}) => _FundingRow(
        symbol: symbol,
        price: price ?? this.price,
        rate: rate,
        rateColor: rateColor,
        sub: sub,
        subColor: subColor,
        apy: apy,
        apyColor: apyColor,
        status: status,
        statusColor: statusColor,
        statusBg: statusBg,
        statusBold: statusBold,
        rateNum: rateNum,
        showDivider: showDivider,
      );
}

/// 7D funding-rate trend: dashed zero baseline + gradient area + glowing endpoint.
/// rates 为真实 8H 费率序列 (百分数, 升序); 空则回退设计稿示意曲线.
class _FundingTrendPainter extends CustomPainter {
  _FundingTrendPainter(this.rates);

  final List<double> rates;

  // (x fraction, y up 0..1) sampled from the SVG path in home_funding.html.
  static const _fallbackPts = [
    Offset(0.0, 0.388),
    Offset(0.118, 0.576),
    Offset(0.235, 0.506),
    Offset(0.471, 0.694),
    Offset(0.706, 0.459),
    Offset(0.838, 0.647),
    Offset(1.0, 0.812),
  ];
  static const _fallbackBaseline = 0.341; // zero axis (y=56 of 85, flipped)

  // 真实序列 -> 归一化点 + 零轴位置 (费率含 0 于值域内).
  (List<Offset>, double) _build() {
    if (rates.length < 2) return (_fallbackPts, _fallbackBaseline);
    var lo = rates.reduce((a, b) => a < b ? a : b);
    var hi = rates.reduce((a, b) => a > b ? a : b);
    if (lo > 0) lo = 0;
    if (hi < 0) hi = 0;
    final range = hi - lo == 0 ? 1.0 : hi - lo;
    // 留 5% 上下边距
    Offset pt(int i) {
      final y = (rates[i] - lo) / range * 0.9 + 0.05;
      return Offset(i / (rates.length - 1), y);
    }

    final pts = [for (var i = 0; i < rates.length; i++) pt(i)];
    final baseline = ((0 - lo) / range * 0.9 + 0.05).clamp(0.0, 1.0);
    return (pts, baseline);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final (pts, baseline) = _build();
    Offset map(Offset p) => Offset(p.dx * size.width, (1 - p.dy) * size.height);

    final linePath = Path()..moveTo(map(pts.first).dx, map(pts.first).dy);
    for (var i = 1; i < pts.length; i++) {
      final m = map(pts[i]);
      linePath.lineTo(m.dx, m.dy);
    }

    // Gradient area fill down to baseline.
    final baseY = (1 - baseline) * size.height;
    final areaPath = Path.from(linePath)
      ..lineTo(size.width, baseY)
      ..lineTo(0, baseY)
      ..close();
    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          McColors.tertiary.withValues(alpha: 0.35),
          McColors.primaryContainer.withValues(alpha: 0.12),
          McColors.primaryContainer.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.7, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(areaPath, areaPaint);

    // Dashed zero baseline.
    final dashPaint = Paint()
      ..color = McColors.outline
      ..strokeWidth = 1;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, baseY), Offset(x + 3, baseY), dashPaint);
      x += 6;
    }

    // Trend line.
    final linePaint = Paint()
      ..color = McColors.tertiary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    // Glowing endpoint.
    final end = map(pts.last);
    canvas.drawCircle(
      end,
      7,
      Paint()
        ..color = McColors.tertiary.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(end, 4, Paint()..color = McColors.tertiary);
  }

  @override
  bool shouldRepaint(_FundingTrendPainter old) => old.rates != rates;
}

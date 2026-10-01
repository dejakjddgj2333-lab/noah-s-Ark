import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/api.dart';
import '../services/data.dart';

/// 资金费率 (Funding Rate) content body.
///
/// 费率矩阵与全网加权指数尝试接 `/api/market-overview/funding/exchange-rates`
/// (BTC, 可选 ETH); 失败(未配置 CoinGlass/上游错误/后端未启动)时静默保留
/// 内置 mock, 永不红屏.
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

  // 全网加权指数 (BTC 行均值): 首屏展示 mock.
  String _indexApy = '+12.45%';
  String _indexRate8h = '0.0114% / 8h';

  // 费率矩阵行: 首屏展示 mock, 成功后按 symbol 覆盖.
  late List<_FundingRow> _rows = _mockRows();

  static List<_FundingRow> _mockRows() => const [
        _FundingRow(
          symbol: 'DOGE',
          price: '\$0.1842',
          rate: '+0.0450%',
          rateColor: McColors.tertiary,
          sub: ['0.045', '0.042', '0.048'],
          subColor: McColors.tertiary,
          apy: '+49.2%',
          apyColor: McColors.tertiary,
          status: '多头过热',
          statusColor: _error,
          statusBg: Color(0x664E0002),
          statusBold: true,
        ),
        _FundingRow(
          symbol: 'SOL',
          price: '\$148.65',
          rate: '+0.0210%',
          rateColor: McColors.tertiary,
          sub: ['0.021', '0.020', '0.022'],
          subColor: McColors.tertiary,
          apy: '+22.9%',
          apyColor: McColors.tertiary,
          status: '适度看多',
          statusColor: McColors.tertiary,
          statusBg: Color(0x66005A34),
          statusBold: true,
        ),
        _FundingRow(
          symbol: 'BTC',
          price: '\$67,820.0',
          rate: '+0.0100%',
          rateColor: McColors.primary,
          sub: ['0.010', '0.010', '0.010'],
          subColor: McColors.primary,
          apy: '+10.9%',
          apyColor: McColors.primary,
          status: '基准平稳',
          statusColor: McColors.onSurfaceVariant,
          statusBg: McColors.surfaceContainerHigh,
          statusBold: false,
        ),
        _FundingRow(
          symbol: 'ETH',
          price: '\$3,524.4',
          rate: '+0.0085%',
          rateColor: McColors.onSurface,
          sub: ['0.008', '0.009', '0.008'],
          subColor: McColors.outline,
          apy: '+9.3%',
          apyColor: McColors.onSurface,
          status: '中性温和',
          statusColor: McColors.onSurfaceVariant,
          statusBg: McColors.surfaceContainerHigh,
          statusBold: false,
        ),
        _FundingRow(
          symbol: 'XRP',
          price: '\$2.0413',
          rate: '+0.0092%',
          rateColor: McColors.primary,
          sub: ['0.009', '0.010', '0.009'],
          subColor: McColors.primary,
          apy: '+10.1%',
          apyColor: McColors.primary,
          status: '基准平稳',
          statusColor: McColors.onSurfaceVariant,
          statusBg: McColors.surfaceContainerHigh,
          statusBold: false,
        ),
        _FundingRow(
          symbol: 'XTZ',
          price: '\$0.842',
          rate: '-0.0320%',
          rateColor: _error,
          sub: ['-0.032', '-0.030', '-0.035'],
          subColor: _error,
          apy: '-35.0%',
          apyColor: _error,
          status: '空头拥挤',
          statusColor: _error,
          statusBg: Color(0x664E0002),
          statusBold: true,
          showDivider: false,
        ),
      ];

  // ---- Module 4 matrix rows: BTC/ETH/SOL/XRP/DOGE/XTZ 费率已接线, 现价由 tickers 填充 ----

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 各 symbol 独立并行尝试, 任一失败不影响其它与已有 mock.
    await Future.wait([
      _fetchSymbol('BTC'),
      _fetchSymbol('ETH'),
      _fetchSymbol('SOL'),
      _fetchSymbol('XRP'),
      _fetchSymbol('DOGE'),
      _fetchSymbol('XTZ'),
      _loadPrices(),
    ]);
  }

  // 现价: funding 接口不带现价, 用 OKX tickers 按 symbol 覆盖每行价格.
  // 失败静默保留现有 (mock) 价格.
  Future<void> _loadPrices() async {
    try {
      final tickers = await McData.tickers(instType: 'SWAP');
      final bySymbol = {for (final t in tickers) t.symbol: t};
      if (!mounted) return;
      setState(() {
        _rows = [
          for (final r in _rows)
            if (bySymbol.containsKey(r.symbol))
              r.copyWith(price: _fmtPrice(bySymbol[r.symbol]!.last))
            else
              r,
        ];
      });
    } catch (_) {
      // 现价接口失败 — 保留现有价格.
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
      // 接口无现价字段: 沿用现有价格, 真实现价由 _loadPrices 统一覆盖.
      final existing = _rows.where((r) => r.symbol == symbol);
      final parsed = _parseExchangeRates(
          symbol, resp['data'],
          fallbackPrice: existing.isEmpty ? '--' : existing.first.price);
      if (parsed == null || !mounted) return;
      final (row, avgRate) = parsed;
      setState(() {
        _rows = [
          for (final r in _rows)
            if (r.symbol == symbol) row else r,
        ];
        if (symbol == 'BTC' && avgRate != null) {
          _indexRate8h = '${_fmtRate(avgRate, signed: false)} / 8h';
          _indexApy = _fmtApy(avgRate);
        }
      });
    } on ApiException {
      // 503 未配置 / 502 上游错误 — 保留 mock.
    } catch (_) {
      // 网络/解析异常 — 保留 mock.
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
        children: [
          _buildIndexCard(),
          const SizedBox(height: 24),
          _buildArbitrage(),
          const SizedBox(height: 24),
          _buildTrend(),
          const SizedBox(height: 24),
          _buildMatrix(),
          const SizedBox(height: 16),
          _buildFooter(),
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
                      child: Text('健康多头·温和溢价',
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
                    child: Text('03:24:15',
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
                    // Cursor at 56%
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final left = constraints.maxWidth * 0.56 - 7;
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

  // ---- Module 2: 期现套利年化推荐 ----
  Widget _buildArbitrage() {
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
              Text('无常风险对冲', style: McText.sans(size: 12, weight: FontWeight.w500, color: McColors.outline)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _arbCard(
                symbol: 'DOGE',
                tag: '首推',
                tagColor: McColors.tertiary,
                tagBg: const Color(0xFF005A34).withValues(alpha: 0.4),
                apy: '+31.20%',
                rate: '8H: 0.028%',
                depth: '深度 \$1.4M',
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _arbCard(
                symbol: 'SUI',
                tag: '稳定',
                tagColor: McColors.primary,
                tagBg: McColors.primaryContainer.withValues(alpha: 0.3),
                apy: '+24.80%',
                rate: '8H: 0.022%',
                depth: '深度 \$860K',
              ),
            ),
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
            child: CustomPaint(painter: _FundingTrendPainter()),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: _hairlineSoft))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('04-09 (周三)', style: McText.mono(size: 11, color: McColors.outline)),
                Text('04-11', style: McText.mono(size: 11, color: McColors.outline)),
                Text('04-13', style: McText.mono(size: 11, color: McColors.outline)),
                Text('今日 (04-15)',
                    style: McText.mono(size: 11, weight: FontWeight.w700, color: McColors.primary)),
              ],
            ),
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
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: McColors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '正费率 (多头拥挤)',
                      textAlign: TextAlign.center,
                      style: McText.sans(size: 12, weight: FontWeight.w700, color: McColors.primary),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Text(
                      '负费率 (空头拥挤)',
                      textAlign: TextAlign.center,
                      style: McText.sans(size: 12, weight: FontWeight.w500, color: McColors.onSurfaceVariant),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    '异动激增',
                    textAlign: TextAlign.center,
                    style: McText.sans(size: 12, weight: FontWeight.w500, color: McColors.onSurfaceVariant),
                  ),
                ),
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
          for (var i = 0; i < _rows.length; i++)
            _matrixRow(_rows[i], showDivider: i < _rows.length - 1),
          const SizedBox(height: 8),
          // Expand button
          Container(
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
                Text('展开全网 128 个合约费率',
                    style: McText.sans(size: 12, weight: FontWeight.w600, color: McColors.onSurfaceVariant)),
                const SizedBox(width: 6),
                const Icon(Icons.expand_more, size: 16, color: McColors.onSurfaceVariant),
              ],
            ),
          ),
        ],
      ),
    );
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

  // ---- Footer system indicators ----
  Widget _buildFooter() {
    return Padding(
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
                  const McGlowDot(color: McColors.tertiary, size: 8),
                  const SizedBox(width: 8),
                  Text('WS: 12ms / 39 Exchanges Ingestion',
                      style: McText.mono(size: 11, color: McColors.outline)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Row(
              children: [
                const Icon(Icons.verified_user,
                    size: 14, color: McColors.primary),
                const SizedBox(width: 6),
                Text('无滑点智能费率路由',
                    style: McText.mono(
                        size: 11, color: McColors.onSurfaceVariant)),
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
        showDivider: showDivider,
      );
}

/// 7D funding-rate trend: dashed zero baseline + gradient area + glowing endpoint.
class _FundingTrendPainter extends CustomPainter {
  // (x fraction, y up 0..1) sampled from the SVG path in home_funding.html.
  static const _pts = [
    Offset(0.0, 0.388),
    Offset(0.118, 0.576),
    Offset(0.235, 0.506),
    Offset(0.471, 0.694),
    Offset(0.706, 0.459),
    Offset(0.838, 0.647),
    Offset(1.0, 0.812),
  ];
  static const _baseline = 0.341; // zero axis (y=56 of 85, flipped)

  @override
  void paint(Canvas canvas, Size size) {
    Offset map(Offset p) => Offset(p.dx * size.width, (1 - p.dy) * size.height);

    final linePath = Path()..moveTo(map(_pts.first).dx, map(_pts.first).dy);
    for (var i = 1; i < _pts.length; i++) {
      final m = map(_pts[i]);
      linePath.lineTo(m.dx, m.dy);
    }

    // Gradient area fill down to baseline.
    final baseY = (1 - _baseline) * size.height;
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
    final end = map(_pts.last);
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
  bool shouldRepaint(_FundingTrendPainter old) => false;
}

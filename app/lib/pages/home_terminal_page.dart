import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/data.dart';

/// 综合 / 多维指数 terminal board.
/// Reference: stitch_ref/home_terminal.html (content body only).
class HomeTerminalPage extends StatefulWidget {
  const HomeTerminalPage({super.key});

  static const _amber = Color(0xFFF59E0B);

  @override
  State<HomeTerminalPage> createState() => _HomeTerminalPageState();
}

class _HomeTerminalPageState extends State<HomeTerminalPage> {
  // 情绪指数 (mock 默认, 拉取成功后覆盖).
  int _fgValue = 74;
  String _fgLabel = '贪婪 (Greed)';
  Color _fgColor = McColors.bull;

  // 爆仓监控 (mock 默认).
  String _liqTotal = '\$3.82 亿';
  int _liqLongPct = 56;
  String _liqLongText = '多头爆仓 \$2.14 亿 (56%)';
  String _liqShortText = '空头爆仓 \$1.68 亿 (44%)';

  // 资金费率加权 (mock 默认).
  String _fundingValue = '+0.0125%';
  Color _fundingColor = McColors.bull;

  // 山寨季指数 (mock 默认, altcoin_season 拉取成功后覆盖).
  String _altSeasonValue = '38';
  double _altSeasonFrac = 0.38;
  String _altSeasonFooter = '距山寨爆发差 37 点';

  // 市占率分布 (mock 默认, btc/eth dominance 拉取成功后覆盖).
  String _btcDom = '56.4%';
  String _ethDom = '14.8%';
  String _otherDom = '28.8%';
  double _btcDomFrac = 0.564;
  double _ethDomFrac = 0.148;

  @override
  void initState() {
    super.initState();
    // 不阻塞首帧: 立即渲染 mock, 成功后再 setState 覆盖.
    Future.wait([
      _loadSentiment(),
      _loadLiquidations(),
      _loadFunding(),
      _loadIndicators(),
      _loadDominance(),
    ]);
  }

  Future<void> _loadIndicators() async {
    try {
      final resp = await McData.overview('indicators');
      final list = resp['indicators'];
      if (list is! List || !mounted) return;
      for (final e in list) {
        if (e is! Map) continue;
        if (e['key'] != 'altcoin_season') continue;
        final v = e['value'];
        if (v is! num) continue;
        final chg = e['change_1d'];
        final val = v.toDouble();
        setState(() {
          _altSeasonValue = val.round().toString();
          _altSeasonFrac = (val / 100).clamp(0.0, 1.0);
          _altSeasonFooter = chg is num
              ? '24H ${chg >= 0 ? '+' : ''}${chg.toStringAsFixed(0)} 点'
              : _altSeasonFooter;
        });
      }
    } catch (_) {/* 保留 mock */}
  }

  Future<void> _loadDominance() async {
    try {
      final g = await McData.globalStats();
      if (!mounted) return;
      final btc = g.btcDominance;
      final eth = g.ethDominance;
      if (btc == null && eth == null) return;
      setState(() {
        if (btc != null) {
          _btcDom = '${btc.toStringAsFixed(1)}%';
          _btcDomFrac = (btc / 100).clamp(0.0, 1.0);
        }
        if (eth != null) {
          _ethDom = '${eth.toStringAsFixed(1)}%';
          _ethDomFrac = (eth / 100).clamp(0.0, 1.0);
        }
        final other = (100 - (_btcDomFrac + _ethDomFrac) * 100).clamp(0.0, 100.0);
        _otherDom = '${other.toStringAsFixed(1)}%';
      });
    } catch (_) {/* 保留 mock */}
  }

  Future<void> _loadSentiment() async {
    try {
      final resp = await McData.overview('sentiment');
      final v = _parseFearGreed(resp);
      if (v == null || !mounted) return;
      setState(() {
        _fgValue = v;
        _fgLabel = _fgLabelFor(v);
        _fgColor = _fgColorFor(v);
      });
    } catch (_) {/* 未配置 / 上游错误 -> 保留 mock */}
  }

  Future<void> _loadLiquidations() async {
    try {
      final resp =
          await McData.overview('liquidations/exchange-list?range=24h');
      final r = _parseLiquidations(resp);
      if (r == null || !mounted) return;
      final total = r[0], longUsd = r[1], shortUsd = r[2];
      final longPct = total > 0 ? (longUsd / total * 100).round() : 50;
      setState(() {
        _liqTotal = _usdToYi(total);
        _liqLongPct = longPct;
        _liqLongText = '多头爆仓 ${_usdToYi(longUsd)} ($longPct%)';
        _liqShortText = '空头爆仓 ${_usdToYi(shortUsd)} (${100 - longPct}%)';
      });
    } catch (_) {/* 保留 mock */}
  }

  Future<void> _loadFunding() async {
    try {
      final resp = await McData.overview('funding/exchange-rates?symbol=BTC');
      final avg = _parseFunding(resp);
      if (avg == null || !mounted) return;
      setState(() {
        _fundingValue = '${avg >= 0 ? '+' : ''}${avg.toStringAsFixed(4)}%';
        _fundingColor = avg >= 0 ? McColors.bull : McColors.bear;
      });
    } catch (_) {/* 保留 mock */}
  }

  // ---- 解析 (对后端返回结构宽容, 失败返回 null -> 保留 mock) ----

  static int? _parseFearGreed(Map<String, dynamic> resp) {
    final n = _deepNum(
      resp,
      (k) {
        final lk = k.toLowerCase();
        return lk == 'value' ||
            lk == 'fgi' ||
            lk.contains('fear') ||
            lk.contains('greed');
      },
      (v) => v >= 0 && v <= 100,
    );
    return n?.round();
  }

  /// 返回 [totalUsd, longUsd, shortUsd]; 无法得到有效多空合计时返回 null.
  static List<double>? _parseLiquidations(Map<String, dynamic> resp) {
    final data = resp['data'];
    if (data is! List) return null;
    double longUsd = 0, shortUsd = 0;
    for (final e in data) {
      if (e is! Map) continue;
      // 跳过 All 聚合行, 避免重复计数
      if ((e['exchange'] ?? '').toString().toLowerCase() == 'all') continue;
      num numOf(dynamic v) => v is num ? v : (num.tryParse('$v') ?? 0);
      longUsd += numOf(e['longLiquidation_usd'] ?? e['longLiquidationUsd']);
      shortUsd += numOf(e['shortLiquidation_usd'] ?? e['shortLiquidationUsd']);
    }
    if (longUsd <= 0 || shortUsd <= 0) return null;
    return [longUsd + shortUsd, longUsd, shortUsd];
  }

  static double? _parseFunding(Map<String, dynamic> resp) {
    final rates = <num>[];
    _collect(resp, (k) {
      final lk = k.toLowerCase();
      return lk.contains('fundingrate') ||
          lk == 'funding_rate' ||
          lk == 'rate';
    }, rates);
    if (rates.isEmpty) return null;
    return rates.fold<double>(0, (a, b) => a + b) / rates.length;
  }

  static num? _deepNum(
      dynamic node, bool Function(String key) match, bool Function(num v) valid) {
    if (node is Map) {
      for (final e in node.entries) {
        final k = e.key;
        if (k is String && match(k)) {
          final v = e.value;
          final n = v is num ? v : num.tryParse('$v');
          if (n != null && valid(n)) return n;
        }
      }
      for (final e in node.entries) {
        final r = _deepNum(e.value, match, valid);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (final item in node) {
        final r = _deepNum(item, match, valid);
        if (r != null) return r;
      }
    }
    return null;
  }

  static void _collect(
      dynamic node, bool Function(String key) match, List<num> out) {
    if (node is Map) {
      for (final e in node.entries) {
        final k = e.key;
        if (k is String && match(k)) {
          final v = e.value;
          final n = v is num ? v : num.tryParse('$v');
          if (n != null) out.add(n);
        }
        _collect(e.value, match, out);
      }
    } else if (node is List) {
      for (final item in node) {
        _collect(item, match, out);
      }
    }
  }

  static String _usdToYi(double usd) => '\$${(usd / 1e8).toStringAsFixed(2)} 亿';

  static String _fgLabelFor(int v) {
    if (v < 25) return '极度恐惧 (Extreme Fear)';
    if (v < 45) return '恐惧 (Fear)';
    if (v < 55) return '中性 (Neutral)';
    if (v < 75) return '贪婪 (Greed)';
    return '极度贪婪 (Extreme Greed)';
  }

  static Color _fgColorFor(int v) {
    if (v < 45) return McColors.bear;
    if (v < 55) return HomeTerminalPage._amber;
    return McColors.bull;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 32),
      children: [
        // 1. 核心情绪与宏观双子盘 (自然高度, IntrinsicHeight 与 Expanded 基线冲突)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
                child: _FearGreedCard(
                    value: _fgValue, label: _fgLabel, color: _fgColor)),
            const SizedBox(width: 10),
            Expanded(
                child: _DominanceCard(
              btc: _btcDom,
              eth: _ethDom,
              other: _otherDom,
              btcFrac: _btcDomFrac,
              ethFrac: _ethDomFrac,
            )),
          ],
        ),
        const SizedBox(height: 16),

        // 2. 市场深度量化指标矩阵
        const McSectionHeader(
          title: '市场深度量化指标矩阵',
          trailing: '6 个核心模型实时计算',
        ),
        const SizedBox(height: 10),
        _matrixGrid(),
        const SizedBox(height: 16),

        // 3. 24H 全网多空爆仓实时监控
        _LiquidationCard(
          total: _liqTotal,
          longPct: _liqLongPct,
          longText: _liqLongText,
          shortText: _liqShortText,
        ),
        const SizedBox(height: 16),

        // 4. 链上巨鲸与做市异动雷达
        const _WhaleSection(),
        const SizedBox(height: 16),

        // 5. 主流资产多维量化指标一览
        const McSectionHeader(
          title: '主流资产多维量化指标一览',
          icon: Icons.trending_up,
          trailing: '24H 实时监控',
        ),
        const SizedBox(height: 10),
        const _AssetListCard(),
        const SizedBox(height: 16),

        // 6. 底部终端微状态栏
        const _TerminalStatusBar(),
      ],
    );
  }

  Widget _matrixGrid() {
    final cards = [
      _MatrixCard(
        title: '山寨季指数',
        pill: const McPill('BTC Season', color: McColors.primarySoft, bold: false),
        value: _altSeasonValue,
        suffix: '/100',
        valueColor: McColors.onSurface,
        fraction: _altSeasonFrac,
        barColor: McColors.primaryContainer,
        footer: _altSeasonFooter,
        footerColor: McColors.onSurfaceVariant,
      ),
      const _MatrixCard(
        title: '全网未平仓合约',
        pill: McPill('+4.15%', color: McColors.bull),
        value: '\$89.4B',
        valueColor: McColors.onSurface,
        fraction: 0.68,
        barColor: McColors.bull,
        footer: '24h 增量资金强劲流入',
        footerColor: McColors.bull,
      ),
      _MatrixCard(
        title: '资金费率加权',
        pill: McPill('适度偏多', color: _fundingColor, bold: false),
        value: _fundingValue,
        valueColor: _fundingColor,
        fraction: 0.48,
        barColor: const Color(0xCC00E388),
        footer: '全网多头适度杠杆配置',
        footerColor: McColors.onSurfaceVariant,
      ),
      const _MatrixCard(
        title: '现货累计买卖差',
        pill: McPill('看涨支撑', color: McColors.primarySoft, bold: false),
        value: '+\$382M',
        valueColor: McColors.onSurface,
        fraction: 0.62,
        barColor: McColors.primaryContainer,
        footer: '主力主动吃单净流入',
        footerColor: McColors.onSurfaceVariant,
      ),
      const _MatrixCard(
        title: '稳定币供给指数',
        pill: McPill('7D +\$1.8B', color: McColors.bull, bold: false),
        value: '\$168.5B',
        valueColor: McColors.onSurface,
        fraction: 0.78,
        barColor: McColors.bull,
        footer: '场外资金流动性充足',
        footerColor: McColors.onSurfaceVariant,
      ),
      const _MatrixCard(
        title: '多空人数比 (L/S)',
        pill: McPill('散户偏多', color: McColors.primarySoft, bold: false),
        value: '1.28',
        valueColor: McColors.onSurface,
        fraction: 0.56,
        barColor: McColors.primaryContainer,
        restColor: Color(0xB3FF6363),
        footer: '散户多方聚集 · 顶部分歧',
        footerColor: McColors.onSurfaceVariant,
      ),
    ];
    return Column(
      children: [
        for (var i = 0; i < cards.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cards[i]),
              const SizedBox(width: 10),
              Expanded(child: cards[i + 1]),
            ],
          ),
        ],
      ],
    );
  }
}

/// 恐惧与贪婪指数卡片.
class _FearGreedCard extends StatelessWidget {
  const _FearGreedCard(
      {required this.value, required this.label, required this.color});

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return McCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.psychology,
                      size: 15, color: McColors.primaryContainer),
                  const SizedBox(width: 4),
                  Text(
                    '情绪指数',
                    style: McText.sans(
                      size: 12,
                      weight: FontWeight.w500,
                      color: McColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const McPill('+4 较昨日', color: McColors.bull, fontSize: 10),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('$value',
                        style: McText.display(size: 24, weight: FontWeight.w700)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: McText.sans(
                            size: 12,
                            weight: FontWeight.w600,
                            color: color),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 仪表分段进度条 (5 segments)
                Container(
                  height: 6,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: McColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Row(
                    children: [
                      _seg(const Color(0x66FF6363)),
                      _seg(const Color(0xB3FF6363)),
                      _seg(HomeTerminalPage._amber.withValues(alpha: 0.6)),
                      _seg(McColors.primaryContainer, glow: true),
                      _seg(McColors.surfaceVariant.withValues(alpha: 0.4)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('昨日 68 · 贪婪',
                  style: McText.mono(
                      size: 12, color: McColors.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text('上周 62 · 中性',
                  style: McText.mono(
                      size: 12, color: McColors.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _seg(Color color, {bool glow = false}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            boxShadow: glow
                ? [
                    BoxShadow(
                      color: McColors.primaryContainer.withValues(alpha: 0.8),
                      blurRadius: 8,
                    )
                  ]
                : null,
          ),
        ),
      ),
    );
  }
}

/// 全网市占率分布卡片.
class _DominanceCard extends StatelessWidget {
  const _DominanceCard({
    required this.btc,
    required this.eth,
    required this.other,
    required this.btcFrac,
    required this.ethFrac,
  });

  final String btc;
  final String eth;
  final String other;
  final double btcFrac;
  final double ethFrac;

  @override
  Widget build(BuildContext context) {
    final bf = (btcFrac * 1000).round();
    final ef = (ethFrac * 1000).round();
    final of = (1000 - bf - ef).clamp(1, 1000);
    return McCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pie_chart,
                  size: 15, color: McColors.secondary),
              const SizedBox(width: 4),
              Text(
                '市占率分布',
                style: McText.sans(
                  size: 12,
                  weight: FontWeight.w500,
                  color: McColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(btc,
                        style: McText.mono(size: 20, weight: FontWeight.w700)),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text('ETH $eth',
                            style: McText.mono(
                                size: 11, color: McColors.onSurfaceVariant)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 6,
                    child: Row(
                      children: [
                        Expanded(
                          flex: bf,
                          child: Container(
                            decoration: BoxDecoration(
                              color: McColors.primaryContainer,
                              boxShadow: [
                                BoxShadow(
                                  color: McColors.primaryContainer
                                      .withValues(alpha: 0.6),
                                  blurRadius: 6,
                                )
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          flex: ef,
                          child: Container(color: McColors.secondary),
                        ),
                        Expanded(
                          flex: of,
                          child: Container(
                            color: McColors.surfaceVariant.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _legendLine('BTC $btc', McColors.primaryContainer),
              const SizedBox(height: 4),
              _legendLine('ETH $eth', McColors.secondary),
              const SizedBox(height: 4),
              _legendLine('Other $other', McColors.onSurfaceVariant),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendLine(String text, Color color) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(text, style: McText.mono(size: 12, weight: FontWeight.w600, color: color)),
      ],
    );
  }
}

/// 量化指标矩阵单卡.
class _MatrixCard extends StatelessWidget {
  const _MatrixCard({
    required this.title,
    required this.pill,
    required this.value,
    this.suffix,
    required this.valueColor,
    required this.fraction,
    required this.barColor,
    this.restColor,
    required this.footer,
    required this.footerColor,
  });

  final String title;
  final Widget pill;
  final String value;
  final String? suffix;
  final Color valueColor;
  final double fraction;
  final Color barColor;
  final Color? restColor;
  final String footer;
  final Color footerColor;

  @override
  Widget build(BuildContext context) {
    return McCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: McText.sans(
                    size: 12,
                    weight: FontWeight.w500,
                    color: McColors.onSurfaceVariant,
                  ),
                ),
              ),
              pill,
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value,
                          style: McText.mono(
                              size: 20,
                              weight: FontWeight.w700,
                              color: valueColor),
                        ),
                      ),
                    ),
                    if (suffix != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        suffix!,
                        style: McText.mono(
                            size: 11, color: McColors.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                _splitBar(),
              ],
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child:
                Text(footer, style: McText.mono(size: 10, color: footerColor)),
          ),
        ],
      ),
    );
  }

  Widget _splitBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: Row(
          children: [
            Expanded(
              flex: (fraction * 1000).round(),
              child: Container(
                decoration: BoxDecoration(
                  color: barColor,
                  boxShadow: [
                    BoxShadow(color: barColor.withValues(alpha: 0.6),
                        blurRadius: 6)
                  ],
                ),
              ),
            ),
            Expanded(
              flex: ((1 - fraction) * 1000).round(),
              child: Container(
                color: restColor ??
                    McColors.surfaceVariant.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 24H 全网多空爆仓实时监控卡片.
class _LiquidationCard extends StatelessWidget {
  const _LiquidationCard({
    required this.total,
    required this.longPct,
    required this.longText,
    required this.shortText,
  });

  final String total;
  final int longPct;
  final String longText;
  final String shortText;

  @override
  Widget build(BuildContext context) {
    return McCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const McGlowDot(color: McColors.bear, size: 8),
                  const SizedBox(width: 6),
                  Text(
                    '全网多空爆仓实时监控',
                    style: McText.sans(size: 12, weight: FontWeight.w600),
                  ),
                ],
              ),
              Row(
                children: [
                  _timeframeToggle(),
                  const SizedBox(width: 8),
                  Text(
                    total,
                    style: McText.mono(
                        size: 14, weight: FontWeight.w700, color: McColors.bear),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 多空爆仓比例进度条
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
                  flex: longPct,
                  child: Container(
                    decoration: BoxDecoration(
                      color: McColors.bear,
                      borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(4)),
                      boxShadow: [
                        BoxShadow(
                          color: McColors.bear.withValues(alpha: 0.5),
                          blurRadius: 8,
                        )
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: 100 - longPct,
                  child: Container(
                    decoration: BoxDecoration(
                      color: McColors.bull,
                      borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(4)),
                      boxShadow: [
                        BoxShadow(
                          color: McColors.bull.withValues(alpha: 0.5),
                          blurRadius: 8,
                        )
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      const McGlowDot(color: McColors.bear, size: 6),
                      const SizedBox(width: 4),
                      Text(longText,
                          style: McText.mono(size: 11, color: McColors.bear)),
                    ],
                  ),
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    children: [
                      const McGlowDot(color: McColors.bull, size: 6),
                      const SizedBox(width: 4),
                      Text(shortText,
                          style: McText.mono(size: 11, color: McColors.bull)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 最大单笔爆仓标牌
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: McColors.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: McColors.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const McPill('最大单笔', color: McColors.bear, fontSize: 10),
                    const SizedBox(width: 8),
                    Text('Binance - ETHUSDT 永续',
                        style: McText.sans(size: 11)),
                  ],
                ),
                Text(
                  '\$8.50M 强平',
                  style: McText.mono(
                      size: 11, weight: FontWeight.w700, color: McColors.bear),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeframeToggle() {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: McColors.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          _tf('1H', false),
          _tf('4H', false),
          _tf('24H', true),
        ],
      ),
    );
  }

  Widget _tf(String label, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: active ? McColors.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        boxShadow: active
            ? [
                BoxShadow(
                  color: McColors.primaryContainer.withValues(alpha: 0.6),
                  blurRadius: 6,
                )
              ]
            : null,
      ),
      child: Text(
        label,
        style: McText.mono(
          size: 10,
          weight: active ? FontWeight.w700 : FontWeight.w400,
          color: active ? Colors.white : McColors.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 链上巨鲸与做市异动雷达.
class _WhaleSection extends StatelessWidget {
  const _WhaleSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              const Icon(Icons.radar, size: 15, color: McColors.primaryContainer),
              const SizedBox(width: 6),
              Text('链上巨鲸与做市异动雷达',
                  style: McText.sans(size: 12, weight: FontWeight.w600)),
              const Spacer(),
              const McGlowDot(color: McColors.bull, size: 4),
              const SizedBox(width: 4),
              Text('实时同步中',
                  style: McText.mono(size: 10, color: McColors.bull)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const _WhaleCard(
          emoji: '🐋',
          emojiBg: McColors.primaryContainer,
          tag: '提币囤积 (Accumulation)',
          tagColor: McColors.bull,
          time: '3分钟前',
          body: [
            TextSpan(text: '巨鲸地址 '),
            TextSpan(
                text: '0x7a8...9f21',
                style: TextStyle(
                    fontFamily: 'JetBrains Mono', color: McColors.primary)),
            TextSpan(text: ' 从 '),
            TextSpan(
                text: 'Binance',
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: Colors.white)),
            TextSpan(text: ' 提取 '),
            TextSpan(
                text: '1,200 BTC',
                style: TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontWeight: FontWeight.w700,
                    color: McColors.bull)),
            TextSpan(text: ' (\$115.7M) 至冷钱包。'),
          ],
          chips: [
            McChip('强利好吸筹'),
            McChip('Tx: 8f42...a90b'),
          ],
        ),
        const SizedBox(height: 8),
        const _WhaleCard(
          emoji: '⚠️',
          emojiBg: McColors.bear,
          tag: '大额充值 (Potential Sell)',
          tagColor: McColors.bear,
          time: '14分钟前',
          body: [
            TextSpan(text: '某以太坊鲸鱼将 '),
            TextSpan(
                text: '25,000 ETH',
                style: TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontWeight: FontWeight.w700,
                    color: McColors.bear)),
            TextSpan(text: ' (\$85.5M) 从未知钱包充入 '),
            TextSpan(
                text: 'Coinbase',
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: Colors.white)),
            TextSpan(text: ' 交易所。'),
          ],
          chips: [
            McChip('潜在抛压预警', color: McColors.bear),
            McChip('Ethereum Network'),
          ],
        ),
        const SizedBox(height: 8),
        const _WhaleCard(
          emoji: '⚡',
          emojiBg: McColors.primaryContainer,
          tag: '做市机构动向',
          tagColor: McColors.primarySoft,
          time: '28分钟前',
          body: [
            TextSpan(
                text: 'DWF Labs',
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: Colors.white)),
            TextSpan(text: ' 链上向某主流衍生品交易所转入 '),
            TextSpan(
                text: '5,000,000 USDT',
                style: TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontWeight: FontWeight.w700,
                    color: McColors.primary)),
            TextSpan(text: ' 进行流动性做市部署。'),
          ],
          chips: [
            McChip('流动性注入', color: McColors.secondary),
            McChip('TRON Network'),
          ],
        ),
      ],
    );
  }
}

class _WhaleCard extends StatelessWidget {
  const _WhaleCard({
    required this.emoji,
    required this.emojiBg,
    required this.tag,
    required this.tagColor,
    required this.time,
    required this.body,
    required this.chips,
  });

  final String emoji;
  final Color emojiBg;
  final String tag;
  final Color tagColor;
  final String time;
  final List<TextSpan> body;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    return McCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: emojiBg.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: emojiBg.withValues(alpha: 0.3)),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: McPill(tag, color: tagColor, fontSize: 12,
                          bold: true),
                    ),
                    const SizedBox(width: 8),
                    Text(time,
                        style: McText.mono(
                            size: 10, color: McColors.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    style: McText.sans(size: 12, height: 1.5),
                    children: body,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 4, children: chips),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 主流资产多维量化指标一览列表.
class _AssetListCard extends StatelessWidget {
  const _AssetListCard();

  static const _rows = [
    _AssetRow(
      glyph: '₿',
      glyphColor: McColors.primary,
      symbol: 'BTC',
      sub1: '持仓 \$42.5B',
      sub2: '费率 +0.012%',
      sub2Color: McColors.bull,
      spark: [0.20, 0.33, 0.27, 0.53, 0.47, 0.73, 0.67, 0.93],
      sparkColor: McColors.bull,
      price: '\$96,450.00',
      delta: '+3.42%',
      positive: true,
    ),
    _AssetRow(
      glyph: 'Ξ',
      glyphColor: McColors.secondary,
      symbol: 'ETH',
      sub1: '持仓 \$24.8B',
      sub2: '费率 +0.008%',
      sub2Color: McColors.bull,
      spark: [0.13, 0.27, 0.40, 0.33, 0.60, 0.67, 0.87],
      sparkColor: McColors.bull,
      price: '\$3,420.50',
      delta: '+2.18%',
      positive: true,
    ),
    _AssetRow(
      glyph: '◎',
      glyphColor: McColors.primary,
      symbol: 'SOL',
      sub1: '持仓 \$11.2B',
      sub2: '费率 +0.024%',
      sub2Color: McColors.bull,
      spark: [0.07, 0.33, 0.47, 0.40, 0.73, 0.83, 0.93],
      sparkColor: McColors.bull,
      price: '\$194.20',
      delta: '+6.85%',
      positive: true,
    ),
    _AssetRow(
      glyph: '💧',
      glyphColor: McColors.secondary,
      symbol: 'SUI',
      sub1: '持仓 \$3.4B',
      sub2: '费率 -0.005%',
      sub2Color: McColors.bear,
      spark: [0.73, 0.67, 0.40, 0.50, 0.27, 0.33, 0.07],
      sparkColor: McColors.bear,
      price: '\$3.85',
      delta: '-1.24%',
      positive: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: McColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: McColors.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: [
            for (var i = 0; i < _rows.length; i++) ...[
              if (i > 0)
                Divider(
                    height: 1,
                    color: McColors.outlineVariant.withValues(alpha: 0.3)),
              _rows[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _AssetRow extends StatelessWidget {
  const _AssetRow({
    required this.glyph,
    required this.glyphColor,
    required this.symbol,
    required this.sub1,
    required this.sub2,
    required this.sub2Color,
    required this.spark,
    required this.sparkColor,
    required this.price,
    required this.delta,
    required this.positive,
  });

  final String glyph;
  final Color glyphColor;
  final String symbol;
  final String sub1;
  final String sub2;
  final Color sub2Color;
  final List<double> spark;
  final Color sparkColor;
  final String price;
  final String delta;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: McColors.surfaceContainerHigh,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    glyph,
                    style: McText.mono(
                        size: 12, weight: FontWeight.w700, color: glyphColor),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(symbol,
                              style: McText.sans(
                                  size: 14, weight: FontWeight.w700)),
                          const SizedBox(width: 4),
                          Text('/USDT',
                              style: McText.sans(
                                  size: 11,
                                  color: McColors.onSurfaceVariant)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Text(sub1,
                                style: McText.mono(
                                    size: 10,
                                    color: McColors.onSurfaceVariant)),
                            const SizedBox(width: 6),
                            Text(sub2,
                                style:
                                    McText.mono(size: 10, color: sub2Color)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: McSparkline(
                points: spark, color: sparkColor, width: 64, height: 24),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(price,
                  style: McText.mono(size: 12, weight: FontWeight.w700)),
              McDeltaBadge(delta, positive: positive),
            ],
          ),
        ],
      ),
    );
  }
}

/// 底部终端微状态栏.
class _TerminalStatusBar extends StatelessWidget {
  const _TerminalStatusBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: McColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  const McGlowDot(color: McColors.bull, size: 6),
                  const SizedBox(width: 6),
                  Text('WebSocket: 18ms (直连 Tokyo-A)',
                      style: McText.mono(
                          size: 10, color: McColors.onSurfaceVariant)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text('BLOCK #21,498,924',
                style: McText.mono(
                    size: 10,
                    color: McColors.onSurfaceVariant,
                    letterSpacing: 1)),
          ),
        ],
      ),
    );
  }
}

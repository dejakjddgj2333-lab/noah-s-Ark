import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../core/coin_icon.dart';
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

  // 资金费率加权 (mock 默认).
  String _fundingValue = '+0.0125%';
  Color _fundingColor = McColors.bull;
  double _fundingFrac = 0.48;

  // 情绪历史 (近8日, 最新在末位): 昨日/上周行真实值.
  List<int>? _fgHistory;

  // 未平仓合约 (OKX BTC+ETH 永续名义额).
  String _oiValue = '--';

  // 24H 爆仓总额 (OKX/Bybit 自建聚合).
  String _liqTotal = '--';
  String _liqCount = '--';

  // 稳定币总流通 (DefiLlama).
  String _stableValue = '--';
  String _stablePill = '--';

  // 多空人数比 (Binance 全局账户).
  String _lsRatio = '--';
  String _lsFooter = '--';
  double _lsFrac = 0.5;

  // 主流资产列表 (真实行情+费率+走势; null=加载中).
  List<_AssetRow>? _assetRows;

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
      _loadFunding(),
      _loadIndicators(),
      _loadDominance(),
      _loadOpenInterest(),
      _loadLiqTotal(),
      _loadStableSupply(),
      _loadLongShort(),
      _loadAssets(),
    ]);
  }

  Future<void> _loadOpenInterest() async {
    try {
      final resp = await McData.overview('open-interest');
      final v = resp['oi_usd'];
      if (v is! num || !mounted) return;
      setState(() => _oiValue = McData.fmtUsdCompact(v.toDouble()));
    } catch (_) {/* 保留 -- */}
  }

  Future<void> _loadLiqTotal() async {
    try {
      final resp =
          await McData.overview('liquidations/exchange-list?range=24h');
      final list = resp['data'];
      if (list is! List || !mounted) return;
      double total = 0;
      int count = 0;
      for (final e in list) {
        if (e is! Map) continue;
        final v = e['liquidation_usd'];
        if (v is num) total += v.toDouble();
        final c = e['count'];
        if (c is num) count += c.toInt();
      }
      if (total <= 0 && count == 0) return;
      setState(() {
        _liqTotal = total > 0 ? McData.fmtUsdCompact(total) : '--';
        _liqCount = '$count 笔';
      });
    } catch (_) {/* 保留 -- */}
  }

  Future<void> _loadStableSupply() async {
    try {
      final liq = await McData.liquidityOverview();
      if (!mounted || liq.stableTotalUsd == null) return;
      final chg = liq.stableChange1dPct;
      setState(() {
        _stableValue = McData.fmtUsdCompact(liq.stableTotalUsd!);
        _stablePill = chg == null
            ? '24H --'
            : '24H ${chg >= 0 ? '+' : ''}${chg.toStringAsFixed(2)}%';
      });
    } catch (_) {/* 保留 -- */}
  }

  Future<void> _loadLongShort() async {
    try {
      final r = await McData.longShortRatio();
      final long = r.longPct;
      final short = r.shortPct;
      if (long == null || short == null || short == 0 || !mounted) return;
      setState(() {
        _lsRatio = (long / short).toStringAsFixed(2);
        _lsFrac = (long / 100).clamp(0.0, 1.0);
        _lsFooter =
            '多头 ${long.toStringAsFixed(1)}% · 空头 ${short.toStringAsFixed(1)}%';
      });
    } catch (_) {/* 保留 -- */}
  }

  // 主流资产: OKX 行情 + 各所费率均值 + 7D 走势, 四币并行.
  Future<void> _loadAssets() async {
    const symbols = ['BTC', 'ETH', 'SOL', 'SUI'];
    try {
      final tickers = await McData.tickers();
      final rows = await Future.wait(symbols.map((s) async {
        final t = tickers.firstWhere(
          (x) => x.instId == '$s-USDT-SWAP',
          orElse: () => throw StateError('no ticker $s'),
        );
        double? rate;
        try {
          final fr =
              await McData.overview('funding/exchange-rates?symbol=$s');
          rate = _parseFunding(fr);
        } catch (_) {}
        final spark = await McData.sparkline(t.instId).catchError(
            (_) => <double>[]);
        return _AssetRow(
          symbol: s,
          sub1: '成交 ${McData.fmtUsdCompact(t.volCcy24h)}',
          sub2: rate == null
              ? '费率 --'
              : '费率 ${rate >= 0 ? '+' : ''}${rate.toStringAsFixed(3)}%',
          sub2Color:
              rate == null ? McColors.outline : (rate >= 0 ? McColors.bull : McColors.bear),
          spark: spark,
          sparkColor: t.changePct >= 0 ? McColors.bull : McColors.bear,
          price: '\$${t.last >= 1000 ? _fmtInt(t.last) : t.last.toStringAsFixed(2)}',
          delta:
              '${t.changePct >= 0 ? '+' : ''}${t.changePct.toStringAsFixed(2)}%',
          positive: t.changePct >= 0,
        );
      }));
      if (!mounted) return;
      setState(() => _assetRows = rows);
    } catch (_) {/* 加载失败不渲染列表 */}
  }

  static String _fmtInt(double v) {
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
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
      final hist = resp['history'];
      if (!mounted) return;
      setState(() {
        if (v != null) {
          _fgValue = v;
          _fgLabel = _fgLabelFor(v);
          _fgColor = _fgColorFor(v);
        }
        if (hist is List && hist.length >= 2) {
          _fgHistory = hist
              .map((e) => e is num ? e.toInt() : int.tryParse('$e') ?? 0)
              .toList();
        }
      });
    } catch (_) {/* 未配置 / 上游错误 -> 保留 mock */}
  }

  Future<void> _loadFunding() async {
    try {
      final resp = await McData.overview('funding/exchange-rates?symbol=BTC');
      final avg = _parseFunding(resp);
      if (avg == null || !mounted) return;
      setState(() {
        _fundingValue = '${avg >= 0 ? '+' : ''}${avg.toStringAsFixed(4)}%';
        _fundingColor = avg >= 0 ? McColors.bull : McColors.bear;
        // 费率区间 -0.05%..+0.05% 映射进度条
        _fundingFrac = ((avg + 0.05) / 0.1).clamp(0.02, 0.98);
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
        // 1. 情绪指数卡 (整行)
        _FearGreedCard(
            value: _fgValue,
            label: _fgLabel,
            color: _fgColor,
            history: _fgHistory),
        const SizedBox(height: 10),

        // 2. 市占率分布 (独立一块, 饼图)
        _DominancePieCard(
          btc: _btcDom,
          eth: _ethDom,
          other: _otherDom,
          btcFrac: _btcDomFrac,
          ethFrac: _ethDomFrac,
        ),
        const SizedBox(height: 16),

        // 2. 市场深度量化指标矩阵
        const McSectionHeader(
          title: '市场深度量化指标矩阵',
          trailing: '公开数据源实时聚合',
        ),
        const SizedBox(height: 10),
        _matrixGrid(),
        const SizedBox(height: 16),

        // 3. 主流资产多维量化指标一览
        const McSectionHeader(
          title: '主流资产多维量化指标一览',
          icon: Icons.trending_up,
          trailing: 'OKX 行情 · 三所费率',
        ),
        const SizedBox(height: 10),
        _AssetListCard(rows: _assetRows),
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
      _MatrixCard(
        title: '全网未平仓合约',
        pill: const McPill('OKX 永续', color: McColors.primarySoft, bold: false),
        value: _oiValue,
        valueColor: McColors.onSurface,
        fraction: 0.68,
        barColor: McColors.bull,
        footer: 'BTC+ETH 永续名义持仓',
        footerColor: McColors.onSurfaceVariant,
      ),
      _MatrixCard(
        title: '资金费率加权',
        pill: McPill('适度偏多', color: _fundingColor, bold: false),
        value: _fundingValue,
        valueColor: _fundingColor,
        fraction: _fundingFrac,
        barColor: const Color(0xCC00E388),
        footer: 'Binance/OKX/Bybit 均值',
        footerColor: McColors.onSurfaceVariant,
      ),
      _MatrixCard(
        title: '24H 爆仓总额',
        pill: McPill(_liqCount, color: McColors.primarySoft, bold: false),
        value: _liqTotal,
        valueColor: McColors.onSurface,
        fraction: 0.5,
        barColor: const Color(0xB3FF6363),
        footer: 'OKX/Bybit 实时强平聚合',
        footerColor: McColors.onSurfaceVariant,
      ),
      _MatrixCard(
        title: '稳定币供给指数',
        pill: McPill(_stablePill, color: McColors.bull, bold: false),
        value: _stableValue,
        valueColor: McColors.onSurface,
        fraction: 0.78,
        barColor: McColors.bull,
        footer: 'DefiLlama 全稳定币流通',
        footerColor: McColors.onSurfaceVariant,
      ),
      _MatrixCard(
        title: '多空人数比 (L/S)',
        pill: const McPill('Binance 账户', color: McColors.primarySoft, bold: false),
        value: _lsRatio,
        valueColor: McColors.onSurface,
        fraction: _lsFrac,
        barColor: McColors.primaryContainer,
        restColor: const Color(0xB3FF6363),
        footer: _lsFooter,
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

/// 恐惧与贪婪指数卡片. history 为近8日值 (最新在末位), 无则隐藏历史行.
class _FearGreedCard extends StatelessWidget {
  const _FearGreedCard(
      {required this.value,
      required this.label,
      required this.color,
      this.history});

  final int value;
  final String label;
  final Color color;
  final List<int>? history;

  @override
  Widget build(BuildContext context) {
    final hist = history;
    final yesterday = (hist != null && hist.length >= 2)
        ? hist[hist.length - 2]
        : null;
    final lastWeek =
        (hist != null && hist.length >= 8) ? hist[hist.length - 8] : null;
    final diff = yesterday == null ? null : value - yesterday;
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
              if (diff != null)
                McPill(
                  '${diff >= 0 ? '+' : ''}$diff 较昨日',
                  color: diff >= 0 ? McColors.bull : McColors.bear,
                  fontSize: 10,
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
          if (yesterday != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('昨日 $yesterday · ${_HomeTerminalPageState._fgLabelFor(yesterday).split(' ').first}',
                    style: McText.mono(
                        size: 12, color: McColors.onSurfaceVariant)),
                if (lastWeek != null) ...[
                  const SizedBox(height: 4),
                  Text(
                      '上周 $lastWeek · ${_HomeTerminalPageState._fgLabelFor(lastWeek).split(' ').first}',
                      style: McText.mono(
                          size: 12, color: McColors.onSurfaceVariant)),
                ],
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

/// 全网市占率分布饼图卡 (独立一块).
class _DominancePieCard extends StatelessWidget {
  const _DominancePieCard({
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

  static final Color _otherColor = McColors.surfaceVariant.withValues(alpha: 0.5);

  @override
  Widget build(BuildContext context) {
    return McCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pie_chart, size: 15, color: McColors.secondary),
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
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox.square(
                dimension: 110,
                child: CustomPaint(
                  painter: _DominancePiePainter(btcFrac, ethFrac),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('BTC',
                            style: McText.sans(
                                size: 11, color: McColors.onSurfaceVariant)),
                        Text(btc,
                            style: McText.mono(
                                size: 16, weight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _legend('BTC', btc, McColors.primaryContainer),
                    const SizedBox(height: 10),
                    _legend('ETH', eth, McColors.secondary),
                    const SizedBox(height: 10),
                    _legend('Other', other, _otherColor),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(String name, String pct, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(name,
            style:
                McText.sans(size: 12, color: McColors.onSurfaceVariant)),
        const Spacer(),
        Text(pct,
            style: McText.mono(size: 13, weight: FontWeight.w700, color: color)),
      ],
    );
  }
}

/// 三环 donut: BTC / ETH / Other.
class _DominancePiePainter extends CustomPainter {
  _DominancePiePainter(this.btcFrac, this.ethFrac);

  final double btcFrac;
  final double ethFrac;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.2;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final fracs = [
      btcFrac.clamp(0.0, 1.0),
      ethFrac.clamp(0.0, 1.0),
      (1 - btcFrac - ethFrac).clamp(0.0, 1.0),
    ];
    final colors = [
      McColors.primaryContainer,
      McColors.secondary,
      _DominancePieCard._otherColor,
    ];
    var angle = -math.pi / 2;
    for (var i = 0; i < 3; i++) {
      final sweep = fracs[i] * 2 * math.pi;
      if (sweep > 0) {
        paint.color = colors[i];
        canvas.drawArc(rect, angle, sweep, false, paint);
      }
      angle += sweep;
    }
  }

  @override
  bool shouldRepaint(_DominancePiePainter old) =>
      old.btcFrac != btcFrac || old.ethFrac != ethFrac;
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

/// 主流资产多维量化指标一览列表. rows=null 加载中显示占位.
class _AssetListCard extends StatelessWidget {
  const _AssetListCard({required this.rows});

  final List<_AssetRow>? rows;

  @override
  Widget build(BuildContext context) {
    final list = rows;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: McColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: McColors.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: list == null
            ? Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Text('行情加载中…',
                      style: McText.sans(
                          size: 12, color: McColors.onSurfaceVariant)),
                ),
              )
            : Column(
                children: [
                  for (var i = 0; i < list.length; i++) ...[
                    if (i > 0)
                      Divider(
                          height: 1,
                          color: McColors.outlineVariant.withValues(alpha: 0.3)),
                    list[i],
                  ],
                ],
              ),
      ),
    );
  }
}

class _AssetRow extends StatelessWidget {
  const _AssetRow({
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
                CoinIcon(symbol, size: 32),
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
            child: Row(
              children: [
                const McGlowDot(color: McColors.bull, size: 6),
                const SizedBox(width: 6),
                Text('数据源: CoinGlass / CoinGecko',
                    style: McText.mono(
                        size: 10, color: McColors.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('失败时展示缓存参考值',
              style: McText.mono(size: 10, color: McColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

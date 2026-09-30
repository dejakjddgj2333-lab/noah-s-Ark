import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/data.dart';
import '../services/ticker_ws.dart';

/// 行情详情页: 实时价格 (OKX WS), 24H 统计, K线, 资金费率.
class MarketDetailPage extends StatefulWidget {
  const MarketDetailPage({
    super.key,
    required this.instId,
    required this.symbol,
  });

  final String instId;
  final String symbol;

  @override
  State<MarketDetailPage> createState() => _MarketDetailPageState();
}

class _MarketDetailPageState extends State<MarketDetailPage> {
  // 实时行情 (REST 初始 + WS 推送覆盖).
  double _last = 0;
  double _open24h = 0;
  double _high24h = 0;
  double _low24h = 0;
  double _volCcy24h = 0;

  StreamSubscription<TickerPush>? _wsSub;

  // K线.
  List<Map<String, double>> _candles = [];
  String _bar = '1H';
  bool _candleLoading = true;

  // 资金费率.
  double? _fundingRate;
  DateTime? _nextFunding;

  static const _bars = ['15m', '1H', '4H', '1D'];

  double get _changePct =>
      _open24h > 0 ? (_last - _open24h) / _open24h * 100 : 0;
  double get _notional => _volCcy24h * _last;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _subscribeLive();
    _loadCandles();
    _loadFunding();
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    try {
      final t = await McData.ticker(widget.instId);
      if (!mounted) return;
      setState(() {
        _last = t.last;
        _open24h = t.open24h;
        _high24h = t.high24h;
        _low24h = t.low24h;
        _volCcy24h = t.volCcy24h;
      });
    } catch (_) {/* 保留占位, 等待 WS 推送 */}
  }

  void _subscribeLive() {
    final ws = TickerWs.instance;
    ws.subscribe({widget.instId});
    _wsSub = ws.stream.listen((p) {
      if (!mounted || p.instId != widget.instId) return;
      setState(() {
        _last = p.last;
        _open24h = p.open24h;
        _high24h = p.high24h;
        _low24h = p.low24h;
        _volCcy24h = p.volCcy24h;
      });
    });
  }

  Future<void> _loadCandles() async {
    setState(() => _candleLoading = true);
    try {
      final data = await McData.candles(widget.instId, bar: _bar, limit: 60);
      if (!mounted) return;
      setState(() {
        _candles = data;
        _candleLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _candles = [];
        _candleLoading = false;
      });
    }
  }

  Future<void> _loadFunding() async {
    try {
      final f = await McData.fundingRate(widget.instId);
      if (!mounted) return;
      setState(() {
        _fundingRate = f.rate;
        _nextFunding = f.nextFundingTime;
      });
    } catch (_) {/* 保留 null 占位 */}
  }

  void _selectBar(String bar) {
    if (bar == _bar) return;
    setState(() => _bar = bar);
    _loadCandles();
  }

  @override
  Widget build(BuildContext context) {
    final pct = _changePct;
    final positive = pct >= 0;
    final pctColor = positive ? McColors.bull : McColors.bear;
    return Scaffold(
      backgroundColor: McColors.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
          children: [
            _buildHeader(pct, pctColor),
            const SizedBox(height: 16),
            _buildStatsRow(),
            const SizedBox(height: 20),
            _buildKlineSection(),
            const SizedBox(height: 20),
            _buildFundingCard(),
          ],
        ),
      ),
    );
  }

  /// 顶部: 返回 + 标题 + 大字价格 + 涨跌徽章.
  Widget _buildHeader(double pct, Color pctColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back,
                  size: 20, color: McColors.onSurface),
              onPressed: () => Navigator.of(context).pop(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            const SizedBox(width: 4),
            Text(
              widget.symbol,
              style: McText.sans(size: 16, weight: FontWeight.w700),
            ),
            Text(
              '/USDT 永续',
              style:
                  McText.sans(size: 13, color: McColors.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _last > 0 ? _fmtPrice(_last) : '--',
                    style: McText.display(
                        size: 30, weight: FontWeight.w700, color: pctColor),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: pctColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: pctColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
                  style: McText.mono(
                      size: 12, weight: FontWeight.w700, color: pctColor),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 24H 统计: 高 / 低 / 成交额(名义 USD).
  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _stat('24H 最高', _high24h > 0 ? _fmtPrice(_high24h) : '--',
              McColors.bull),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _stat('24H 最低', _low24h > 0 ? _fmtPrice(_low24h) : '--',
              McColors.bear),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _stat('24H 成交额',
              _notional > 0 ? McData.fmtUsdCompact(_notional) : '--',
              McColors.onSurface),
        ),
      ],
    );
  }

  Widget _stat(String label, String value, Color valueColor) {
    return McCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  McText.sans(size: 12, color: McColors.onSurfaceVariant)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: McText.sans(
                  size: 15, weight: FontWeight.w700, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }

  /// K线区: 周期切换 + 蜡烛图.
  Widget _buildKlineSection() {
    return McCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('K线走势',
                  style: McText.sans(size: 13, weight: FontWeight.w600)),
              Row(
                children: [
                  for (final b in _bars)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: _barChip(b),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: _candleLoading
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: McColors.primary),
                    ),
                  )
                : _candles.isEmpty
                    ? Center(
                        child: Text('暂无K线数据',
                            style: McText.sans(
                                size: 12,
                                color: McColors.onSurfaceVariant)),
                      )
                    : CustomPaint(
                        size: Size.infinite,
                        painter: _CandlePainter(
                          candles: _candles,
                          lastPrice: _last,
                          bull: McColors.bull,
                          bear: McColors.bear,
                          gridColor: McColors.outlineVariant,
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _barChip(String bar) {
    final active = _bar == bar;
    return GestureDetector(
      onTap: () => _selectBar(bar),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? McColors.surfaceContainerHighest
              : McColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          bar,
          style: McText.sans(
            size: 12,
            weight: active ? FontWeight.w600 : FontWeight.w500,
            color: active ? McColors.onSurface : McColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// 资金费率卡片.
  Widget _buildFundingCard() {
    final rate = _fundingRate;
    final rateColor =
        (rate ?? 0) >= 0 ? McColors.bull : McColors.bear;
    return McCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.percent, size: 15, color: McColors.secondary),
              const SizedBox(width: 6),
              Text('资金费率',
                  style: McText.sans(size: 13, weight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _fundingItem(
                  '当前费率',
                  rate == null
                      ? '--'
                      : '${rate >= 0 ? '+' : ''}${(rate * 100).toStringAsFixed(4)}%',
                  rateColor,
                ),
              ),
              Expanded(
                child: _fundingItem(
                  '下次结算',
                  _nextFunding == null ? '--' : _fmtTime(_nextFunding!),
                  McColors.onSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fundingItem(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text(value,
            style: McText.mono(
                size: 14, weight: FontWeight.w700, color: valueColor)),
      ],
    );
  }

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

  static String _fmtTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }
}

/// 蜡烛图画笔: 绿涨红跌, 上下影线, 暗色背景网格 + 最新价虚线.
class _CandlePainter extends CustomPainter {
  _CandlePainter({
    required this.candles,
    required this.lastPrice,
    required this.bull,
    required this.bear,
    required this.gridColor,
  });

  final List<Map<String, double>> candles;
  final double lastPrice;
  final Color bull;
  final Color bear;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    var lo = double.infinity;
    var hi = -double.infinity;
    for (final c in candles) {
      if (c['l']! < lo) lo = c['l']!;
      if (c['h']! > hi) hi = c['h']!;
    }
    if (lastPrice > 0) {
      if (lastPrice < lo) lo = lastPrice;
      if (lastPrice > hi) hi = lastPrice;
    }
    final range = hi - lo;
    if (range <= 0) return;
    // 上下各留 6% 边距.
    final pad = range * 0.06;
    final min = lo - pad;
    final span = range + pad * 2;

    double yOf(double price) =>
        size.height - (price - min) / span * size.height;

    // 水平网格线 (4 条).
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    for (var i = 1; i <= 4; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final count = candles.length;
    final step = size.width / count;
    final bodyW = (step * 0.6).clamp(1.0, step);

    for (var i = 0; i < count; i++) {
      final c = candles[i];
      final o = c['o']!;
      final h = c['h']!;
      final l = c['l']!;
      final cl = c['c']!;
      final up = cl >= o;
      final color = up ? bull : bear;
      final cx = i * step + step / 2;

      // 影线.
      final wickPaint = Paint()
        ..color = color
        ..strokeWidth = 1;
      canvas.drawLine(Offset(cx, yOf(h)), Offset(cx, yOf(l)), wickPaint);

      // 实体.
      final bodyPaint = Paint()..color = color;
      final top = yOf(up ? cl : o);
      final bottom = yOf(up ? o : cl);
      final rect = Rect.fromLTRB(
        cx - bodyW / 2,
        top,
        cx + bodyW / 2,
        (bottom - top).abs() < 1 ? top + 1 : bottom,
      );
      canvas.drawRect(rect, bodyPaint);
    }

    // 最新价虚线.
    if (lastPrice > 0 && lastPrice >= min && lastPrice <= min + span) {
      final y = yOf(lastPrice);
      final dashPaint = Paint()
        ..color = McColors.onSurfaceVariant.withValues(alpha: 0.8)
        ..strokeWidth = 1;
      const dashW = 5.0;
      const gapW = 4.0;
      var x = 0.0;
      while (x < size.width) {
        canvas.drawLine(Offset(x, y), Offset(x + dashW, y), dashPaint);
        x += dashW + gapW;
      }
    }
  }

  @override
  bool shouldRepaint(_CandlePainter old) =>
      old.candles != candles || old.lastPrice != lastPrice;
}

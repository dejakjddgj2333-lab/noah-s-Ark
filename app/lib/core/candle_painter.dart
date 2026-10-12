/// OKX 风格蜡烛图 painter: 详情页与分享卡共用 (抽自 market_detail_page).
import 'package:flutter/material.dart';

/// OKX 风格蜡烛图: 右轴价标 + 时间轴 + MA5/10/20 + 成交量副图 + 最新价标签.
class McCandlePainter extends CustomPainter {
  McCandlePainter({
    required this.candles,
    required this.lastPrice,
    required this.bar,
    required this.bull,
    required this.bear,
    required this.gridColor,
    required this.labelColor,
    this.startIndex = 0,
    this.viewCount = 0,
  });

  final List<Map<String, double>> candles;
  final double lastPrice;
  final String bar;
  final Color bull;
  final Color bear;
  final Color gridColor;
  final Color labelColor;

  /// 可见窗口: [startIndex, startIndex+viewCount); viewCount<=0 = 全部.
  final int startIndex;
  final int viewCount;

  static const _labelW = 52.0; // 右轴价标宽
  static const _timeH = 16.0; // 底部时间轴高
  static const _legendH = 20.0; // 顶部 MA 图例区高 (价格绘图区下移, 不压 K 线)
  static const _volRatio = 0.22; // 成交量副图占比
  static const _ma5Color = Color(0xFFE8EAF0);
  static const _ma10Color = Color(0xFFF0B90B);
  static const _ma20Color = Color(0xFFB877DB);

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;
    // 可见窗口裁剪.
    final total = candles.length;
    var s0 = startIndex.clamp(0, total - 1);
    var cnt = viewCount <= 0 ? total : viewCount.clamp(1, total - s0);
    final s1 = (s0 + cnt).clamp(0, total);
    cnt = s1 - s0;
    if (cnt <= 0) return;

    var lo = double.infinity;
    var hi = -double.infinity;
    var maxVol = 0.0;
    var hiIdx = 0;
    var loIdx = 0;
    for (var i = s0; i < s1; i++) {
      final c = candles[i];
      if (c['l']! < lo) {
        lo = c['l']!;
        loIdx = i;
      }
      if (c['h']! > hi) {
        hi = c['h']!;
        hiIdx = i;
      }
      if (c['v']! > maxVol) maxVol = c['v']!;
    }
    if (lastPrice > 0) {
      if (lastPrice < lo) lo = lastPrice;
      if (lastPrice > hi) hi = lastPrice;
    }
    final range = hi - lo;
    if (range <= 0) return;

    final chartW = size.width - _labelW;
    if (chartW <= 0) return;
    final chartH = size.height - _timeH;
    final topPad = _legendH; // 顶部预留图例区, 避免 MA 图例压住 K 线最高价
    final priceH = chartH * (1 - _volRatio) - 4 - topPad;
    final volH = chartH * _volRatio;
    final volTop = topPad + priceH + 4;

    final pad = range * 0.06;
    final min = lo - pad;
    final span = range + pad * 2;
    double yOf(double price) =>
        topPad + priceH - (price - min) / span * priceH;

    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.25)
      ..strokeWidth = 1;

    // 水平网格 + 右轴价标 (5 档).
    for (var i = 0; i <= 4; i++) {
      final y = topPad + priceH * i / 4;
      canvas.drawLine(Offset(0, y), Offset(chartW, y), gridPaint);
      final price = min + span * (1 - i / 4);
      _text(canvas, _axisPrice(price),
          Offset(chartW + 6, y - 5), labelColor, 10);
    }

    // 价格区与量区分隔线.
    canvas.drawLine(Offset(0, volTop), Offset(chartW, volTop), gridPaint);

    final step = chartW / cnt;
    final bodyW = (step * 0.62).clamp(1.0, step);
    double xOf(int i) => (i - s0) * step + step / 2;

    // 时间轴 (4 档).
    for (var i = 0; i < 4; i++) {
      final idx = s0 + (cnt - 1) * i ~/ 3;
      final x = xOf(idx);
      final label = _axisTime(candles[idx]['ts']!);
      final w = label.length * 5.4;
      var tx = x - w / 2;
      if (tx < 0) tx = 0;
      if (tx + w > chartW) tx = chartW - w;
      _text(canvas, label, Offset(tx, topPad + priceH + 6 + volH), labelColor, 9);
    }

    // 蜡烛 + 成交量.
    for (var i = s0; i < s1; i++) {
      final c = candles[i];
      final o = c['o']!;
      final h = c['h']!;
      final l = c['l']!;
      final cl = c['c']!;
      final up = cl >= o;
      final color = up ? bull : bear;
      final cx = xOf(i);

      canvas.drawLine(
          Offset(cx, yOf(h)),
          Offset(cx, yOf(l)),
          Paint()
            ..color = color
            ..strokeWidth = 1);
      final top = yOf(up ? cl : o);
      final bottom = yOf(up ? o : cl);
      canvas.drawRect(
        Rect.fromLTRB(cx - bodyW / 2, top, cx + bodyW / 2,
            (bottom - top).abs() < 1 ? top + 1 : bottom),
        Paint()..color = color,
      );

      if (maxVol > 0) {
        final vh = (c['v']! / maxVol) * volH;
        canvas.drawRect(
          Rect.fromLTRB(cx - bodyW / 2, volTop + volH - vh, cx + bodyW / 2,
              volTop + volH),
          Paint()..color = color.withValues(alpha: 0.35),
        );
      }
    }

    // MA 线 + 左上角图例 (带半透明底, 避免与 K 线/价标重叠).
    _maLine(canvas, 5, step, yOf, _ma5Color, s0, s1);
    _maLine(canvas, 10, step, yOf, _ma10Color, s0, s1);
    _maLine(canvas, 20, step, yOf, _ma20Color, s0, s1);
    final legend = <(String, Color)>[];
    for (final (n, color) in [(5, _ma5Color), (10, _ma10Color), (20, _ma20Color)]) {
      final v = _maAt(s1 - 1, n);
      legend.add((v == null ? 'MA$n' : 'MA$n ${_axisPrice(v)}', color));
    }
    const legendPadX = 6.0;
    const legendGap = 10.0;
    var legendW = legendPadX * 2;
    for (final (t, _) in legend) {
      legendW += _measure(t, 10) + legendGap;
    }
    legendW -= legendGap; // 末项后无 gap
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, legendW, 20),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0x660B0E14),
    );
    var lx = legendPadX;
    for (final (t, color) in legend) {
      _text(canvas, t, Offset(lx, 4), color, 10);
      lx += _measure(t, 10) + legendGap;
    }

    // 可见区最高/最低价指示 (OKX 风格: 极值点短横线 + 价格文本).
    final markColor = const Color(0xFFE8EAF0).withValues(alpha: 0.9);
    _hiLoMark(canvas, xOf(hiIdx), yOf(candles[hiIdx]['h']!),
        candles[hiIdx]['h']!, markColor, chartW);
    _hiLoMark(canvas, xOf(loIdx), yOf(candles[loIdx]['l']!),
        candles[loIdx]['l']!, markColor, chartW);

    // 最新价虚线 + 右轴标签.
    if (lastPrice > 0 && lastPrice >= min && lastPrice <= min + span) {
      final y = yOf(lastPrice);
      final lastClose = candles.last['c']!;
      final tagColor = lastPrice >= lastClose ? bull : bear;
      final dashPaint = Paint()
        ..color = tagColor.withValues(alpha: 0.7)
        ..strokeWidth = 1;
      var x = 0.0;
      while (x < chartW) {
        canvas.drawLine(Offset(x, y), Offset(x + 5, y), dashPaint);
        x += 9;
      }
      canvas.drawRect(
        Rect.fromLTWH(chartW, y - 8, _labelW, 16),
        Paint()..color = tagColor,
      );
      _text(canvas, _axisPrice(lastPrice), Offset(chartW + 4, y - 5),
          const Color(0xFF0B0E14), 10,
          bold: true);
    }
  }

  /// 极值标记: 从 (x,y) 向左右画 20px 短横线, 外侧跟价格文本 (x 过半屏向左).
  void _hiLoMark(Canvas canvas, double x, double y, double price, Color color,
      double chartW) {
    const lineSize = 20.0;
    const gap = 5.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final label = _axisPrice(price);
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: color, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    if (x < chartW / 2) {
      canvas.drawLine(Offset(x, y), Offset(x + lineSize, y), paint);
      tp.paint(canvas, Offset(x + lineSize + gap, y - tp.height / 2));
    } else {
      canvas.drawLine(Offset(x - lineSize, y), Offset(x, y), paint);
      tp.paint(canvas, Offset(x - lineSize - gap - tp.width, y - tp.height / 2));
    }
  }

  double? _maAt(int end, int n) {
    if (end < n - 1 || end < 0) return null;
    var sum = 0.0;
    for (var i = end - n + 1; i <= end; i++) {
      sum += candles[i]['c']!;
    }
    return sum / n;
  }

  void _maLine(Canvas canvas, int n, double step, double Function(double) yOf,
      Color color, int s0, int s1) {
    final path = Path();
    var started = false;
    final begin = s0 > n - 1 ? s0 : n - 1;
    for (var i = begin; i < s1; i++) {
      final v = _maAt(i, n)!;
      final x = (i - s0) * step + step / 2;
      if (!started) {
        path.moveTo(x, yOf(v));
        started = true;
      } else {
        path.lineTo(x, yOf(v));
      }
    }
    if (!started) return;
    canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.9)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke);
  }

  void _text(Canvas canvas, String s, Offset at, Color color, double size,
      {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  double _measure(String s, double size) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontSize: size, fontWeight: FontWeight.w400),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  String _axisPrice(double p) {
    if (p >= 1000) return p.toStringAsFixed(1);
    if (p >= 1) return p.toStringAsFixed(2);
    return p.toStringAsFixed(4);
  }

  String _axisTime(double tsMs) {
    final t = DateTime.fromMillisecondsSinceEpoch(tsMs.toInt());
    String two(int n) => n.toString().padLeft(2, '0');
    if (bar == '1D') return '${two(t.month)}-${two(t.day)}';
    return '${two(t.hour)}:${two(t.minute)}';
  }

  @override
  bool shouldRepaint(McCandlePainter old) =>
      old.candles != candles ||
      old.lastPrice != lastPrice ||
      old.bar != bar ||
      old.startIndex != startIndex ||
      old.viewCount != viewCount;
}

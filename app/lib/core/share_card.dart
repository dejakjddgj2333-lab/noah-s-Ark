/// K线分享卡: 离屏渲染行情卡片 → PNG → 系统分享 (share_plus).
///
/// 复用 [McCandlePainter] 画蜡烛图, 卡片固定深色底 (明暗主题下观感一致),
/// 带「明策」水印, 天然传播物料.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import 'candle_painter.dart';
import 'theme.dart';

class ShareCard {
  /// 离屏挂载卡片, 等一帧渲染后截图为 PNG 并调起系统分享.
  static Future<void> share({
    required BuildContext context,
    required String symbol,
    required double last,
    required double changePct,
    required List<Map<String, double>> candles,
    required String bar,
    required Color bull,
    required Color bear,
  }) async {
    if (candles.isEmpty || last <= 0) return;
    final key = GlobalKey();
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -10000,
        top: 0,
        child: RepaintBoundary(
          key: key,
          child: _ShareCardView(
            symbol: symbol,
            last: last,
            changePct: changePct,
            candles: candles,
            bar: bar,
            bull: bull,
            bear: bear,
          ),
        ),
      ),
    );
    Overlay.of(context).insert(entry);
    try {
      // 等离屏内容完成一帧渲染
      await Future.delayed(const Duration(milliseconds: 120));
      final boundary = key.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      await SharePlus.instance.share(ShareParams(
        files: [
          XFile.fromData(
            bytes.buffer.asUint8List(),
            mimeType: 'image/png',
            name: '$symbol-kline.png',
          ),
        ],
      ));
    } finally {
      entry.remove();
    }
  }
}

class _ShareCardView extends StatelessWidget {
  const _ShareCardView({
    required this.symbol,
    required this.last,
    required this.changePct,
    required this.candles,
    required this.bar,
    required this.bull,
    required this.bear,
  });

  final String symbol;
  final double last;
  final double changePct;
  final List<Map<String, double>> candles;
  final String bar;
  final Color bull;
  final Color bear;

  static String _fmt(double p) {
    if (p >= 1000) return p.toStringAsFixed(1);
    if (p >= 1) return p.toStringAsFixed(2);
    return p.toStringAsFixed(4);
  }

  @override
  Widget build(BuildContext context) {
    final pctColor = changePct >= 0 ? bull : bear;
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final timeStr =
        '${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}';
    // 固定深色卡面, 不随主题变化 (分享出去观感一致)
    const bg = Color(0xFF0B0E14);
    const line = Color(0xFF23262F);
    const textMain = Color(0xFFE8EAF0);
    const textSub = Color(0xFF8B8F9E);

    return Material(
      color: bg,
      child: Container(
        width: 360,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$symbol/USDT · $bar',
                  style: McText.sans(
                      size: 14, weight: FontWeight.w700, color: textMain),
                ),
                Text(timeStr,
                    style: McText.mono(size: 10, color: textSub)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _fmt(last),
                  style: McText.display(
                      size: 28, weight: FontWeight.w700, color: pctColor),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(2)}%',
                    style: McText.mono(
                        size: 13, weight: FontWeight.w700, color: pctColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: CustomPaint(
                painter: McCandlePainter(
                  candles: candles,
                  lastPrice: last,
                  bar: bar,
                  bull: bull,
                  bear: bear,
                  gridColor: line,
                  labelColor: textSub,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('明策 MINGCE',
                    style: McText.display(
                        size: 12, weight: FontWeight.w600, color: textSub)),
                Text('MA5 / MA10 / MA20',
                    style: McText.mono(size: 9, color: textSub)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

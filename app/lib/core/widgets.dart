import 'package:flutter/material.dart';

import '../services/api.dart';
import 'theme.dart';

/// Panel card: surface-container-low bg, 1px hairline border, radius 12.
class McCard extends StatelessWidget {
  const McCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color = McColors.surfaceContainerLow,
    this.borderColor,
    this.radius = 12,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color? borderColor;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ?? McColors.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: child,
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: box,
      ),
    );
  }
}

/// Small mono tag/pill: tinted bg + border, uppercase-ish label.
class McPill extends StatelessWidget {
  const McPill(
    this.text, {
    super.key,
    this.color = McColors.primarySoft,
    this.fontSize = 12,
    this.bold = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
  });

  final String text;
  final Color color;
  final double fontSize;
  final bool bold;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        text,
        style: McText.mono(
          size: fontSize,
          weight: bold ? FontWeight.w700 : FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}

/// Neutral chip on surface-container bg (e.g. "Tx: 8f42...a90b").
class McChip extends StatelessWidget {
  const McChip(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: McColors.surfaceContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: McText.mono(size: 12, color: color ?? McColors.onSurfaceVariant),
      ),
    );
  }
}

/// Glowing status dot.
class McGlowDot extends StatelessWidget {
  const McGlowDot({super.key, this.color = McColors.bull, this.size = 6});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.8), blurRadius: 6)],
      ),
    );
  }
}

/// Section header: glowing dot or icon + bold title + optional trailing label.
class McSectionHeader extends StatelessWidget {
  const McSectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
    this.trailingColor = McColors.onSurfaceVariant,
  });

  final String title;
  final IconData? icon;
  final String? trailing;
  final Color trailingColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          if (icon != null)
            Icon(icon, size: 15, color: McColors.primaryContainer)
          else
            const McGlowDot(color: McColors.primaryContainer),
          const SizedBox(width: 6),
          Text(
            title,
            style: McText.sans(size: 12, weight: FontWeight.w600),
          ),
          const Spacer(),
          if (trailing != null)
            Text(trailing!, style: McText.mono(size: 12, color: trailingColor)),
        ],
      ),
    );
  }
}

/// Thin progress bar with glow on the filled segment.
class McProgressBar extends StatelessWidget {
  const McProgressBar({
    super.key,
    required this.fraction,
    this.color = McColors.primaryContainer,
    this.height = 6,
    this.trackColor = McColors.surfaceContainerLowest,
    this.glow = true,
  });

  final double fraction; // 0..1
  final Color color;
  final double height;
  final Color trackColor;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: Container(
        height: height,
        color: trackColor,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: fraction.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              boxShadow: glow
                  ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)]
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Polyline sparkline. Points normalized 0..1 (y up). Stroke 2, round caps.
class McSparkline extends StatelessWidget {
  const McSparkline({
    super.key,
    required this.points,
    this.color = McColors.bull,
    this.width = 64,
    this.height = 24,
    this.strokeWidth = 2,
  });

  final List<double> points;
  final Color color;
  final double width;
  final double height;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SparklinePainter(points, color, strokeWidth),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.points, this.color, this.strokeWidth);

  final List<double> points;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = i / (points.length - 1) * size.width;
      final y = (1 - points[i]) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.points != points || old.color != color;
}

/// Up/down percent badge: mono bold on tinted bg.
class McDeltaBadge extends StatelessWidget {
  const McDeltaBadge(this.text, {super.key, required this.positive});

  final String text;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final c = positive ? McColors.bull : McColors.bear;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: McText.mono(size: 12, weight: FontWeight.w700, color: c),
      ),
    );
  }
}

/// 头像: 有图显示网络图, 无图/加载失败回退首字母. url 为相对路径时自动补 baseUrl.
class McAvatar extends StatelessWidget {
  const McAvatar({
    super.key,
    required this.name,
    this.url,
    this.size = 46,
    this.radius = 10,
    this.bg,
    this.fg = McColors.primarySoft,
  });

  final String name;
  final String? url;
  final double size;
  final double radius;
  final Color? bg;
  final Color fg;

  String get _fullUrl {
    final u = url ?? '';
    if (u.isEmpty) return '';
    if (u.startsWith('http')) return u;
    return '${McApi.baseUrl}$u';
  }

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg ?? fg.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: McText.display(
          size: size * 0.38,
          weight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
    final u = _fullUrl;
    if (u.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        u,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

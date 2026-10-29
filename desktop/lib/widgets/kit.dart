import 'package:flutter/material.dart';

import '../theme.dart';

/// Card Navy panel: 1px hairline border, 12px radius, 18px padding.
class McCard extends StatelessWidget {
  const McCard({super.key, required this.child, this.padding, this.color});
  final Widget child;
  final EdgeInsets? padding;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: color ?? Mc.card,
          borderRadius: BorderRadius.circular(Mc.cardRadius),
          border: Border.all(color: Mc.hairline),
        ),
        padding: padding ?? const EdgeInsets.all(Mc.cardPadding),
        child: child,
      );
}

/// Uppercase mono micro-label, e.g. `WHALE ALERT`.
class McTag extends StatelessWidget {
  const McTag(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: Mc.tag(color: color));
}

/// Section header: mono tag + SpaceGrotesk title + optional trailing.
class McSection extends StatelessWidget {
  const McSection(this.title, {super.key, this.tag, this.trailing});
  final String title;
  final String? tag;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (tag != null) McTag(tag!, color: Mc.cobaltSoft),
            Text(title, style: Mc.display(16)),
          ]),
        ),
        ?trailing,
      ]);
}

enum McBtnKind { primary, ghost, danger }

class McButton extends StatelessWidget {
  const McButton(this.label,
      {super.key,
      this.onPressed,
      this.kind = McBtnKind.primary,
      this.icon,
      this.busy = false,
      this.height = 40});
  final String label;
  final VoidCallback? onPressed;
  final McBtnKind kind;
  final IconData? icon;
  final bool busy;
  final double height;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (kind) {
      McBtnKind.primary => (Mc.cobalt, Colors.white, Colors.transparent),
      McBtnKind.ghost => (Mc.surface, Mc.cobaltSoft, Mc.hairline),
      McBtnKind.danger => (Mc.bear.withValues(alpha: 0.12), Mc.bear, Mc.bear),
    };
    return SizedBox(
      height: height,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: busy ? null : onPressed,
          borderRadius: BorderRadius.circular(8),
          hoverColor: Colors.white.withValues(alpha: 0.06),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border),
            ),
            alignment: Alignment.center,
            child: busy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    if (icon != null) ...[
                      Icon(icon, size: 16, color: fg),
                      const SizedBox(width: 6)
                    ],
                    Text(label,
                        style: Mc.body(13, w: FontWeight.w600, color: fg)),
                  ]),
          ),
        ),
      ),
    );
  }
}

/// Surface input with hairline border; cobalt focus ring.
class McInput extends StatelessWidget {
  const McInput(
      {super.key,
      this.controller,
      this.hint,
      this.obscure = false,
      this.prefix,
      this.suffix,
      this.onSubmitted,
      this.onChanged,
      this.keyboardType,
      this.height = 40});
  final TextEditingController? controller;
  final String? hint;
  final bool obscure;
  final IconData? prefix;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final double height;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Mc.hairline),
    );
    return SizedBox(
      height: height,
      child: TextField(
        controller: controller,
        obscureText: obscure,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        keyboardType: keyboardType,
        style: Mc.body(13),
        cursorColor: Mc.cobaltSoft,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: Mc.body(13, color: Mc.muted.withValues(alpha: 0.6)),
          filled: true,
          fillColor: Mc.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          prefixIcon:
              prefix != null ? Icon(prefix, size: 16, color: Mc.muted) : null,
          suffixIcon: suffix,
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
              borderSide: const BorderSide(color: Mc.cobalt, width: 1.2)),
        ),
      ),
    );
  }
}

/// Semantic pill badge: 12% tinted bg + semantic text.
class McBadge extends StatelessWidget {
  const McBadge(this.text, {super.key, this.color = Mc.cobaltSoft});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: Mc.mono(10, w: FontWeight.w600, color: color)),
      );
}

/// KPI tile: mono tag label + big mono value + delta line. The delta row is
/// always laid out (invisible when null) so sibling tiles stay equal height.
class McStat extends StatelessWidget {
  const McStat(this.label, this.value,
      {super.key, this.delta, this.deltaIsPct = true, this.valueColor});
  final String label;
  final String value;
  final num? delta;
  final bool deltaIsPct;
  final Color? valueColor;
  @override
  Widget build(BuildContext context) => McCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          McTag(label),
          const SizedBox(height: 8),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Mc.mono(22, w: FontWeight.w600, color: valueColor ?? Mc.ink)),
          const SizedBox(height: 4),
          Text(
            delta == null
                ? ' '
                : '${(delta! >= 0) ? '+' : ''}${delta!.toStringAsFixed(2)}${deltaIsPct ? '%' : ''}',
            maxLines: 1,
            style: Mc.mono(12, color: Mc.upDown(delta)),
          ),
        ]),
      );
}

class McLoading extends StatelessWidget {
  const McLoading({super.key, this.label = '加载中'});
  final String label;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Mc.cobaltSoft)),
          const SizedBox(height: 12),
          Text(label, style: Mc.body(12, color: Mc.muted)),
        ]),
      );
}

class McError extends StatelessWidget {
  const McError(this.message, {super.key, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, color: Mc.bear, size: 28),
          const SizedBox(height: 8),
          Text(message, style: Mc.body(12, color: Mc.muted)),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            McButton('重试', kind: McBtnKind.ghost, height: 32, onPressed: onRetry),
          ],
        ]),
      );
}

class McEmpty extends StatelessWidget {
  const McEmpty(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) => Center(
      child: Text(label, style: Mc.body(13, color: Mc.muted)));
}

/// Table header cell — small muted uppercase-ish.
class McTh extends StatelessWidget {
  const McTh(this.text, {super.key, this.align = TextAlign.left});
  final String text;
  final TextAlign align;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(text,
            textAlign: align,
            style: Mc.body(11, w: FontWeight.w600, color: Mc.muted)),
      );
}

/// Equal-height 12-col grid row: children expanded by span, fixed gutter,
/// every card stretched to the tallest. Use for all side-by-side card rows
/// so left/right edges and baselines line up across the page.
class McRow extends StatelessWidget {
  const McRow({super.key, required this.children, this.spans, this.gap = 16});
  final List<Widget> children;

  /// 12-col spans per child; defaults to equal split.
  final List<int>? spans;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final sp = spans ?? List.filled(children.length, 12 ~/ children.length);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(flex: sp[i], child: children[i]),
          ],
        ],
      ),
    );
  }
}

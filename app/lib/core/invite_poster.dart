/// 邀请分享海报: 离屏渲染海报 → PNG → 系统分享 (share_plus).
///
/// 海报含品牌 logo、邀请标语、邀请链接二维码、邀请码, 固定深色底.
/// 复用 ShareCard 同款离屏截图技术.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'l10n.dart';
import 'theme.dart';

/// Stitch「Obsidian Precision」布局 + App 钴蓝主题.
/// 仅用于分享页/海报, 不改 App 其它页面.
abstract final class InviteDesign {
  static const canvas = Color(0xFF070D1C);
  static const surface = Color(0xFF0D1528);
  static const card = Color(0xFF121D34);
  static const cardHigh = Color(0xFF1A2742);
  static const line = Color(0xFF34415E);
  static const primary = McColors.primarySoft;
  static const primaryContainer = McColors.primaryContainer;
  static const onPrimary = Color(0xFFFFFFFF);
  static const text = Color(0xFFF0F0FF);
  static const textMuted = McColors.onSurfaceVariant;
}

class InvitePoster {
  /// 分享前先展示海报预览, 用户确认后才生成 PNG 并调起系统分享.
  static Future<void> previewAndShare({
    required BuildContext context,
    required String inviteCode,
    required String inviteLink,
  }) async {
    if (inviteCode.isEmpty || inviteLink.isEmpty) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: tr('cancel'),
      barrierColor: Colors.black.withValues(alpha: 0.82),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, _, _) => _InviteSharePreviewDialog(
        inviteCode: inviteCode,
        inviteLink: inviteLink,
      ),
      transitionBuilder: (_, animation, _, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curve,
          child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(curve),
            child: child,
          ),
        );
      },
    );
  }

  /// 离屏挂载海报, 截图为 PNG 并调起系统分享.
  static Future<void> share({
    required BuildContext context,
    required String inviteCode,
    required String inviteLink,
  }) async {
    if (inviteCode.isEmpty || inviteLink.isEmpty) return;
    final key = GlobalKey();
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -10000,
        top: 0,
        child: RepaintBoundary(
          key: key,
          child: _InvitePosterView(
            inviteCode: inviteCode,
            inviteLink: inviteLink,
          ),
        ),
      ),
    );
    Overlay.of(context).insert(entry);
    try {
      await Future.delayed(const Duration(milliseconds: 150));
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              bytes.buffer.asUint8List(),
              mimeType: 'image/png',
              name: 'mingce-invite-$inviteCode.png',
            ),
          ],
        ),
      );
    } finally {
      entry.remove();
    }
  }

  /// 邀请页内实时预览; 与分享出去的 PNG 使用同一个组件.
  static Widget preview({
    required String inviteCode,
    required String inviteLink,
  }) {
    return _InvitePosterView(
      inviteCode: inviteCode,
      inviteLink: inviteLink,
      compact: true,
    );
  }
}

class _InviteSharePreviewDialog extends StatefulWidget {
  const _InviteSharePreviewDialog({
    required this.inviteCode,
    required this.inviteLink,
  });

  final String inviteCode;
  final String inviteLink;

  @override
  State<_InviteSharePreviewDialog> createState() =>
      _InviteSharePreviewDialogState();
}

class _InviteSharePreviewDialogState extends State<_InviteSharePreviewDialog> {
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await InvitePoster.share(
        context: context,
        inviteCode: widget.inviteCode,
        inviteLink: widget.inviteLink,
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('inv_poster_preview_title'),
                      style: McText.display(
                        size: 18,
                        weight: FontWeight.w700,
                        color: InviteDesign.text,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _sharing
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: InviteDesign.text),
                    tooltip: tr('cancel'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 0.53,
                    child: InvitePoster.preview(
                      inviteCode: widget.inviteCode,
                      inviteLink: widget.inviteLink,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _sharing ? null : _share,
                  icon: _sharing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: InviteDesign.onPrimary,
                          ),
                        )
                      : const Icon(
                          Icons.ios_share,
                          size: 19,
                          color: InviteDesign.onPrimary,
                        ),
                  label: Text(
                    tr(_sharing ? 'inv_poster_sharing' : 'inv_share_poster'),
                    style: McText.sans(
                      size: 15,
                      weight: FontWeight.w700,
                      color: InviteDesign.onPrimary,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: InviteDesign.primaryContainer,
                    disabledBackgroundColor: InviteDesign.primaryContainer
                        .withValues(alpha: 0.65),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 分享页与离屏截图共用的海报.
class _InvitePosterView extends StatelessWidget {
  const _InvitePosterView({
    required this.inviteCode,
    required this.inviteLink,
    this.compact = false,
  });

  final String inviteCode;
  final String inviteLink;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final poster = Material(
      color: InviteDesign.canvas,
      child: Container(
        width: 360,
        decoration: BoxDecoration(
          color: InviteDesign.canvas,
          border: Border.all(color: InviteDesign.line.withValues(alpha: 0.7)),
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image(
                image: AssetImage('assets/invite_poster_bg.jpg'),
                fit: BoxFit.cover,
                color: const Color(0xFF315DFF).withValues(alpha: 0.24),
                colorBlendMode: BlendMode.color,
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      InviteDesign.canvas.withValues(alpha: 0.12),
                      InviteDesign.canvas.withValues(alpha: 0.48),
                      InviteDesign.canvas.withValues(alpha: 0.82),
                    ],
                    stops: const [0, 0.48, 1],
                  ),
                ),
              ),
            ),
            const Positioned.fill(child: _TechnicalGrid()),
            Positioned(
              left: 40,
              right: 40,
              top: -90,
              height: 220,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      InviteDesign.primary.withValues(alpha: 0.12),
                      InviteDesign.primary.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _posterHeader(),
                  const SizedBox(height: 22),
                  Text(
                    tr('inv_poster_title'),
                    textAlign: TextAlign.center,
                    style: McText.display(
                      size: 25,
                      weight: FontWeight.w700,
                      color: InviteDesign.text,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr('inv_poster_subtitle'),
                    textAlign: TextAlign.center,
                    style: McText.sans(
                      size: 12,
                      color: InviteDesign.textMuted,
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _featureStrip(),
                  const SizedBox(height: 20),
                  _qrCard(),
                  const SizedBox(height: 17),
                  Text(
                    tr('inv_poster_code_label'),
                    style: McText.sans(
                      size: 12,
                      color: InviteDesign.textMuted,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: InviteDesign.card.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: InviteDesign.primary.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      inviteCode,
                      style: McText.mono(
                        size: 27,
                        weight: FontWeight.w700,
                        color: InviteDesign.primary,
                        letterSpacing: 3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.qr_code_scanner,
                        size: 16,
                        color: InviteDesign.primary,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          tr('inv_poster_scan_hint'),
                          textAlign: TextAlign.center,
                          style: McText.sans(
                            size: 12,
                            color: InviteDesign.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (!compact) return poster;
    return FittedBox(
      fit: BoxFit.contain,
      alignment: Alignment.topCenter,
      child: poster,
    );
  }

  Widget _posterHeader() {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Image.asset('assets/logo.png', width: 34, height: 34),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '明策 MINGCE',
                style: McText.display(
                  size: 17,
                  weight: FontWeight.w700,
                  color: InviteDesign.text,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'MARKET INTELLIGENCE',
                style: McText.mono(
                  size: 12,
                  color: InviteDesign.textMuted.withValues(alpha: 0.7),
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: InviteDesign.cardHigh.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: InviteDesign.line.withValues(alpha: 0.65),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: InviteDesign.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                'INVITE',
                style: McText.mono(
                  size: 12,
                  weight: FontWeight.w600,
                  color: InviteDesign.primary,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _featureStrip() {
    final features = [
      (Icons.show_chart, tr('inv_poster_feature_market')),
      (Icons.radar, tr('inv_poster_feature_whale')),
      (Icons.record_voice_over, tr('inv_poster_feature_voice')),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        color: InviteDesign.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: InviteDesign.line.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < features.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 30,
                color: InviteDesign.line.withValues(alpha: 0.45),
              ),
            Expanded(
              child: Column(
                children: [
                  Icon(features[i].$1, size: 17, color: InviteDesign.primary),
                  const SizedBox(height: 5),
                  Text(
                    features[i].$2,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: McText.sans(size: 12, color: InviteDesign.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _qrCard() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: QrImageView(
            data: inviteLink,
            version: QrVersions.auto,
            size: 172,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: InviteDesign.canvas,
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: InviteDesign.canvas,
            ),
          ),
        ),
        Container(
          width: 38,
          height: 38,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white, width: 3),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.asset('assets/logo.png'),
          ),
        ),
      ],
    );
  }
}

class _TechnicalGrid extends StatelessWidget {
  const _TechnicalGrid();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _GridPainter());
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = InviteDesign.line.withValues(alpha: 0.12)
      ..strokeWidth = 0.6;
    const step = 24.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

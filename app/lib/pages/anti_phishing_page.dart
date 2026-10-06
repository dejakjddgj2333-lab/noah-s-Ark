import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';

/// 防钓鱼码: 设置后官方通知附带此码, 空串清除.
class AntiPhishingPage extends StatefulWidget {
  const AntiPhishingPage({super.key});

  @override
  State<AntiPhishingPage> createState() => _AntiPhishingPageState();
}

class _AntiPhishingPageState extends State<AntiPhishingPage> {
  late final TextEditingController _ctrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: AuthStore.instance.antiPhishingCode ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: McText.sans(size: 13)),
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            error ? McColors.bear.withValues(alpha: 0.9) : McColors.surfaceContainerHigh,
        duration: const Duration(seconds: 2),
      ));
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await AuthStore.instance.setAntiPhishing(_ctrl.text.trim());
      await AuthStore.instance.refreshProfile();
      if (!mounted) return;
      _toast(tr('ap_done'));
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    } catch (_) {
      _toast(tr('update_failed'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: McColors.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: McColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: McColors.onSurface),
        title: Text(tr('ap_title'),
            style: McText.sans(size: 15, weight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        children: [
          Text(tr('ap_hint'),
              style: McText.sans(size: 13, color: McColors.onSurfaceVariant)),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            maxLength: 32,
            style: McText.mono(size: 13),
            decoration: InputDecoration(
              hintText: tr('ap_input'),
              hintStyle:
                  McText.sans(size: 13, color: McColors.onSurfaceVariant),
              counterStyle:
                  McText.sans(size: 12, color: McColors.onSurfaceVariant),
              prefixIcon: const Icon(Icons.verified_user_outlined,
                  size: 18, color: McColors.onSurfaceVariant),
              filled: true,
              fillColor: McColors.surfaceContainerLowest,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                    color: McColors.outlineVariant.withValues(alpha: 0.6)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                    color: McColors.outlineVariant.withValues(alpha: 0.6)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                    color: McColors.primaryContainer, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: _busy ? null : _submit,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: _busy
                    ? McColors.surfaceContainerHigh
                    : McColors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: McColors.primarySoft),
                    )
                  : Text(tr('save'),
                      style: McText.sans(
                          size: 14,
                          weight: FontWeight.w700,
                          color: McColors.onPrimaryContainer)),
            ),
          ),
        ],
      ),
    );
  }
}

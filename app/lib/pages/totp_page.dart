import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';

/// 谷歌验证 (2FA): 未绑定时显示密钥绑定, 已绑定时输入验证码解绑.
class TotpPage extends StatefulWidget {
  const TotpPage({super.key});

  @override
  State<TotpPage> createState() => _TotpPageState();
}

class _TotpPageState extends State<TotpPage> {
  final _codeCtrl = TextEditingController();
  bool _busy = false;
  bool _loading = false;
  String? _secret;

  bool get _bound => AuthStore.instance.has2fa;

  @override
  void initState() {
    super.initState();
    if (!_bound) _setup();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _setup() async {
    setState(() => _loading = true);
    try {
      final resp = await AuthStore.instance.totpSetup();
      if (!mounted) return;
      setState(() => _secret = (resp['secret'] ?? '').toString());
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    } catch (_) {
      _toast(tr('update_failed'), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      _toast(tr('totp_code'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      if (_bound) {
        await AuthStore.instance.totpDisable(code);
        await AuthStore.instance.refreshProfile();
        if (!mounted) return;
        _toast(tr('totp_unbound'));
      } else {
        await AuthStore.instance.totpEnable(code);
        await AuthStore.instance.refreshProfile();
        if (!mounted) return;
        _toast(tr('totp_bound'));
      }
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    } catch (_) {
      _toast(tr('update_failed'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    final s = _secret;
    if (s == null || s.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: s));
    _toast(tr('totp_copied'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: McColors.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: McColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: McColors.onSurface),
        title: Text(tr('totp_title'),
            style: McText.sans(size: 15, weight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        children: [
          if (!_bound) ...[
            Text(tr('totp_scan_hint'),
                style:
                    McText.sans(size: 13, color: McColors.onSurfaceVariant)),
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: McColors.primarySoft),
                ),
              )
            else if (_secret != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                decoration: BoxDecoration(
                  color: McColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: McColors.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      _secret!,
                      style: McText.mono(
                          size: 15,
                          weight: FontWeight.w600,
                          color: McColors.primary,
                          letterSpacing: 1),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: _copy,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.copy,
                              size: 14, color: McColors.primarySoft),
                          const SizedBox(width: 6),
                          Text(tr('totp_copy'),
                              style: McText.sans(
                                  size: 13, color: McColors.primarySoft)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ],
          _field(_codeCtrl, tr('totp_code'), Icons.pin_outlined),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: _busy ? null : _submit,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: _busy
                    ? McColors.surfaceContainerHigh
                    : (_bound ? McColors.bear : McColors.primaryContainer),
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
                  : Text(_bound ? tr('totp_unbind') : tr('totp_bind'),
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

  Widget _field(TextEditingController ctrl, String hint, IconData icon) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      style: McText.mono(size: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: McText.sans(size: 13, color: McColors.onSurfaceVariant),
        prefixIcon: Icon(icon, size: 18, color: McColors.onSurfaceVariant),
        filled: true,
        fillColor: McColors.surfaceContainerLowest,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              BorderSide(color: McColors.outlineVariant.withValues(alpha: 0.6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              BorderSide(color: McColors.outlineVariant.withValues(alpha: 0.6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: McColors.primaryContainer, width: 1.5),
        ),
      ),
    );
  }
}

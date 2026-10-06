import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';

/// 修改登录密码页: 原密码 + 新密码 + 确认, 调 /api/auth/change-password.
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _oldCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
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
    final oldPw = _oldCtrl.text;
    final newPw = _newCtrl.text;
    final confirm = _confirmCtrl.text;
    if (newPw.length < 8) {
      _toast(tr('cp_err_short'), error: true);
      return;
    }
    if (newPw != confirm) {
      _toast(tr('cp_err_mismatch'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await AuthStore.instance.changePassword(oldPw, newPw);
      if (!mounted) return;
      _toast(tr('cp_done'));
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
        title: Text(tr('cp_title'),
            style: McText.sans(size: 15, weight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        children: [
          _field(_oldCtrl, tr('cp_old'), Icons.lock_outline),
          const SizedBox(height: 14),
          _field(_newCtrl, tr('cp_new'), Icons.lock_reset),
          const SizedBox(height: 14),
          _field(_confirmCtrl, tr('cp_confirm'), Icons.lock_outline),
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
                  : Text(tr('cp_submit'),
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
      obscureText: true,
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

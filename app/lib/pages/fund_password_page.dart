import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';

/// 资金密码: 未设置时设置(需登录密码), 已设置时修改.
class FundPasswordPage extends StatefulWidget {
  const FundPasswordPage({super.key});

  @override
  State<FundPasswordPage> createState() => _FundPasswordPageState();
}

class _FundPasswordPageState extends State<FundPasswordPage> {
  final _aCtrl = TextEditingController(); // 未设置: 资金密码 / 已设置: 原资金密码
  final _bCtrl = TextEditingController(); // 未设置: 登录密码 / 已设置: 新资金密码
  final _cCtrl = TextEditingController(); // 已设置: 确认新资金密码
  bool _busy = false;

  bool get _isSet => AuthStore.instance.hasFundPassword;

  @override
  void dispose() {
    _aCtrl.dispose();
    _bCtrl.dispose();
    _cCtrl.dispose();
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

  bool _is6Digits(String s) => RegExp(r'^\d{6}$').hasMatch(s);

  Future<void> _submit() async {
    if (_busy) return;
    if (_isSet) {
      final oldPw = _aCtrl.text;
      final newPw = _bCtrl.text;
      final confirm = _cCtrl.text;
      if (!_is6Digits(newPw)) {
        _toast(tr('fp_err_6'), error: true);
        return;
      }
      if (newPw != confirm) {
        _toast(tr('cp_err_mismatch'), error: true);
        return;
      }
      setState(() => _busy = true);
      try {
        await AuthStore.instance.changeFundPassword(oldPw, newPw);
        await AuthStore.instance.refreshProfile();
        if (!mounted) return;
        _toast(tr('fp_done'));
        Navigator.of(context).pop();
      } on ApiException catch (e) {
        _toast(e.message, error: true);
      } catch (_) {
        _toast(tr('update_failed'), error: true);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } else {
      final fundPw = _aCtrl.text;
      final loginPw = _bCtrl.text;
      if (!_is6Digits(fundPw)) {
        _toast(tr('fp_err_6'), error: true);
        return;
      }
      setState(() => _busy = true);
      try {
        await AuthStore.instance.setFundPassword(fundPw, loginPw);
        await AuthStore.instance.refreshProfile();
        if (!mounted) return;
        _toast(tr('fp_done'));
        Navigator.of(context).pop();
      } on ApiException catch (e) {
        _toast(e.message, error: true);
      } catch (_) {
        _toast(tr('update_failed'), error: true);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
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
        title: Text(tr('fp_title'),
            style: McText.sans(size: 15, weight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        children: [
          if (_isSet) ...[
            _field(_aCtrl, tr('fp_old'), Icons.lock_outline),
            const SizedBox(height: 14),
            _field(_bCtrl, tr('fp_new'), Icons.lock_reset),
            const SizedBox(height: 14),
            _field(_cCtrl, tr('fp_confirm'), Icons.lock_outline),
          ] else ...[
            _field(_aCtrl, tr('fp_title'), Icons.lock_outline),
            const SizedBox(height: 14),
            _field(_bCtrl, tr('fp_login_pw'), Icons.password),
          ],
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

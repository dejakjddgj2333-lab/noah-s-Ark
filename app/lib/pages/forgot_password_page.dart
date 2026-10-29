import 'dart:async';

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';

/// 忘记密码页 (push 路由 /forgot-password). 邮箱验证码重置密码, 视觉风格同登录页.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  bool _busy = false;
  String? _error;

  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();

  // 验证码倒计时
  int _countdown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = tr('login_err_email'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // 后端模糊提示: 邮箱未注册也返回 ok, 前端恒提示「验证码已发送」.
      final debugCode =
          await AuthStore.instance.sendEmailCode(email, purpose: 'reset');
      _startCountdown();
      if (debugCode != null && mounted) {
        // dev 模式: SMTP 未配置, 直接回填
        _codeCtrl.text = debugCode;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('login_dev_code_filled'))),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('login_code_sent'))),
        );
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = tr('login_err_network'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _countdown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdown <= 1) {
        t.cancel();
        setState(() => _countdown = 0);
      } else {
        setState(() => _countdown--);
      }
    });
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    final password = _passCtrl.text;
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = tr('login_err_email'));
      return;
    }
    if (code.isEmpty) {
      setState(() => _error = tr('login_err_empty_code'));
      return;
    }
    if (password.length < 8) {
      setState(() => _error = tr('forgot_err_pwd_short'));
      return;
    }
    if (password != _pass2Ctrl.text) {
      setState(() => _error = tr('login_err_pwd_mismatch'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthStore.instance
          .resetPassword(email: email, code: code, newPassword: password);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('forgot_success'))),
        );
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = tr('login_err_network'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: McColors.surface,
      appBar: AppBar(
        backgroundColor: McColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 18, color: McColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: McColors.primaryContainer
                                .withValues(alpha: 0.45),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child:
                          Image.asset('assets/logo.png', fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: Text(tr('forgot_title'),
                        style: McText.display(
                            size: 20, weight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      tr('forgot_subtitle'),
                      textAlign: TextAlign.center,
                      style: McText.sans(
                          size: 12, color: McColors.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 表单
                  _field(_emailCtrl, tr('email'), Icons.mail_outline,
                      keyboard: TextInputType.emailAddress),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _field(_codeCtrl, tr('login_email_code'),
                            Icons.pin_outlined,
                            keyboard: TextInputType.number),
                      ),
                      const SizedBox(width: 10),
                      _codeButton(),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _field(_passCtrl, tr('forgot_new_password'),
                      Icons.lock_outline,
                      obscure: true),
                  const SizedBox(height: 12),
                  _field(_pass2Ctrl, tr('login_confirm_password'),
                      Icons.lock_outline,
                      obscure: true),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: McColors.bear.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: McColors.bear.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              size: 14, color: McColors.bear),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(_error!,
                                style: McText.sans(
                                    size: 12, color: McColors.bear)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: McColors.primaryContainer,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            McColors.primaryContainer.withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              tr('forgot_btn_reset'),
                              style: McText.sans(
                                  size: 14,
                                  weight: FontWeight.w700,
                                  letterSpacing: 2),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    bool obscure = false,
    TextInputType? keyboard,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboard,
      style: McText.mono(size: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            McText.sans(size: 13, color: McColors.onSurfaceVariant),
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

  Widget _codeButton() {
    final disabled = _countdown > 0 || _busy;
    return SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: disabled ? null : _sendCode,
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: disabled
                ? McColors.outlineVariant
                : McColors.primaryContainer,
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        child: Text(
          _countdown > 0 ? '${_countdown}s' : tr('login_send_code'),
          style: McText.mono(
            size: 12,
            weight: FontWeight.w600,
            color: disabled
                ? McColors.onSurfaceVariant
                : McColors.primarySoft,
          ),
        ),
      ),
    );
  }
}

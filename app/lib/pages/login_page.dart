import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';

/// 登录 / 注册页 (push 路由 /login). 终端风格: 黑曜输入框 + 钴蓝执行键.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isLogin = true;
  bool _busy = false;
  String? _error;

  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  // 验证码倒计时
  int _countdown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = '请输入有效邮箱');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final debugCode = await AuthStore.instance.sendEmailCode(email);
      _startCountdown();
      if (debugCode != null && mounted) {
        // dev 模式: SMTP 未配置, 直接回填
        _codeCtrl.text = debugCode;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('开发模式: 验证码已自动填入')),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('验证码已发送, 请查收邮箱')),
        );
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = '网络错误, 请稍后重试');
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
    final username = _userCtrl.text.trim();
    final password = _passCtrl.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = '请输入用户名和密码');
      return;
    }
    if (!_isLogin) {
      if (_emailCtrl.text.trim().isEmpty || _codeCtrl.text.trim().isEmpty) {
        setState(() => _error = '请输入邮箱和验证码');
        return;
      }
      if (password != _pass2Ctrl.text) {
        setState(() => _error = '两次密码不一致');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_isLogin) {
        await AuthStore.instance.login(username: username, password: password);
      } else {
        await AuthStore.instance.register(
          username: username,
          password: password,
          email: _emailCtrl.text.trim(),
          code: _codeCtrl.text.trim(),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = '网络错误, 请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: McColors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 品牌
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
                    child: Text('Noah’s Ark',
                        style: McText.display(
                            size: 20, weight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      _isLogin ? '欢迎回到交易终端' : '创建终端账户 · 邮箱即凭证',
                      style: McText.sans(
                          size: 12, color: McColors.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 登录/注册 切换
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: McColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color:
                              McColors.outlineVariant.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        _segTab('登录', _isLogin, () {
                          setState(() {
                            _isLogin = true;
                            _error = null;
                          });
                        }),
                        _segTab('注册', !_isLogin, () {
                          setState(() {
                            _isLogin = false;
                            _error = null;
                          });
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // 表单
                  _field(_userCtrl, '用户名', Icons.person_outline),
                  const SizedBox(height: 12),
                  if (!_isLogin) ...[
                    _field(_emailCtrl, '邮箱', Icons.mail_outline,
                        keyboard: TextInputType.emailAddress),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _field(
                              _codeCtrl, '邮箱验证码', Icons.pin_outlined,
                              keyboard: TextInputType.number),
                        ),
                        const SizedBox(width: 10),
                        _codeButton(),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  _field(_passCtrl, '密码', Icons.lock_outline, obscure: true),
                  if (!_isLogin) ...[
                    const SizedBox(height: 12),
                    _field(_pass2Ctrl, '确认密码', Icons.lock_outline,
                        obscure: true),
                  ],
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
                  // 执行键
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
                              _isLogin ? '登 录' : '注册并绑定邮箱',
                              style: McText.sans(
                                  size: 14,
                                  weight: FontWeight.w700,
                                  letterSpacing: 2),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      '注册即代表同意《终端服务协议》与《风险披露声明》',
                      style: McText.sans(
                          size: 12, color: McColors.onSurfaceVariant),
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

  Widget _segTab(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? McColors.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: active
                ? [
                    BoxShadow(
                        color:
                            McColors.primaryContainer.withValues(alpha: 0.5),
                        blurRadius: 10)
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: McText.sans(
              size: 13,
              weight: FontWeight.w700,
              color: active ? Colors.white : McColors.onSurfaceVariant,
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
          _countdown > 0 ? '${_countdown}s' : '发送验证码',
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

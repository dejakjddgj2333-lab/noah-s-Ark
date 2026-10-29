import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme.dart';
import '../widgets/kit.dart';

/// 忘记密码页 —— 居中卡片布局，与注册页一致；从登录页 Navigator.push 进入。
/// 后端模糊提示: 邮箱未注册也返回 ok, 前端恒提示「验证码已发送」。
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});
  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();

  bool _busy = false;
  bool _sending = false;
  bool _codeSent = false;
  bool _showPass = false;
  bool _done = false;
  String? _error;

  Timer? _timer;
  int _countdown = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _code.dispose();
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String _errText(Object e) => e is DioException
      ? (e.error?.toString() ?? e.message ?? '网络错误')
      : e.toString();

  Future<void> _sendCode() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = '请先填写正确的邮箱');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final res =
          await ApiClient.I.sendEmailCode(email, purpose: 'reset');
      setState(() {
        _codeSent = true;
        _countdown = 60;
        // dev 模式: SMTP 未配置时后端回显验证码, 直接回填
        final dbg = res is Map ? res['debug_code'] : null;
        if (dbg != null) _code.text = dbg.toString();
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        setState(() {
          _countdown--;
          if (_countdown <= 0) t.cancel();
        });
      });
    } catch (e) {
      setState(() => _error = _errText(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty ||
        _code.text.trim().isEmpty ||
        _pass.text.isEmpty) {
      setState(() => _error = '请填写完整信息');
      return;
    }
    if (_pass.text.length < 8) {
      setState(() => _error = '新密码至少 8 位');
      return;
    }
    if (_pass.text != _confirm.text) {
      setState(() => _error = '两次密码不一致');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.I
          .resetPassword(_email.text.trim(), _code.text.trim(), _pass.text);
      if (mounted) setState(() => _done = true);
    } catch (e) {
      setState(() => _error = _errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: SizedBox(
            width: 400,
            child: McCard(
              padding: const EdgeInsets.all(32),
              child: _done ? _buildDone() : _buildForm(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDone() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
            color: Mc.bull.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10)),
        alignment: Alignment.center,
        child: const Icon(Icons.check, color: Mc.bull, size: 24),
      ),
      const SizedBox(height: 14),
      Text('密码已重置', style: Mc.display(18, w: FontWeight.w700)),
      const SizedBox(height: 6),
      Text('请使用新密码重新登录终端',
          textAlign: TextAlign.center, style: Mc.body(12, color: Mc.muted)),
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: McButton('返回登录',
            onPressed: () => Navigator.of(context).pop()),
      ),
    ]);
  }

  Widget _buildForm() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('PASSWORD RECOVERY', style: Mc.tag(color: Mc.cobaltSoft)),
              const SizedBox(height: 6),
              Text('找回密码', style: Mc.display(20, w: FontWeight.w700)),
            ]),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.arrow_back, size: 14, color: Mc.cobaltSoft),
              const SizedBox(width: 4),
              Text('返回登录',
                  style: Mc.body(12, w: FontWeight.w600, color: Mc.cobaltSoft)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerLeft,
        child: Text('通过注册邮箱验证身份后重置终端访问密钥',
            style: Mc.body(12, color: Mc.muted)),
      ),
      const SizedBox(height: 24),
      _fieldLabel('注册邮箱'),
      McInput(
          controller: _email,
          hint: 'name@institution.com',
          prefix: Icons.alternate_email,
          keyboardType: TextInputType.emailAddress),
      const SizedBox(height: 14),
      _fieldLabel('邮箱验证码'),
      Row(children: [
        Expanded(
          child: McInput(
              controller: _code,
              hint: '6 位验证码',
              prefix: Icons.mark_email_read_outlined),
        ),
        const SizedBox(width: 8),
        McButton(
          _countdown > 0
              ? '${_countdown}s'
              : (_codeSent ? '重新发送' : '获取验证码'),
          kind: McBtnKind.ghost,
          busy: _sending,
          onPressed: (_countdown > 0 || _sending) ? null : _sendCode,
        ),
      ]),
      const SizedBox(height: 14),
      _fieldLabel('新访问密钥'),
      McInput(
        controller: _pass,
        hint: '至少8位，包含大写字母与特殊字符',
        prefix: Icons.lock_outline,
        obscure: !_showPass,
        onSubmitted: (_) => _submit(),
        suffix: GestureDetector(
          onTap: () => setState(() => _showPass = !_showPass),
          child: Icon(
              _showPass
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 16,
              color: Mc.muted),
        ),
      ),
      const SizedBox(height: 14),
      _fieldLabel('确认新密钥'),
      McInput(
          controller: _confirm,
          hint: '再次输入以确认',
          prefix: Icons.lock_reset,
          obscure: true,
          onSubmitted: (_) => _submit()),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(_error!, style: Mc.body(12, color: Mc.bear)),
        ),
      ],
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: McButton('重 置 密 码', busy: _busy, onPressed: _submit),
      ),
    ]);
  }

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text, style: Mc.tag()),
        ),
      );
}

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme.dart';
import '../widgets/kit.dart';

/// 注册页 —— 居中卡片布局，与登录页一致；从登录页 Navigator.push 进入。
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _user = TextEditingController();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  final _invite = TextEditingController();

  bool _busy = false;
  bool _sending = false;
  bool _codeSent = false;
  bool _agreed = true;
  bool _showPass = false;
  bool _done = false;
  String? _error;

  Timer? _timer;
  int _countdown = 0;

  @override
  void initState() {
    super.initState();
    _pass.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _user.dispose();
    _email.dispose();
    _code.dispose();
    _pass.dispose();
    _confirm.dispose();
    _invite.dispose();
    super.dispose();
  }

  /// 密码强度 0-3 段（与 web 端一致）。
  int get _pwdStrength {
    final p = _pass.text;
    if (p.isEmpty) return 0;
    var s = 0;
    if (p.length >= 8) s++;
    if (RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[a-z]').hasMatch(p)) s++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p) || RegExp(r'\d').hasMatch(p)) s++;
    return s;
  }

  String get _strengthLabel =>
      const ['强度: 弱', '强度: 弱', '强度: 中强', '强度: 强'][_pwdStrength];

  String _errText(Object e) => e is DioException
      ? (e.error?.toString() ?? e.message ?? '网络错误')
      : e.toString();

  Future<void> _sendCode() async {
    if (_email.text.trim().isEmpty) {
      setState(() => _error = '请先填写邮箱');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ApiClient.I.sendEmailCode(_email.text.trim(), purpose: 'register');
      setState(() {
        _codeSent = true;
        _countdown = 60;
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
    if (_user.text.trim().isEmpty ||
        _email.text.trim().isEmpty ||
        _pass.text.isEmpty) {
      setState(() => _error = '请填写完整信息');
      return;
    }
    if (_pass.text != _confirm.text) {
      setState(() => _error = '两次密码不一致');
      return;
    }
    if (!_agreed) {
      setState(() => _error = '请先阅读并同意终端访问协议');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.I.register({
        'username': _user.text.trim(),
        'email': _email.text.trim(),
        'password': _pass.text,
        'code': _code.text.trim(),
        if (_invite.text.trim().isNotEmpty) 'invite_code': _invite.text.trim(),
      });
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
      Text('注册成功', style: Mc.display(18, w: FontWeight.w700)),
      const SizedBox(height: 6),
      Text('账号已创建，请返回登录页使用新账号登录',
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
    final strength = _pwdStrength;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('NEW TERMINAL ACCESS', style: Mc.tag(color: Mc.cobaltSoft)),
              const SizedBox(height: 6),
              Text('创建账户', style: Mc.display(20, w: FontWeight.w700)),
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
        child: Text('邀请制终端权限开启 · 请录入操作员凭证',
            style: Mc.body(12, color: Mc.muted)),
      ),
      const SizedBox(height: 24),
      _fieldLabel('操作员用户名'),
      McInput(
          controller: _user,
          hint: '例如: quant_trader_01',
          prefix: Icons.badge_outlined),
      const SizedBox(height: 14),
      _fieldLabel('机构 / 工作邮箱'),
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
      Row(children: [
        Expanded(child: _fieldLabel('终端访问密码')),
        if (_pass.text.isNotEmpty)
          Text(_strengthLabel,
              style: Mc.tag(
                  color: strength >= 2 ? Mc.bull : Mc.muted)),
      ]),
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
      const SizedBox(height: 8),
      Row(children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: strength > i ? Mc.bull : Mc.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 14),
      _fieldLabel('确认终端密码'),
      McInput(
          controller: _confirm,
          hint: '再次输入以确认',
          prefix: Icons.lock_reset,
          obscure: true,
          onSubmitted: (_) => _submit()),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _fieldLabel('专属邀请码')),
        const McBadge('选填', color: Mc.amber),
      ]),
      McInput(
          controller: _invite, hint: 'MGC-XXXX-XXXX', prefix: Icons.key_outlined),
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerLeft,
        child: Text('填写好友邀请码，双方享返佣',
            style: Mc.body(11, color: Mc.amber)),
      ),
      const SizedBox(height: 16),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 18,
          height: 18,
          child: Checkbox(
            value: _agreed,
            onChanged: (v) => setState(() => _agreed = v ?? false),
            activeColor: Mc.cobalt,
            side: const BorderSide(color: Mc.hairline),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _agreed = !_agreed),
            child: Text('我已阅读并知悉机构合规接入要求及交易终端访问协议',
                style: Mc.body(12, color: Mc.muted)),
          ),
        ),
      ]),
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
        child:
            McButton('注册并进入终端', busy: _busy, onPressed: _submit),
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

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/auth_store.dart';
import '../theme.dart';
import '../widgets/kit.dart';
import 'legal_page.dart';
import 'forgot_password_page.dart';
import 'register_page.dart';

/// 登录页: 宽屏 (>=900) 左右分栏 (左 55% 品牌区 / 右 45% 登录卡),
/// 顶部状态条 + 底部合规 footer; 窄屏退化为单栏居中卡。
/// 结构对齐 web-terminal/src/views/Login.vue (3D 地球以 radial 渐变替代)。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const _kRemember = 'mc_remember_terminal';
  static const _kSavedUser = 'mc_saved_username';

  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  bool _remember = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRemembered();
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _loadRemembered() async {
    try {
      final p = await SharedPreferences.getInstance();
      final remember = p.getBool(_kRemember) ?? false;
      if (!mounted || !remember) {
        if (mounted) setState(() => _remember = remember);
        return;
      }
      setState(() {
        _remember = true;
        _user.text = p.getString(_kSavedUser) ?? '';
      });
    } catch (_) {}
  }

  Future<void> _persistRemember() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kRemember, _remember);
      if (_remember) {
        await p.setString(_kSavedUser, _user.text.trim());
      } else {
        await p.remove(_kSavedUser);
      }
    } catch (_) {}
  }

  Future<void> _submit() async {
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = '请输入用户名和密码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthStore.I.login(_user.text.trim(), _pass.text);
      await _persistRemember();
    } catch (e) {
      final msg = e is DioException
          ? (e.error?.toString() ?? e.message ?? '网络错误')
          : e.toString();
      setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 忘记密码: 邮箱验证码重置 (接口 /auth/send-email-code + /auth/reset-password)。
  void _forgotPassword() {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ForgotPasswordPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 900) {
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: _loginCard(),
            ),
          );
        }
        return Column(children: [
          _topBar(),
          Expanded(
            child: Row(children: [
              Expanded(flex: 55, child: _brandPanel()),
              Expanded(flex: 45, child: _authPanel()),
            ]),
          ),
          _footer(),
        ]);
      }),
    );
  }

  // ---------- 顶部状态条 ----------
  Widget _topBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Mc.canvas,
        border: Border(bottom: BorderSide(color: Mc.hairline)),
      ),
      child: Row(children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: Mc.card,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Mc.hairline),
          ),
          alignment: Alignment.center,
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Mc.cobalt.withValues(alpha: 0.25),
              border: Border.all(color: Mc.cobalt),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text('MINGCE', style: Mc.display(14, w: FontWeight.w700)),
        const SizedBox(width: 8),
        Text('|', style: Mc.body(12, color: Mc.hairline)),
        const SizedBox(width: 8),
        Text('TERMINAL.V4', style: Mc.tag()),
        const Spacer(),
        Container(
            width: 6,
            height: 6,
            decoration:
                const BoxDecoration(color: Mc.bull, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('系统状态: 正常 (14ms)', style: Mc.mono(11)),
        const SizedBox(width: 16),
        Container(width: 1, height: 14, color: Mc.hairline),
        const SizedBox(width: 16),
        const Icon(Icons.security, size: 14, color: Mc.muted),
        const SizedBox(width: 4),
        Text('SSL 256', style: Mc.tag()),
        const SizedBox(width: 14),
        const Icon(Icons.language, size: 14, color: Mc.muted),
        const SizedBox(width: 4),
        Text('ZH-CN', style: Mc.tag()),
        const SizedBox(width: 14),
        const Icon(Icons.help_outline, size: 14, color: Mc.muted),
        const SizedBox(width: 4),
        Text('支持', style: Mc.tag()),
      ]),
    );
  }

  // ---------- 左 55% 品牌区 ----------
  Widget _brandPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topLeft,
          radius: 1.4,
          colors: [Mc.cobalt.withValues(alpha: 0.14), Colors.transparent],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Spacer(),
        // INSTITUTIONAL CORE 徽标
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Mc.cobalt.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Mc.cobalt.withValues(alpha: 0.4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                    color: Mc.cobalt, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text('INSTITUTIONAL CORE', style: Mc.tag(color: Mc.cobaltSoft)),
          ]),
        ),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('明策 MINGCE', style: Mc.display(34, w: FontWeight.w700)),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Mc.card,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Mc.hairline),
                ),
                child: Text('PRO', style: Mc.tag(color: Mc.muted)),
              ),
            ]),
        const SizedBox(height: 6),
        Text('全球高密行情洞察与机构级巨鲸流动性中枢',
            style: Mc.mono(12, color: Mc.muted)),
        const SizedBox(height: 24),
        // 4 能力小卡
        Row(children: [
          _capCard('L3 ORDERBOOK', '48 EXCHANGES', '629K TICK/S'),
          const SizedBox(width: 12),
          _capCard('HSM VAULT', 'TPM 2.0', 'ISMS CERTIFIED'),
          const SizedBox(width: 12),
          _capCard('LATENCY', '14ms HK-CENTRAL', '0 PACKET DROP'),
          const SizedBox(width: 12),
          _capCard('WHALE DETECTION', '38,420 WALLETS', 'REALTIME FLOW',
              subColor: Mc.amber),
        ]),
        const Spacer(),
        // 4 状态 pill
        Row(children: [
          _statPill(Icons.speed, Mc.bull, '延迟: ', '14ms (HK)'),
          const SizedBox(width: 10),
          _statPill(Icons.query_stats, Mc.muted, '监控实体: ', '38,420'),
          const SizedBox(width: 10),
          _statPill(Icons.lock, Mc.cobaltSoft, '', 'AES-256 GCM'),
          const SizedBox(width: 10),
          _statPill(Icons.verified_user, Mc.cobaltSoft, '', 'HSM TPM 2.0'),
        ]),
      ]),
    );
  }

  Widget _capCard(String label, String value, String sub,
      {Color subColor = Mc.bull}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Mc.card.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Mc.hairline),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Mc.tag()),
          const SizedBox(height: 4),
          Text(value,
              overflow: TextOverflow.ellipsis,
              style: Mc.mono(13, w: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(sub, style: Mc.mono(10, color: subColor)),
        ]),
      ),
    );
  }

  Widget _statPill(IconData icon, Color iconColor, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Mc.card.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Mc.hairline),
        ),
        child: Row(children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text.rich(
              TextSpan(children: [
                if (label.isNotEmpty)
                  TextSpan(text: label, style: Mc.body(11, color: Mc.muted)),
                TextSpan(text: value, style: Mc.mono(11)),
              ]),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      ),
    );
  }

  // ---------- 右 45% 认证区 ----------
  Widget _authPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: Mc.surface,
        border: Border(left: BorderSide(color: Mc.hairline)),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _loginCard(),
            const SizedBox(height: 16),
            Wrap(alignment: WrapAlignment.center, children: [
              Text('登录即代表同意 ', style: Mc.body(11, color: Mc.muted)),
              _inlineLink('用户协议', 'terms'),
              Text(' 与 ', style: Mc.body(11, color: Mc.muted)),
              _inlineLink('隐私政策', 'privacy'),
            ]),
            const SizedBox(height: 4),
            Text.rich(TextSpan(children: [
              TextSpan(
                  text: '安全接入节点: ', style: Mc.mono(11, color: Mc.muted)),
              TextSpan(text: 'NODE: HK-CENTRAL-01', style: Mc.mono(11)),
            ])),
          ]),
        ),
      ),
    );
  }

  Widget _inlineLink(String label, String kind) {
    return GestureDetector(
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => LegalPage(kind: kind))),
      child: Text(label,
          style: Mc.body(11, color: Mc.muted)
              .copyWith(decoration: TextDecoration.underline)),
    );
  }

  // ---------- 登录卡 ----------
  Widget _loginCard() {
    return SizedBox(
      width: 420,
      child: McCard(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset('assets/logo.png',
                width: 44, height: 44, fit: BoxFit.cover),
          ),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('明策', style: Mc.display(20, w: FontWeight.w700)),
            const SizedBox(width: 6),
            Text('MINGCE',
                style:
                    Mc.display(16, w: FontWeight.w700, color: Mc.cobaltSoft)),
          ]),
          const SizedBox(height: 4),
          Text('MARKET INTELLIGENCE', style: Mc.tag(color: Mc.cobaltSoft)),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('AUTHORIZED ACCESS ONLY', style: Mc.tag(color: Mc.cobaltSoft)),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('请输入分配的机构操作员凭据以解锁行情会话',
                style: Mc.body(12, color: Mc.muted)),
          ),
          const SizedBox(height: 16),
          McInput(
              controller: _user,
              hint: '用户名',
              prefix: Icons.person_outline,
              onSubmitted: (_) => _submit()),
          const SizedBox(height: 12),
          McInput(
            controller: _pass,
            hint: '密码',
            prefix: Icons.lock_outline,
            obscure: _obscure,
            onSubmitted: (_) => _submit(),
            suffix: InkWell(
              onTap: () => setState(() => _obscure = !_obscure),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 16,
                    color: Mc.muted),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            SizedBox(
              width: 18,
              height: 18,
              child: Checkbox(
                value: _remember,
                onChanged: (v) => setState(() => _remember = v ?? false),
                activeColor: Mc.cobalt,
                checkColor: Colors.white,
                side: const BorderSide(color: Mc.hairline),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() => _remember = !_remember),
              child:
                  Text('记住当前终端 (30天)', style: Mc.body(11, color: Mc.muted)),
            ),
            const Spacer(),
            GestureDetector(
              onTap: _forgotPassword,
              child: Text('忘记密码?',
                  style:
                      Mc.body(11, w: FontWeight.w500, color: Mc.cobaltSoft)),
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
            child: McButton(_busy ? '登 录 中 …' : '登 录', busy: _busy, onPressed: _submit),
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('还没有账号？', style: Mc.body(12, color: Mc.muted)),
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RegisterPage())),
              child: Text('立即注册',
                  style:
                      Mc.body(12, w: FontWeight.w600, color: Mc.cobaltSoft)),
            ),
          ]),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final (label, kind) in [
              ('服务条款', 'terms'),
              ('隐私政策', 'privacy'),
              ('监管披露', 'disclosure'),
            ]) ...[
              GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => LegalPage(kind: kind))),
                child: Text(label, style: Mc.body(11, color: Mc.muted)),
              ),
              if (kind != 'disclosure')
                Text('  ·  ', style: Mc.body(11, color: Mc.hairline)),
            ],
          ]),
        ]),
      ),
    );
  }

  // ---------- 底部 footer ----------
  Widget _footer() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Mc.canvas,
        border: Border(top: BorderSide(color: Mc.hairline)),
      ),
      child: Row(children: [
        Text('MINGCE', style: Mc.display(12, color: Mc.muted)),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
              '© 2025 MINGCE Terminal Inc. All rights reserved. AES-256 GCM 机构级端到端加密传输',
              overflow: TextOverflow.ellipsis,
              style: Mc.body(11, color: Mc.muted)),
        ),
        const Spacer(),
        for (final (label, kind) in [
          ('服务条款', 'terms'),
          ('隐私合规', 'privacy'),
          ('监管披露', 'disclosure'),
        ]) ...[
          GestureDetector(
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => LegalPage(kind: kind))),
            child: Text(label, style: Mc.body(11, color: Mc.muted)),
          ),
          Text('  ·  ', style: Mc.body(11, color: Mc.hairline)),
        ],
        Container(
            width: 6,
            height: 6,
            decoration:
                const BoxDecoration(color: Mc.bull, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text('节点状态', style: Mc.body(11, color: Mc.muted)),
      ]),
    );
  }
}

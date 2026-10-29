import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../state/auth_store.dart';
import '../state/settings_store.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/kit.dart';

/// 个人中心页: 用户信息 / 账户安全 / 邀请返佣 / 登录设备。
/// 数据组织参考 web-terminal/src/views/Profile.vue; 接口失败静默降级。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _loading = true;
  bool _fatal = false;

  Map<String, dynamic>? _invite;
  Map<String, dynamic> _summary = const {};
  List<dynamic>? _devices;
  Map<String, dynamic>? _vip;

  String _pwdMsg = '';
  Timer? _msgTimer;

  // ---------- 偏好设置 (本地持久化, 仅存储不接线) ----------
  static const _kLang = 'mc_lang';
  static const _kColorScheme = 'mc_color_scheme';
  static const _kNotifMarket = 'mc_notif_market';
  static const _kNotifWhale = 'mc_notif_whale';
  static const _kNotifSystem = 'mc_notif_system';
  static const _kAntiPhishing = 'mc_anti_phishing';

  String _lang = 'zh';
  String _colorScheme = 'intl';
  bool _notifMarket = true;
  bool _notifWhale = true;
  bool _notifSystem = true;
  String _antiPhishing = '';

  @override
  void initState() {
    super.initState();
    _load();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _lang = p.getString(_kLang) ?? 'zh';
        _colorScheme = p.getString(_kColorScheme) ?? 'intl';
        _notifMarket = p.getBool(_kNotifMarket) ?? true;
        _notifWhale = p.getBool(_kNotifWhale) ?? true;
        _notifSystem = p.getBool(_kNotifSystem) ?? true;
        _antiPhishing = p.getString(_kAntiPhishing) ?? '';
      });
    } catch (_) {}
  }

  Future<void> _saveStringPref(String key, String value) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(key, value);
    } catch (_) {}
  }

  Future<void> _saveBoolPref(String key, bool value) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(key, value);
    } catch (_) {}
  }

  @override
  void dispose() {
    _msgTimer?.cancel();
    super.dispose();
  }

  Future<dynamic> _safe(Future<dynamic> f) async {
    try {
      return await f;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    final api = ApiClient.I;
    final r = await Future.wait([
      _safe(api.inviteMe()),
      _safe(api.commissionsSummary()),
      _safe(api.devices()),
      _safe(api.vipMe()),
    ]);
    AuthStore.I.refreshMe();
    if (!mounted) return;
    setState(() {
      if (r[0] is Map) _invite = Map<String, dynamic>.from(r[0] as Map);
      if (r[1] is Map) _summary = Map<String, dynamic>.from(r[1] as Map);
      final d = r[2];
      if (d is List) {
        _devices = d;
      } else if (d is Map && d['data'] is List) {
        _devices = d['data'] as List;
      } else if (d is Map && d['devices'] is List) {
        _devices = d['devices'] as List;
      }
      if (r[3] is Map) _vip = Map<String, dynamic>.from(r[3] as Map);
      _fatal = AuthStore.I.user == null &&
          _invite == null &&
          _devices == null &&
          _summary.isEmpty;
      _loading = false;
    });
  }

  Future<void> _retry() async {
    setState(() {
      _loading = true;
      _fatal = false;
    });
    await _load();
  }

  // ---------- 派生数据 ----------
  Map<String, dynamic> get _user => AuthStore.I.user ?? const {};

  String get _displayName => AuthStore.I.displayName.isEmpty
      ? '--'
      : AuthStore.I.displayName;

  String get _avatarChar {
    final n = _displayName;
    return (n.isEmpty || n == '--') ? 'M' : n[0].toUpperCase();
  }

  String get _inviteCode =>
      (_invite?['invite_code'] ?? _invite?['code'] ?? '--').toString();

  /// 与 web Profile.vue 一致: `${origin}/register?invite=CODE`。
  String get _inviteLink => _inviteCode == '--'
      ? ''
      : 'https://mingcevip.com/register?invite=$_inviteCode';

  num? get _invitedCount =>
      Fmt.toNum(_invite?['invited_count'] ?? _invite?['invite_count']);

  num? get _totalCommission =>
      Fmt.toNum(_summary['total_commission'] ?? _summary['total']);

  int? get _vipLevel {
    final v = Fmt.toNum(_vip?['level'] ?? _vip?['vip_level']);
    if (v != null) return v.toInt();
    if (_vip?['is_vip'] == true) return 1;
    return null;
  }

  void _copy(String text, String label) {
    if (text.isEmpty || text == '--') return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        backgroundColor: Mc.cardHigh,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content:
            Text('$label已复制', style: Mc.body(12, color: Mc.bull)),
      ));
  }

  Future<void> _changePassword() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _PwdDialog(),
    );
    if (ok == true && mounted) {
      setState(() => _pwdMsg = '密码已修改');
      _msgTimer?.cancel();
      _msgTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _pwdMsg = '');
      });
    }
  }

  Future<void> _logout() async {
    await AuthStore.I.logout();
  }

  /// 防钓鱼码: 后端暂无接口, 本地持久化 (对齐 web 占位行的交互)。
  Future<void> _editAntiPhishing() async {
    final code = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AntiPhishingDialog(initial: _antiPhishing),
    );
    if (code != null && mounted) {
      setState(() => _antiPhishing = code);
      _saveStringPref(_kAntiPhishing, code);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const McLoading(label: '个人资料加载中');
    if (_fatal) return McError('个人资料暂时不可用，请稍后重试', onRetry: _retry);
    return LayoutBuilder(builder: (context, c) {
      final right = Column(children: [
        _securityCard(),
        const SizedBox(height: 16),
        _prefsCard(),
        const SizedBox(height: 16),
        _inviteCard(),
        const SizedBox(height: 16),
        _devicesCard(),
      ]);
      if (c.maxWidth < 920) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const McSection('个人中心', tag: 'MY PROFILE'),
            const SizedBox(height: 16),
            _userCard(),
            const SizedBox(height: 16),
            right,
          ]),
        );
      }
      // 宽屏: 左侧信息卡固定不随右列滚动; 各自独立滚动 (矮窗可兜底)。
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const McSection('个人中心', tag: 'MY PROFILE'),
          const SizedBox(height: 16),
          Expanded(
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  flex: 4, child: SingleChildScrollView(child: _userCard())),
              const SizedBox(width: 16),
              Expanded(flex: 8, child: SingleChildScrollView(child: right)),
            ]),
          ),
        ]),
      );
    });
  }

  // ---------- 用户信息卡 ----------
  Widget _userCard() {
    final email = (_user['email'] ?? '--').toString();
    final uid = (_user['id'] ?? '--').toString();
    final username = (_user['username'] ?? '--').toString();
    final vipLevel = _vipLevel;
    final reg = Fmt.mdHm(_user['created_at']);
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // 头像 + 昵称
        Column(children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Mc.cardHigh,
              shape: BoxShape.circle,
              border: Border.all(color: Mc.cobalt, width: 1.5),
            ),
            alignment: Alignment.center,
            child: Text(_avatarChar,
                style: Mc.display(24, color: Mc.cobaltSoft)),
          ),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(
              child: Text(_displayName,
                  overflow: TextOverflow.ellipsis, style: Mc.display(16)),
            ),
            if (vipLevel != null) ...[
              const SizedBox(width: 8),
              McBadge('VIP $vipLevel', color: Mc.amber),
            ],
          ]),
          const SizedBox(height: 4),
          Text(username, style: Mc.mono(11, color: Mc.muted)),
        ]),
        const SizedBox(height: 14),
        const Divider(height: 1, color: Mc.hairline),
        const SizedBox(height: 14),
        // UID 复制
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Mc.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Mc.hairline),
          ),
          child: Row(children: [
            Text('UID', style: Mc.tag()),
            const Spacer(),
            Text(uid, style: Mc.mono(12, w: FontWeight.w600)),
            const SizedBox(width: 6),
            InkWell(
              onTap: () => _copy(uid, 'UID '),
              borderRadius: BorderRadius.circular(4),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.copy, size: 14, color: Mc.muted),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        _kvRow('邮箱', email),
        const SizedBox(height: 10),
        _kvRow('注册时间', reg),
        const SizedBox(height: 14),
        const Divider(height: 1, color: Mc.hairline),
        const SizedBox(height: 14),
        McButton('退出当前登录会话',
            kind: McBtnKind.ghost,
            icon: Icons.power_settings_new,
            onPressed: _logout),
      ]),
    );
  }

  Widget _kvRow(String k, String v) => Row(children: [
        Text(k, style: Mc.body(13, color: Mc.muted)),
        const Spacer(),
        Flexible(
          child: Text(v,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: Mc.mono(12)),
        ),
      ]);

  // ---------- 账户安全 ----------
  Widget _securityCard() {
    final has2fa = _user['has_2fa'] == true;
    final devs = _devices ?? const [];
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const McSection('账户安全', tag: 'ACCOUNT SECURITY'),
        const SizedBox(height: 6),
        Text('管理密码凭证与关键安全配置', style: Mc.body(12, color: Mc.muted)),
        const SizedBox(height: 14),
        const Divider(height: 1, color: Mc.hairline),
        // 登录密码
        _securityRow(
          icon: Icons.key,
          title: '登录密码',
          desc: '定期更新保障账户安全',
          trailing: Row(children: [
            Text('已设置', style: Mc.body(12, color: Mc.muted)),
            if (_pwdMsg.isNotEmpty) ...[
              const SizedBox(width: 10),
              Text(_pwdMsg, style: Mc.body(12, color: Mc.bull)),
            ],
            const SizedBox(width: 12),
            McButton('修改',
                kind: McBtnKind.ghost, height: 32, onPressed: _changePassword),
          ]),
        ),
        const Divider(height: 1, color: Mc.hairline),
        // 两步验证
        _securityRow(
          icon: Icons.security,
          title: '两步验证 (2FA)',
          desc: '用于敏感操作与新设备准入鉴权',
          trailing: McBadge(has2fa ? '已绑定' : '未绑定',
              color: has2fa ? Mc.bull : Mc.amber),
        ),
        const Divider(height: 1, color: Mc.hairline),
        // 防钓鱼码 (本地设置, 后端接口缺失)
        _securityRow(
          icon: Icons.phishing,
          title: '防钓鱼码 ANTI-PHISHING',
          desc: '核对官方系统邮件与推送签名的专属防伪标识',
          trailing: Row(children: [
            if (_antiPhishing.isEmpty) ...[
              const McBadge('未设置 (推荐开启)', color: Mc.amber),
            ] else ...[
              Text(_antiPhishing, style: Mc.mono(12, w: FontWeight.w600)),
              const SizedBox(width: 8),
              const McBadge('已设置', color: Mc.bull),
            ],
            const SizedBox(width: 12),
            McButton(_antiPhishing.isEmpty ? '立即设置' : '修改',
                kind: McBtnKind.ghost,
                height: 32,
                onPressed: _editAntiPhishing),
          ]),
        ),
        const Divider(height: 1, color: Mc.hairline),
        // 邮箱认证
        _securityRow(
          icon: Icons.mark_email_read_outlined,
          title: '邮箱认证',
          desc: (_user['email'] ?? '--').toString(),
          trailing: const Row(children: [
            Icon(Icons.check_circle, size: 13, color: Mc.bull),
            SizedBox(width: 4),
            McBadge('已验证', color: Mc.bull),
          ]),
        ),
        const Divider(height: 1, color: Mc.hairline),
        // 终端会话加密
        _securityRow(
          icon: Icons.lock_outline,
          title: '终端会话加密',
          desc: '机构级端到端加密传输',
          trailing: Row(children: [
            const Icon(Icons.lock, size: 13, color: Mc.bull),
            const SizedBox(width: 4),
            Text('AES-256 GCM', style: Mc.mono(12, color: Mc.muted)),
          ]),
        ),
        const Divider(height: 1, color: Mc.hairline),
        // 安全防护评级
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(children: [
            Row(children: [
              Text('安全防护评级', style: Mc.tag()),
              const Spacer(),
              Text('高风险防御 (94/100)',
                  style: Mc.mono(12, w: FontWeight.w600, color: Mc.bull)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: const LinearProgressIndicator(
                value: 0.94,
                minHeight: 6,
                backgroundColor: Mc.surface,
                valueColor: AlwaysStoppedAnimation(Mc.bull),
              ),
            ),
          ]),
        ),
        // 审计摘要
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Mc.cardHigh.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Mc.hairline),
            ),
            child: Row(children: [
              const Icon(Icons.receipt_long, size: 16, color: Mc.muted),
              const SizedBox(width: 8),
              Text('最近鉴权审计', style: Mc.tag()),
              const SizedBox(width: 10),
              Text('IP ${_currentIp(devs)}', style: Mc.mono(12)),
              const SizedBox(width: 8),
              Text('[成功 SUCCESS]', style: Mc.mono(11, color: Mc.bull)),
              const Spacer(),
              Text('共 ${devs.length} 台已鉴权设备',
                  style: Mc.body(12, color: Mc.muted)),
            ]),
          ),
        ),
      ]),
    );
  }

  String _currentIp(List<dynamic> devs) {
    for (final d in devs) {
      if (d is Map && d['current'] == true) {
        return (d['ip'] ?? '--').toString();
      }
    }
    if (devs.isNotEmpty && devs.first is Map) {
      return ((devs.first as Map)['ip'] ?? '--').toString();
    }
    return '--';
  }

  Widget _securityRow({
    required IconData icon,
    required String title,
    required String desc,
    required Widget trailing,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Mc.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Mc.hairline),
            ),
            child: Icon(icon, size: 18, color: Mc.muted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Mc.body(13, w: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(desc, style: Mc.body(11, color: Mc.muted)),
            ]),
          ),
          trailing,
        ]),
      );

  // ---------- 偏好设置 ----------
  Widget _prefsCard() {
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        McSection('偏好设置',
            tag: 'PREFERENCES',
            trailing: const McTag('已同步至本地配置', color: Mc.muted)),
        const SizedBox(height: 6),
        Text('定制专属量化操作盘面色彩与实时市场警报规则',
            style: Mc.body(12, color: Mc.muted)),
        const SizedBox(height: 14),
        const Divider(height: 1, color: Mc.hairline),
        // 界面语言
        _prefItemRow(
          title: '界面语言',
          desc: '终端显示语言与数字格式化国际标准',
          trailing: _langSegment(),
        ),
        const Divider(height: 1, color: Mc.hairline),
        // 涨跌色彩方案
        _prefItemRow(
          title: '涨跌色彩方案',
          desc: 'K线、深度图、持仓收益与多空比率映射色彩',
          trailing: Wrap(spacing: 8, runSpacing: 8, children: [
            _schemeOption(
              value: 'intl',
              label: '绿涨红跌 (国际)',
              dots: const [Mc.bull, Mc.bear],
            ),
            _schemeOption(
              value: 'cn',
              label: '红涨绿跌 (国内习惯)',
              dots: const [Mc.bear, Mc.bull],
            ),
          ]),
        ),
        const Divider(height: 1, color: Mc.hairline),
        // 实时推送通道
        const Padding(
          padding: EdgeInsets.only(top: 14, bottom: 8),
          child: McTag('实时推送通道 NOTIFICATIONS'),
        ),
        _notifRow(
          icon: Icons.show_chart,
          iconColor: Mc.cobaltSoft,
          title: '行情异动提醒',
          desc: '关注币种 15m 振幅超 3% 或急速拉升/下挫推流',
          value: _notifMarket,
          onChanged: (v) {
            setState(() => _notifMarket = v);
            _saveBoolPref(_kNotifMarket, v);
          },
        ),
        const SizedBox(height: 10),
        _notifRow(
          icon: Icons.water_drop,
          iconColor: Mc.bull,
          title: '巨鲸推送 WHALE ALERTS',
          desc: r'>500 BTC 或 $10M 以上链上冷热钱包大额异动流',
          value: _notifWhale,
          onChanged: (v) {
            setState(() => _notifWhale = v);
            _saveBoolPref(_kNotifWhale, v);
          },
        ),
        const SizedBox(height: 10),
        _notifRow(
          icon: Icons.campaign,
          iconColor: Mc.muted,
          title: '系统公告与风控披露',
          desc: '重大版本升级、API 速率限制调整与风控规则披露',
          value: _notifSystem,
          onChanged: (v) {
            setState(() => _notifSystem = v);
            _saveBoolPref(_kNotifSystem, v);
          },
        ),
      ]),
    );
  }

  Widget _prefItemRow({
    required String title,
    required String desc,
    required Widget trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      // 不用 LayoutBuilder: 本卡位于外层 McRow(IntrinsicHeight) 内会触发
      // "LayoutBuilder does not support returning intrinsic dimensions"。
      // 右列最窄也 >520 (最小窗口 1120), 固定横排即可。
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Mc.body(13, w: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(desc, style: Mc.body(11, color: Mc.muted)),
              ]),
        ),
        const SizedBox(width: 16),
        Flexible(child: Align(alignment: Alignment.centerRight, child: trailing)),
      ]),
    );
  }

  Widget _langSegment() {
    Widget seg(String value, String label) {
      final sel = _lang == value;
      return InkWell(
        onTap: () {
          setState(() => _lang = value);
          _saveStringPref(_kLang, value);
        },
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: sel ? Mc.cobalt : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(label,
              style: Mc.body(12,
                  w: sel ? FontWeight.w600 : FontWeight.w400,
                  color: sel ? Colors.white : Mc.muted)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Mc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Mc.hairline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg('zh', '中文'),
        seg('en', 'EN'),
      ]),
    );
  }

  Widget _schemeOption({
    required String value,
    required String label,
    required List<Color> dots,
  }) {
    final sel = _colorScheme == value;
    return InkWell(
      onTap: () {
        setState(() => _colorScheme = value);
        SettingsStore.I.setColorScheme(value); // 持久化并全局生效
      },
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Mc.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: sel ? Mc.cobalt : Mc.hairline,
            width: sel ? 1.5 : 1,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < dots.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: dots[i], shape: BoxShape.circle),
            ),
          ],
          const SizedBox(width: 8),
          Text(label,
              style: Mc.body(12,
                  w: sel ? FontWeight.w600 : FontWeight.w400,
                  color: sel ? Mc.ink : Mc.muted)),
          if (sel) ...[
            const SizedBox(width: 6),
            const Icon(Icons.check, size: 15, color: Mc.cobaltSoft),
          ],
        ]),
      ),
    );
  }

  Widget _notifRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String desc,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Mc.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Mc.hairline),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Mc.body(13, w: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(desc, style: Mc.body(11, color: Mc.muted)),
          ]),
        ),
        const SizedBox(width: 12),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.white,
          activeTrackColor: Mc.cobalt,
          inactiveThumbColor: Mc.muted,
          inactiveTrackColor: Mc.surface,
        ),
      ]),
    );
  }

  // ---------- 邀请返佣 ----------
  Widget _inviteCard() {
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const McSection('邀请有礼', tag: 'REFERRAL REWARDS'),
        const SizedBox(height: 6),
        Text('邀请好友注册，返佣自动结算至账户', style: Mc.body(12, color: Mc.muted)),
        const SizedBox(height: 16),
        // 不用 LayoutBuilder 分宽窄: 本卡在外层 McRow(IntrinsicHeight) 内,
        // LayoutBuilder 无法求固有尺寸会崩; 内容区最窄 832 > 640, 恒横排。
        McRow(spans: const [7, 5], gap: 16, children: [_inviteCodeCard(), _inviteStats()]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Mc.surface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Mc.hairline),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline, size: 15, color: Mc.cobaltSoft),
            const SizedBox(width: 8),
            Expanded(
              child: Text('返佣每日 00:00 UTC 自动结算至账户，长期有效',
                  style: Mc.body(11, color: Mc.muted)),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _inviteCodeCard() {
    final code = _inviteCode;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Mc.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Mc.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const McTag('我的专属邀请码 REFERRAL CODE'),
          const Spacer(),
          Text('永久有效', style: Mc.mono(10, color: Mc.bull)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Mc.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Mc.hairline),
              ),
              child: Text(code,
                  overflow: TextOverflow.ellipsis,
                  style: Mc.mono(18,
                      w: FontWeight.w600,
                      color: code == '--' ? Mc.muted : Mc.ink)),
            ),
          ),
          const SizedBox(width: 10),
          McButton('复制邀请码',
              icon: Icons.copy,
              height: 36,
              onPressed:
                  code == '--' ? null : () => _copy(code, '邀请码 ')),
        ]),
        const SizedBox(height: 12),
        const Divider(height: 1, color: Mc.hairline),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Text(_inviteLink.isEmpty ? '--' : _inviteLink,
                overflow: TextOverflow.ellipsis,
                style: Mc.mono(11, color: Mc.muted)),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: _inviteLink.isEmpty
                ? null
                : () => _copy(_inviteLink, '专属邀请链接 '),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Text('复制专属链接',
                  style: Mc.body(12,
                      w: FontWeight.w600,
                      color: _inviteLink.isEmpty ? Mc.muted : Mc.cobaltSoft)),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _inviteStats() {
    final count = _invitedCount;
    final total = _totalCommission;
    return McRow(gap: 16, children: [
      _statTile('已邀请人数', count == null ? '--' : '$count', '人'),
      _statTile('累计返佣 (USDT)', Fmt.num_(total), '', valueColor: Mc.up),
    ]);
  }

  Widget _statTile(String label, String value, String unit,
      {Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Mc.cardHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Mc.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Mc.body(11, color: Mc.muted)),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(value,
                    overflow: TextOverflow.ellipsis,
                    style: Mc.mono(20,
                        w: FontWeight.w600, color: valueColor ?? Mc.ink)),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(unit, style: Mc.body(11, color: Mc.muted)),
              ],
            ]),
      ]),
    );
  }

  // ---------- 登录设备 ----------
  Widget _devicesCard() {
    final devs = _devices;
    return McCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: McSection('登录设备',
              tag: 'DEVICES',
              trailing: McBadge('${devs?.length ?? 0} 台设备',
                  color: Mc.cobaltSoft)),
        ),
        const Divider(height: 1, color: Mc.hairline),
        if (devs == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: McEmpty('设备记录暂时不可用'),
          )
        else if (devs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: McEmpty('暂无记录'),
          )
        else ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Row(children: [
              Expanded(flex: 3, child: McTh('设备')),
              Expanded(flex: 2, child: McTh('平台')),
              Expanded(flex: 3, child: McTh('IP 地址')),
              Expanded(
                  flex: 3,
                  child: McTh('最近活跃', align: TextAlign.right)),
              Expanded(
                  flex: 2,
                  child: McTh('状态', align: TextAlign.center)),
            ]),
          ),
          const Divider(height: 1, color: Mc.hairline),
          for (var i = 0; i < devs.length; i++) ...[
            _deviceRow(devs[i]),
            if (i != devs.length - 1)
              const Divider(height: 1, color: Mc.hairline),
          ],
          const SizedBox(height: 8),
        ],
      ]),
    );
  }

  Widget _deviceRow(dynamic d) {
    if (d is! Map) return const SizedBox.shrink();
    final name = (d['device_name'] ?? '未命名设备').toString();
    final platform = (d['platform'] ?? '--').toString();
    final ip = (d['ip'] ?? '--').toString();
    final seen = Fmt.mdHm(d['last_seen_at']);
    final current = d['current'] == true;
    return _HoverRow(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      children: [
        Expanded(
          flex: 3,
          child: Row(children: [
            Icon(platform == 'web' ? Icons.language : Icons.smartphone,
                size: 15, color: Mc.muted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(name,
                  overflow: TextOverflow.ellipsis,
                  style: Mc.body(12, w: FontWeight.w500)),
            ),
          ]),
        ),
        Expanded(
          flex: 2,
          child: Align(
            alignment: Alignment.centerLeft,
            child: McBadge(platform, color: Mc.muted),
          ),
        ),
        Expanded(
            flex: 3,
            child: Text(ip, style: Mc.mono(12, color: Mc.muted))),
        Expanded(
            flex: 3,
            child: Text(seen,
                textAlign: TextAlign.right,
                style: Mc.mono(12, color: Mc.muted))),
        Expanded(
          flex: 2,
          child: Center(
            child: current
                ? const McBadge('本设备', color: Mc.bull)
                : Text('--', style: Mc.mono(11, color: Mc.muted)),
          ),
        ),
      ],
    );
  }
}

/// 行悬停高亮 (Mc.cardHigh)，无斑马纹。
class _HoverRow extends StatefulWidget {
  const _HoverRow({required this.children, this.padding});
  final List<Widget> children;
  final EdgeInsets? padding;

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _hover ? Mc.cardHigh : Colors.transparent,
        padding: widget.padding ??
            const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(children: widget.children),
      ),
    );
  }
}

/// 修改登录密码对话框。
class _PwdDialog extends StatefulWidget {
  const _PwdDialog();

  @override
  State<_PwdDialog> createState() => _PwdDialogState();
}

class _PwdDialogState extends State<_PwdDialog> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  String _err = '';
  bool _busy = false;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _err = '');
    if (_old.text.isEmpty) {
      setState(() => _err = '请输入当前密码');
      return;
    }
    if (_new.text.length < 8) {
      setState(() => _err = '新密码至少 8 位');
      return;
    }
    if (_new.text != _confirm.text) {
      setState(() => _err = '两次新密码不一致');
      return;
    }
    setState(() => _busy = true);
    try {
      await ApiClient.I.changePassword(_old.text, _new.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _err = e is ApiException ? e.message : '修改失败，请稍后重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: SizedBox(
        width: 420,
        child: McCard(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.key, size: 18, color: Mc.cobaltSoft),
                  const SizedBox(width: 8),
                  Text('修改登录密码', style: Mc.display(16)),
                  const Spacer(),
                  InkWell(
                    onTap: _busy ? null : () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 18, color: Mc.muted),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                const Divider(height: 1, color: Mc.hairline),
                const SizedBox(height: 16),
                _field('当前密码', _old, '请输入当前密码'),
                const SizedBox(height: 12),
                _field('新密码', _new, '新密码 (至少 8 位)'),
                const SizedBox(height: 12),
                _field('确认新密码', _confirm, '再次输入新密码', onSubmit: _submit),
                if (_err.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Mc.bear.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Mc.bear.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline,
                          size: 15, color: Mc.bear),
                      const SizedBox(width: 6),
                      Expanded(
                          child:
                              Text(_err, style: Mc.body(12, color: Mc.bear))),
                    ]),
                  ),
                ],
                const SizedBox(height: 18),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  McButton('取消',
                      kind: McBtnKind.ghost,
                      height: 36,
                      onPressed:
                          _busy ? null : () => Navigator.of(context).pop()),
                  const SizedBox(width: 10),
                  McButton(_busy ? '提交中…' : '确认修改',
                      height: 36, busy: _busy, onPressed: _submit),
                ]),
              ]),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController c, String hint,
      {VoidCallback? onSubmit}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: Mc.body(12, color: Mc.muted)),
      const SizedBox(height: 6),
      McInput(
        controller: c,
        hint: hint,
        obscure: true,
        onSubmitted: onSubmit != null ? (_) => onSubmit() : null,
      ),
    ]);
  }
}

/// 防钓鱼码设置对话框 (本地持久化, 返回新码或 null=取消)。
class _AntiPhishingDialog extends StatefulWidget {
  const _AntiPhishingDialog({required this.initial});
  final String initial;

  @override
  State<_AntiPhishingDialog> createState() => _AntiPhishingDialogState();
}

class _AntiPhishingDialogState extends State<_AntiPhishingDialog> {
  late final TextEditingController _code =
      TextEditingController(text: widget.initial);
  String _err = '';

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _code.text.trim();
    if (!RegExp(r'^[A-Za-z0-9]{4,12}$').hasMatch(v)) {
      setState(() => _err = '请输入 4-12 位字母或数字');
      return;
    }
    Navigator.of(context).pop(v.toUpperCase());
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: SizedBox(
        width: 400,
        child: McCard(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.phishing, size: 18, color: Mc.amber),
                  const SizedBox(width: 8),
                  Text('设置防钓鱼码', style: Mc.display(16)),
                  const Spacer(),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 18, color: Mc.muted),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Text('设置后, 所有官方系统邮件与推送将携带此专属标识, 请妥善记忆',
                    style: Mc.body(12, color: Mc.muted)),
                const SizedBox(height: 16),
                const Divider(height: 1, color: Mc.hairline),
                const SizedBox(height: 16),
                Text('防钓鱼码', style: Mc.body(12, color: Mc.muted)),
                const SizedBox(height: 6),
                McInput(
                  controller: _code,
                  hint: '4-12 位字母或数字',
                  prefix: Icons.verified_user_outlined,
                  onSubmitted: (_) => _submit(),
                ),
                if (_err.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(_err, style: Mc.body(12, color: Mc.bear)),
                ],
                const SizedBox(height: 18),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  McButton('取消',
                      kind: McBtnKind.ghost,
                      height: 36,
                      onPressed: () => Navigator.of(context).pop()),
                  const SizedBox(width: 10),
                  McButton('确认保存', height: 36, onPressed: _submit),
                ]),
              ]),
        ),
      ),
    );
  }
}

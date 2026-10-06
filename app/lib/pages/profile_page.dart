import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/l10n.dart';
import '../core/color_pref.dart';
import '../core/notify_pref.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/auth.dart';
import 'change_password_page.dart';
import 'fund_password_page.dart';
import 'totp_page.dart';
import 'anti_phishing_page.dart';
import 'devices_page.dart';
import 'language_page.dart';
import 'price_alerts_page.dart';

/// 用户中心: 顶部用户卡 + 三个 tab (个人资料 / 安全设置 / 偏好设置).
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  bool _busy = false; // 上传/保存中防连点
  late final TabController _tab;

  AuthStore get _auth => AuthStore.instance;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    if (_busy) return;
    final XFile? picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 1024, maxHeight: 1024);
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await picked.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        _toast(tr('avatar_too_large'));
        return;
      }
      await _auth.uploadAvatar(bytes, picked.name);
      _toast(tr('avatar_updated'));
    } catch (_) {
      _toast(tr('avatar_upload_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editNickname() async {
    final controller = TextEditingController(text: _auth.nickname ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: McColors.surfaceContainerLow,
        title: Text(tr('edit_nickname'),
            style: McText.sans(size: 15, weight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 32,
          style: McText.sans(size: 14),
          decoration: InputDecoration(
            hintText: tr('nickname_hint'),
            hintStyle:
                McText.sans(size: 14, color: McColors.onSurfaceVariant),
            counterStyle:
                McText.sans(size: 12, color: McColors.onSurfaceVariant),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('cancel'),
                style: McText.sans(color: McColors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(tr('save'), style: McText.sans(color: McColors.primarySoft)),
          ),
        ],
      ),
    );
    if (name == null || name == (_auth.nickname ?? '')) return;
    setState(() => _busy = true);
    try {
      await _auth.updateNickname(name);
      _toast(tr('nickname_updated'));
    } catch (_) {
      _toast(tr('update_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: McColors.surfaceContainerLow,
        title: Text(tr('logout'),
            style: McText.sans(size: 15, weight: FontWeight.w700)),
        content: Text(tr('logout_confirm'),
            style: McText.sans(size: 13, color: McColors.onSurfaceVariant)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel'),
                style: McText.sans(color: McColors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('exit'), style: McText.sans(color: McColors.bear)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _auth.logout();
    if (mounted) Navigator.of(context).pop();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: McText.sans(size: 13)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: McColors.surfaceContainerHigh,
        duration: const Duration(seconds: 2),
      ));
  }

  void _todo() => _toast(tr('coming_soon'));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: McColors.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: McColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: McColors.onSurface),
        title: Text(tr('user_center'),
            style: McText.sans(size: 15, weight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tab,
          labelColor: McColors.primary,
          unselectedLabelColor: McColors.onSurfaceVariant,
          labelStyle: McText.sans(size: 13, weight: FontWeight.w600),
          unselectedLabelStyle: McText.sans(size: 13),
          indicatorColor: McColors.primary,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: McColors.outlineVariant.withValues(alpha: 0.3),
          tabs: [
            Tab(text: tr('tab_profile')),
            Tab(text: tr('tab_security')),
            Tab(text: tr('tab_preference')),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: _auth,
        builder: (context, _) {
          return TabBarView(
            controller: _tab,
            children: [
              _profileTab(),
              _securityTab(),
              _preferenceTab(),
            ],
          );
        },
      ),
    );
  }

  // ---------------- 个人资料 ----------------
  Widget _profileTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 24),
      children: [
        // 头像: 居中大头 + 更换提示
        Center(
          child: GestureDetector(
            onTap: _pickAvatar,
            child: Stack(
              children: [
                McAvatar(
                  name: _auth.displayName,
                  url: _auth.avatarUrl,
                  size: 96,
                  radius: 20,
                ),
                if (_busy)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: McColors.primarySoft),
                        ),
                      ),
                    ),
                  )
                else
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: McColors.surfaceContainerHigh,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color:
                                McColors.outlineVariant.withValues(alpha: 0.6)),
                      ),
                      child: const Icon(Icons.photo_camera,
                          size: 14, color: McColors.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(tr('change_avatar_hint'),
              style:
                  McText.sans(size: 12, color: McColors.onSurfaceVariant)),
        ),
        const SizedBox(height: 24),

        _row(
          label: tr('nickname'),
          value: _auth.displayName,
          trailing: const Icon(Icons.chevron_right,
              size: 18, color: McColors.onSurfaceVariant),
          onTap: _editNickname,
        ),
        const SizedBox(height: 10),
        _row(label: tr('username'), value: _auth.username ?? ''),
        const SizedBox(height: 10),
        _row(label: tr('email'), value: _auth.email ?? ''),
        const SizedBox(height: 32),

        // 退出登录
        GestureDetector(
          onTap: _logout,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: McColors.bear.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: McColors.bear.withValues(alpha: 0.35)),
            ),
            alignment: Alignment.center,
            child: Text(tr('logout'),
                style: McText.sans(
                    size: 14,
                    weight: FontWeight.w600,
                    color: McColors.bear)),
          ),
        ),
      ],
    );
  }

  // ---------------- 安全设置 ----------------
  Widget _securityTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 24),
      children: [
        _sectionTitle(tr('sec_account')),
        const SizedBox(height: 10),
        _row(
          label: tr('sec_login_password'),
          value: tr('status_set'),
          trailing: _chevron(),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const ChangePasswordPage())),
        ),
        const SizedBox(height: 10),
        _row(
          label: tr('sec_fund_password'),
          value: _auth.hasFundPassword
              ? tr('status_set')
              : tr('status_unset'),
          trailing: _chevron(),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const FundPasswordPage())),
        ),
        const SizedBox(height: 10),
        _row(
          label: tr('sec_2fa'),
          value: _auth.has2fa ? tr('status_bound') : tr('status_unbound'),
          trailing: _chevron(),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TotpPage())),
        ),
        const SizedBox(height: 24),
        _sectionTitle(tr('sec_device_verify')),
        const SizedBox(height: 10),
        _row(
          label: tr('sec_email_verify'),
          value: _auth.email ?? tr('status_unbound'),
        ),
        const SizedBox(height: 10),
        _row(
          label: tr('sec_devices'),
          value: '',
          trailing: _chevron(),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DevicesPage())),
        ),
        const SizedBox(height: 24),
        _row(
          label: tr('sec_anti_phishing'),
          value: _auth.antiPhishingCode != null
              ? tr('status_set')
              : tr('status_unset'),
          trailing: _chevron(),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const AntiPhishingPage())),
        ),
      ],
    );
  }

  // ---------------- 偏好设置 ----------------
  Widget _preferenceTab() {
    return ListenableBuilder(
      listenable: Listenable.merge([ColorPref.instance, NotifyPref.instance]),
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 20, 14, 24),
          children: [
            _sectionTitle(tr('pref_general')),
            const SizedBox(height: 10),
            _row(
              label: tr('pref_language'),
              value: L10n.instance.current.nativeName,
              trailing: _chevron(),
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const LanguagePage())),
            ),
            const SizedBox(height: 10),
            _row(
                label: tr('pref_currency'),
                value: 'USD',
                trailing: _chevron(),
                onTap: _todo),
            const SizedBox(height: 10),
            _row(
              label: tr('pref_price_color'),
              value: ColorPref.instance.redUp
                  ? tr('color_red_up')
                  : tr('color_green_up'),
              trailing: _chevron(),
              onTap: _pickPriceColor,
            ),
            const SizedBox(height: 24),
            _sectionTitle(tr('pref_notify')),
            const SizedBox(height: 10),
            _switchRow(
              label: tr('pref_notify_market'),
              value: NotifyPref.instance.market,
              onChanged: (v) => NotifyPref.instance.setMarket(v),
            ),
            const SizedBox(height: 10),
            _switchRow(
              label: tr('pref_notify_notice'),
              value: NotifyPref.instance.notice,
              onChanged: (v) => NotifyPref.instance.setNotice(v),
            ),
            const SizedBox(height: 10),
            _row(
              label: tr('pref_price_alert'),
              value: '',
              trailing: _chevron(),
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const PriceAlertsPage())),
            ),
          ],
        );
      },
    );
  }

  /// 涨跌配色选择: 绿涨红跌 / 红涨绿跌.
  Future<void> _pickPriceColor() async {
    final redUp = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cur = ColorPref.instance.redUp;
        Widget opt(bool v, String label) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(ctx, v),
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: cur == v
                      ? McColors.primaryContainer.withValues(alpha: 0.15)
                      : McColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: cur == v
                        ? McColors.primary.withValues(alpha: 0.6)
                        : McColors.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    // 涨色块 + 跌色块直观预览
                    Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                            color: v ? McColors.bear : McColors.bull,
                            borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 4),
                    Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                            color: v ? McColors.bull : McColors.bear,
                            borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(label,
                            style: McText.sans(
                                size: 14,
                                weight: cur == v
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: Colors.white))),
                    if (cur == v)
                      const Icon(Icons.check_circle,
                          size: 18, color: McColors.primary),
                  ],
                ),
              ),
            );
        return AlertDialog(
          backgroundColor: McColors.surfaceContainerLow,
          title: Text(tr('pref_price_color'),
              style: McText.sans(size: 15, weight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              opt(false, tr('color_green_up')),
              opt(true, tr('color_red_up')),
            ],
          ),
        );
      },
    );
    if (redUp == null) return;
    await ColorPref.instance.setRedUp(redUp);
  }

  /// 通知开关行 (Switch).
  Widget _switchRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: McColors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: McText.sans(size: 13, color: McColors.onSurfaceVariant)),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: McColors.primary,
            activeTrackColor: McColors.primaryContainer.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }

  // ---------------- 公共小组件 ----------------
  Widget _sectionTitle(String text) {
    return Text(text,
        style: McText.sans(
            size: 12,
            weight: FontWeight.w600,
            color: McColors.onSurfaceVariant,
            letterSpacing: 0.5));
  }

  Widget _chevron() =>
      const Icon(Icons.chevron_right, size: 18, color: McColors.onSurfaceVariant);

  Widget _row({
    required String label,
    required String value,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: McColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: McColors.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Text(label,
                style: McText.sans(
                    size: 13, color: McColors.onSurfaceVariant)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: McText.sans(size: 14, color: Colors.white),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 4), trailing],
          ],
        ),
      ),
    );
  }
}

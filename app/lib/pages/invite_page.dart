import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../services/api.dart';
import '../services/invite_api.dart';

/// 邀请好友页: 专属邀请码/链接 + 上级绑定状态 + 补填入口.
/// 规则提示 (V0.7 第一节): 本人或任意层级下级购买成功后, 将无法补填邀请码绑定上级.
class InvitePage extends StatefulWidget {
  const InvitePage({super.key});

  @override
  State<InvitePage> createState() => _InvitePageState();
}

class _InvitePageState extends State<InvitePage> {
  InviteInfo? _info;
  String? _error;
  bool _busy = false;

  final _bindCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bindCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final info = await InviteApi.me();
      if (mounted) setState(() => _info = info);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = tr('net_error_retry'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _bind() async {
    final code = _bindCtrl.text.trim();
    if (code.isEmpty) {
      _toast(tr('inv_err_empty'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final info = await InviteApi.bind(code);
      if (mounted) {
        setState(() => _info = info);
        _toast(tr('inv_bind_success'));
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = tr('net_error_retry'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _copy(String text, String toast) {
    Clipboard.setData(ClipboardData(text: text));
    _toast(toast);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: McText.sans(size: 13)),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        backgroundColor: McColors.surfaceContainerHighest,
      ),
    );
  }

  String get _inviteLink {
    final base = Uri.base;
    // origin 仅对 http/https 有效; 本地调试 Uri.base 是 file:// 会抛 StateError.
    final isWeb = base.scheme == 'http' || base.scheme == 'https';
    final origin = isWeb ? base.origin : McApi.baseUrl;
    return '$origin/?invite=${_info?.inviteCode ?? ''}';
  }

  /// APP 内可直接唤起的 scheme 链接 (Android intent-filter 已配 noahsark://invite)
  String get _inviteAppLink =>
      'noahsark://invite?invite=${_info?.inviteCode ?? ''}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: McColors.surface,
      appBar: AppBar(
        backgroundColor: McColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: McColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(tr('inv_title'), style: McText.display(size: 16, weight: FontWeight.w700)),
      ),
      body: _busy && _info == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
              children: [
                if (_error != null) ...[
                  _errorBox(_error!),
                  const SizedBox(height: 12),
                ],
                if (_info != null) ...[
                  _codeCard(),
                  const SizedBox(height: 16),
                  _inviterCard(),
                  const SizedBox(height: 16),
                  _ruleCard(),
                ],
              ],
            ),
    );
  }

  Widget _errorBox(String msg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: McColors.bear.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: McColors.bear.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: McColors.bear),
          const SizedBox(width: 8),
          Expanded(child: Text(msg, style: McText.sans(size: 12, color: McColors.bear))),
        ],
      ),
    );
  }

  /// 专属邀请码 + 邀请链接
  Widget _codeCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: McColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: McColors.surfaceContainerHigh),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('inv_my_code'), style: McText.mono(size: 12, color: McColors.onSurfaceVariant, letterSpacing: 1)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: McColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: McColors.primaryContainer.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _info!.inviteCode,
                    style: McText.mono(size: 20, weight: FontWeight.w700, color: McColors.primarySoft, letterSpacing: 2),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _copyButton(tr('assets_copy'), () => _copy(_info!.inviteCode, tr('inv_code_copied'))),
            ],
          ),
          const SizedBox(height: 12),
          Text(tr('inv_link'), style: McText.mono(size: 12, color: McColors.onSurfaceVariant, letterSpacing: 1)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  _inviteLink,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: McText.mono(size: 12, color: McColors.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 10),
              _copyButton(tr('inv_copy_link'), () => _copy(_inviteLink, tr('inv_link_copied'))),
            ],
          ),
          const SizedBox(height: 12),
          Text(tr('inv_app_link'), style: McText.mono(size: 12, color: McColors.onSurfaceVariant, letterSpacing: 1)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  _inviteAppLink,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: McText.mono(size: 12, color: McColors.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 10),
              _copyButton(tr('assets_copy'), () => _copy(_inviteAppLink, tr('inv_app_link_copied'))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _copyButton(String text, VoidCallback onTap) {
    return Material(
      color: McColors.primaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            text,
            style: McText.sans(size: 12, weight: FontWeight.w700, color: Colors.white),
          ),
        ),
      ),
    );
  }

  /// 上级绑定状态 + 补填入口
  Widget _inviterCard() {
    final info = _info!;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: McColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: McColors.surfaceContainerHigh),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('inv_my_inviter'), style: McText.display(size: 15, weight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (info.bound) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: McColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: McColors.surfaceContainerHigh),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_pin, size: 18, color: McColors.primarySoft),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      info.inviterUsername ?? '${tr('assets_user_prefix')}${info.inviterId}',
                      style: McText.sans(size: 14, weight: FontWeight.w600),
                    ),
                  ),
                  Text(tr('inv_bound_fixed'), style: McText.mono(size: 11, color: McColors.tertiary)),
                ],
              ),
            ),
          ] else if (info.canBind) ...[
            Text(
              tr('inv_can_bind'),
              style: McText.sans(size: 12, color: McColors.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _bindCtrl,
                    style: McText.mono(size: 13),
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: tr('inv_code_hint'),
                      hintStyle: McText.sans(size: 13, color: McColors.onSurfaceVariant),
                      filled: true,
                      fillColor: McColors.surfaceContainerLowest,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: McColors.outlineVariant.withValues(alpha: 0.6)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: McColors.outlineVariant.withValues(alpha: 0.6)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: McColors.primaryContainer, width: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _copyButton(tr('inv_bind'), _busy ? () {} : _bind),
              ],
            ),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: McColors.bear.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: McColors.bear.withValues(alpha: 0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lock_outline, size: 16, color: McColors.bear),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('inv_cannot_bind'), style: McText.sans(size: 13, weight: FontWeight.w700, color: McColors.bear)),
                        const SizedBox(height: 4),
                        Text(
                          info.bindBlockReason ?? tr('inv_cannot_bind_default'),
                          style: McText.sans(size: 12, color: McColors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 规则说明 (文档要求首次购买前提示)
  Widget _ruleCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: McColors.surfaceContainerHigh.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, size: 16, color: McColors.primarySoft),
              const SizedBox(width: 6),
              Text(tr('inv_rules_title'), style: McText.sans(size: 13, weight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            tr('inv_rules_body'),
            style: McText.sans(size: 12, color: McColors.onSurfaceVariant, height: 1.7),
          ),
        ],
      ),
    );
  }
}

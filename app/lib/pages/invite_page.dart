import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
      if (mounted) setState(() => _error = '网络错误, 请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _bind() async {
    final code = _bindCtrl.text.trim();
    if (code.isEmpty) {
      _toast('请输入邀请码');
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
        _toast('绑定成功, 上级关系永久固定');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '网络错误, 请稍后重试');
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
    final origin = base.hasScheme ? base.origin : McApi.baseUrl;
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
        title: Text('邀请好友', style: McText.display(size: 16, weight: FontWeight.w700)),
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
          Text('我的专属邀请码', style: McText.mono(size: 12, color: McColors.onSurfaceVariant, letterSpacing: 1)),
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
              _copyButton('复制', () => _copy(_info!.inviteCode, '邀请码已复制')),
            ],
          ),
          const SizedBox(height: 12),
          Text('邀请链接', style: McText.mono(size: 12, color: McColors.onSurfaceVariant, letterSpacing: 1)),
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
              _copyButton('复制链接', () => _copy(_inviteLink, '邀请链接已复制')),
            ],
          ),
          const SizedBox(height: 12),
          Text('APP 直开链接', style: McText.mono(size: 12, color: McColors.onSurfaceVariant, letterSpacing: 1)),
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
              _copyButton('复制', () => _copy(_inviteAppLink, 'APP链接已复制')),
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
          Text('我的上级', style: McText.display(size: 15, weight: FontWeight.w700)),
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
                      info.inviterUsername ?? '用户 #${info.inviterId}',
                      style: McText.sans(size: 14, weight: FontWeight.w600),
                    ),
                  ),
                  Text('已绑定 · 永久固定', style: McText.mono(size: 11, color: McColors.tertiary)),
                ],
              ),
            ),
          ] else if (info.canBind) ...[
            Text(
              '尚未绑定上级, 可补填邀请码',
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
                      hintText: '输入邀请码',
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
                _copyButton('绑定', _busy ? () {} : _bind),
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
                        Text('不可补填邀请码', style: McText.sans(size: 13, weight: FontWeight.w700, color: McColors.bear)),
                        const SizedBox(height: 4),
                        Text(
                          info.bindBlockReason ?? '当前不满足补绑条件',
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
              Text('绑定规则', style: McText.sans(size: 13, weight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '· 上下级关系一旦绑定永久固定, 不能更换上级\n'
            '· 没有邀请码也可以正常注册和购买产品\n'
            '· 本人或任意层级下级购买成功后, 将无法补填邀请码绑定上级\n'
            '· 返佣仅统计三代内下级, 补绑资格检查覆盖全部层级',
            style: McText.sans(size: 12, color: McColors.onSurfaceVariant, height: 1.7),
          ),
        ],
      ),
    );
  }
}

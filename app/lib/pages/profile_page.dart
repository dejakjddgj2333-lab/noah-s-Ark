import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/auth.dart';

/// 个人信息页: 头像 (点按更换) + 昵称修改 + 只读账号信息 + 退出登录.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _busy = false; // 上传/保存中防连点

  AuthStore get _auth => AuthStore.instance;

  Future<void> _pickAvatar() async {
    if (_busy) return;
    final XFile? picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 1024, maxHeight: 1024);
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await picked.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        _toast('图片超过 10MB');
        return;
      }
      await _auth.uploadAvatar(bytes, picked.name);
      _toast('头像已更新');
    } catch (_) {
      _toast('头像上传失败');
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
        title: Text('修改昵称',
            style: McText.sans(size: 15, weight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 32,
          style: McText.sans(size: 14),
          decoration: InputDecoration(
            hintText: '输入昵称, 留空则显示用户名',
            hintStyle:
                McText.sans(size: 14, color: McColors.onSurfaceVariant),
            counterStyle:
                McText.sans(size: 12, color: McColors.onSurfaceVariant),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消',
                style: McText.sans(color: McColors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text('保存', style: McText.sans(color: McColors.primarySoft)),
          ),
        ],
      ),
    );
    if (name == null || name == (_auth.nickname ?? '')) return;
    setState(() => _busy = true);
    try {
      await _auth.updateNickname(name);
      _toast('昵称已更新');
    } catch (_) {
      _toast('修改失败');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: McColors.surfaceContainerLow,
        title:
            Text('退出登录', style: McText.sans(size: 15, weight: FontWeight.w700)),
        content: Text('退出后聊天记录将保留在本机, 可随时重新登录.',
            style: McText.sans(size: 13, color: McColors.onSurfaceVariant)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消',
                style: McText.sans(color: McColors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('退出', style: McText.sans(color: McColors.bear)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: McColors.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: McColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: McColors.onSurface),
        title:
            Text('个人信息', style: McText.sans(size: 15, weight: FontWeight.w700)),
      ),
      body: ListenableBuilder(
        listenable: _auth,
        builder: (context, _) {
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
                                    strokeWidth: 2,
                                    color: McColors.primarySoft),
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
                                  color: McColors.outlineVariant
                                      .withValues(alpha: 0.6)),
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
                child: Text('点击更换头像',
                    style: McText.sans(
                        size: 12, color: McColors.onSurfaceVariant)),
              ),
              const SizedBox(height: 24),

              // 昵称 (可改)
              _row(
                label: '昵称',
                value: _auth.displayName,
                trailing: const Icon(Icons.chevron_right,
                    size: 18, color: McColors.onSurfaceVariant),
                onTap: _editNickname,
              ),
              const SizedBox(height: 10),
              // 只读信息
              _row(label: '用户名', value: _auth.username ?? ''),
              const SizedBox(height: 10),
              _row(label: '邮箱', value: _auth.email ?? ''),
              const SizedBox(height: 32),

              // 退出登录
              GestureDetector(
                onTap: _logout,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: McColors.bear.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: McColors.bear.withValues(alpha: 0.35)),
                  ),
                  alignment: Alignment.center,
                  child: Text('退出登录',
                      style: McText.sans(
                          size: 14,
                          weight: FontWeight.w600,
                          color: McColors.bear)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row({
    required String label,
    required String value,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
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
            const Spacer(),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: McText.sans(size: 14, color: Colors.white),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 6), trailing],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../services/chat_api.dart';

/// 拉黑管理: 我拉黑的用户列表, 可取消拉黑.
class BlockedUsersPage extends StatefulWidget {
  const BlockedUsersPage({super.key});

  @override
  State<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends State<BlockedUsersPage> {
  bool _loading = true;
  List<BlockedUser> _list = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _list = await ChatApi.blockedUsers();
    } catch (_) {
      _list = const [];
    }
    if (mounted) setState(() => _loading = false);
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

  Future<void> _unblock(BlockedUser u) async {
    try {
      await ChatApi.unblockUser(u.userId);
      _toast(tr('unblock_done'));
      _load();
    } catch (e) {
      _toast(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: McColors.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: McColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: McColors.onSurface),
        title: Text(tr('blocked_users'),
            style: McText.sans(size: 15, weight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: McColors.primarySoft),
              ),
            )
          : _list.isEmpty
              ? Center(
                  child: Text(tr('blocked_empty'),
                      style: McText.sans(
                          size: 13, color: McColors.onSurfaceVariant)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: _list.length,
                  separatorBuilder: (_, i) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final u = _list[i];
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: McColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: McColors.outlineVariant
                                .withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(u.displayName,
                                style: McText.sans(
                                    size: 14, weight: FontWeight.w600)),
                          ),
                          TextButton(
                            onPressed: () => _unblock(u),
                            child: Text(tr('unblock'),
                                style: McText.sans(
                                    size: 13, color: McColors.primary)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

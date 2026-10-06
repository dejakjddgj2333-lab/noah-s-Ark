import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../services/chat_api.dart';

/// 发起群聊: 群名输入 + 好友多选, 创建成功后返回 Conversation (pop result).
class GroupCreatePage extends StatefulWidget {
  const GroupCreatePage({super.key});

  @override
  State<GroupCreatePage> createState() => _GroupCreatePageState();
}

class _GroupCreatePageState extends State<GroupCreatePage> {
  final _name = TextEditingController();
  List<ChatUser> _friends = [];
  final Set<int> _selected = {};
  bool _loading = true;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await ChatApi.friends();
      if (!mounted) return;
      setState(() {
        _friends = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
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

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _toast(tr('grp_enter_name'));
      return;
    }
    if (_selected.isEmpty) {
      _toast(tr('grp_select_member'));
      return;
    }
    setState(() => _creating = true);
    try {
      final conv = await ChatApi.createGroup(name, _selected.toList());
      if (!mounted) return;
      Navigator.of(context).pop(conv);
    } catch (_) {
      if (!mounted) return;
      setState(() => _creating = false);
      _toast(tr('grp_create_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: McColors.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: McColors.surface,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: McColors.onSurface),
        title: Text(tr('grp_create_title'),
            style: McText.sans(size: 16, weight: FontWeight.w700)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _creating ? null : _create,
              child: _creating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: McColors.primarySoft),
                    )
                  : Text(tr('grp_create'),
                      style: McText.sans(
                          size: 14,
                          weight: FontWeight.w700,
                          color: McColors.primarySoft)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: McColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: McColors.outlineVariant.withValues(alpha: 0.6)),
              ),
              child: TextField(
                controller: _name,
                style: McText.sans(size: 14),
                decoration: InputDecoration(
                  icon: const Icon(Icons.group_outlined,
                      size: 18, color: McColors.onSurfaceVariant),
                  hintText: tr('grp_name_hint'),
                  hintStyle:
                      McText.sans(size: 14, color: McColors.onSurfaceVariant),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Row(
              children: [
                Text(tr('grp_select_members'),
                    style:
                        McText.mono(size: 12, color: McColors.onSurfaceVariant)),
                const Spacer(),
                Text(tr('grp_selected').replaceAll('{n}', '${_selected.length}'),
                    style:
                        McText.mono(size: 12, color: McColors.primarySoft)),
              ],
            ),
          ),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: McColors.primarySoft),
        ),
      );
    }
    if (_friends.isEmpty) {
      return Center(
        child: Text(tr('grp_no_friends'),
            style: McText.sans(size: 13, color: McColors.onSurfaceVariant)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
      itemCount: _friends.length,
      separatorBuilder: (_, _) => Divider(
          height: 1, color: McColors.outlineVariant.withValues(alpha: 0.3)),
      itemBuilder: (context, i) {
        final u = _friends[i];
        final sel = _selected.contains(u.id);
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: _avatar(u.username),
          title: Text(u.username,
              style: McText.sans(size: 14, weight: FontWeight.w600)),
          onTap: () => setState(() {
            if (sel) {
              _selected.remove(u.id);
            } else {
              _selected.add(u.id);
            }
          }),
          trailing: Icon(
            sel ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 20,
            color: sel ? McColors.primarySoft : McColors.outline,
          ),
        );
      },
    );
  }

  Widget _avatar(String name) {
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: McColors.primarySoft.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: McColors.primarySoft.withValues(alpha: 0.3)),
      ),
      alignment: Alignment.center,
      child: Text(initial,
          style: McText.display(
              size: 15, weight: FontWeight.w700, color: McColors.primarySoft)),
    );
  }
}

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/auth.dart';
import '../services/chat_api.dart';

/// 群信息页: 群名 (群主可改) + 成员列表 (群主可移除成员).
/// 仅群聊进入; 非群主只读. 全部接口静默容错.
class GroupInfoPage extends StatefulWidget {
  const GroupInfoPage({super.key, required this.conversation});

  final Conversation conversation;

  @override
  State<GroupInfoPage> createState() => _GroupInfoPageState();
}

class _GroupInfoPageState extends State<GroupInfoPage> {
  List<GroupMember> _members = [];
  bool _loading = true;
  bool _failed = false;
  late String _name;

  int get _myId => AuthStore.instance.userId ?? -1;
  bool get _isOwner => _members.any((m) => m.isOwner && m.id == _myId);

  @override
  void initState() {
    super.initState();
    _name = widget.conversation.displayName;
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ChatApi.members(widget.conversation.id);
      if (!mounted) return;
      setState(() {
        _members = list;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  // ---------- 群主: 改名 ----------

  Future<void> _editName() async {
    final controller = TextEditingController(text: _name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: McColors.surfaceContainerLow,
        title: Text(tr('grp_edit_name'),
            style: McText.sans(size: 15, weight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          style: McText.sans(size: 14),
          decoration: InputDecoration(
            hintText: tr('grp_name_input_hint'),
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
    if (name == null || name.isEmpty || name == _name) return;
    try {
      await ChatApi.renameConversation(widget.conversation.id, name);
      if (!mounted) return;
      setState(() => _name = name);
      _toast(tr('grp_name_updated'));
    } catch (_) {
      _toast(tr('grp_update_failed'));
    }
  }

  // ---------- 群主: 移除成员 ----------

  Future<void> _confirmRemove(GroupMember m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: McColors.surfaceContainerLow,
        title: Text(tr('grp_remove_member'),
            style: McText.sans(size: 15, weight: FontWeight.w700)),
        content: Text(tr('grp_remove_member_hint').replaceAll('{name}', m.username),
            style: McText.sans(size: 13, color: McColors.onSurfaceVariant)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel'),
                style: McText.sans(color: McColors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('grp_remove'), style: McText.sans(color: McColors.bear)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ChatApi.removeMember(widget.conversation.id, m.id);
      if (!mounted) return;
      setState(() => _members.removeWhere((x) => x.id == m.id));
      _toast(tr('grp_removed'));
    } catch (_) {
      _toast(tr('grp_remove_failed'));
    }
  }

  // ---------- 全员: 拉人进群 ----------

  Future<void> _addMember() async {
    List<ChatUser> candidates;
    try {
      final friends = await ChatApi.friends();
      final ids = _members.map((m) => m.id).toSet();
      candidates = [for (final f in friends) if (!ids.contains(f.id)) f];
    } catch (_) {
      _toast(tr('grp_load_friends_failed'));
      return;
    }
    if (!mounted) return;
    if (candidates.isEmpty) {
      _toast(tr('grp_no_addable_friends'));
      return;
    }
    final picked = await showDialog<ChatUser>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: McColors.surfaceContainerLow,
        title: Text(tr('grp_pick_friend'),
            style: McText.sans(size: 15, weight: FontWeight.w700)),
        children: [
          for (final f in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, f),
              child: Row(
                children: [
                  McAvatar(
                      name: f.displayName, url: f.avatarUrl, size: 32, radius: 8),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(f.displayName,
                        style: McText.sans(size: 14, color: Colors.white)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null) return;
    try {
      await ChatApi.addGroupMember(widget.conversation.id, picked.id);
      if (!mounted) return;
      _toast(tr('grp_added').replaceAll('{name}', picked.username));
      _load();
    } catch (_) {
      _toast(tr('grp_add_failed'));
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

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: McColors.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: McColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: McColors.onSurface),
        title: Text(tr('grp_info_title'),
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
          : _failed
              ? _failState()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                  children: [
                    _nameCard(),
                    const SizedBox(height: 16),
                    Text(tr('grp_members').replaceAll('{n}', '${_members.length}'),
                        style: McText.sans(
                            size: 12,
                            weight: FontWeight.w600,
                            color: McColors.onSurfaceVariant,
                            letterSpacing: 0.4)),
                    const SizedBox(height: 8),
                    _memberGrid(),
                  ],
                ),
    );
  }

  Widget _nameCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: McColors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.groups_outlined,
              size: 22, color: McColors.primarySoft),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('grp_name_label'),
                    style: McText.sans(
                        size: 12, color: McColors.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(_name,
                    style: McText.sans(
                        size: 15,
                        weight: FontWeight.w600,
                        color: Colors.white)),
              ],
            ),
          ),
          if (_isOwner)
            GestureDetector(
              onTap: _editName,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: McColors.primaryContainer.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color:
                          McColors.primaryContainer.withValues(alpha: 0.4)),
                ),
                child: Text(tr('grp_edit'),
                    style: McText.sans(
                        size: 12,
                        weight: FontWeight.w600,
                        color: McColors.primarySoft)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _memberGrid() {
    return GridView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero, // 防 primary 滚动视图自动吃状态栏 inset
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 14,
        crossAxisSpacing: 6,
        childAspectRatio: 0.66,
      ),
      itemCount: _members.length + 1, // 末尾 "+" 拉人
      itemBuilder: (context, i) =>
          i == _members.length ? _addCell() : _memberCell(_members[i]),
    );
  }

  /// 拉人格子 (任一成员可用).
  Widget _addCell() {
    return GestureDetector(
      onTap: _addMember,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: McColors.outlineVariant.withValues(alpha: 0.8)),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.add,
                size: 24, color: McColors.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            tr('frd_tab_add'),
            maxLines: 1,
            textAlign: TextAlign.center,
            style: McText.sans(size: 12, color: McColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _memberCell(GroupMember m) {
    final canRemove = _isOwner && !m.isOwner;
    return GestureDetector(
      // 群主可长按非群主成员触发移除.
      onLongPress: canRemove ? () => _confirmRemove(m) : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: McColors.primarySoft.withValues(alpha: 0.3)),
                ),
                child: McAvatar(
                    name: m.displayName, url: m.avatarUrl, size: 46),
              ),
              if (canRemove)
                Positioned(
                  top: -4,
                  right: -4,
                  child: GestureDetector(
                    onTap: () => _confirmRemove(m),
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: McColors.bear,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close,
                          size: 11, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            m.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: McText.sans(size: 12, color: McColors.onSurfaceVariant),
          ),
          if (m.isOwner)
            Text(tr('grp_owner'),
                style: McText.sans(
                    size: 12,
                    weight: FontWeight.w600,
                    color: McColors.goldBright)),
        ],
      ),
    );
  }

  Widget _failState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline,
              size: 40, color: McColors.outline),
          const SizedBox(height: 12),
          Text(tr('news_load_failed'),
              style:
                  McText.sans(size: 13, color: McColors.onSurfaceVariant)),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              setState(() {
                _loading = true;
                _failed = false;
              });
              _load();
            },
            child: Text(tr('grp_reload'),
                style: McText.sans(size: 12, color: McColors.primarySoft)),
          ),
        ],
      ),
    );
  }
}

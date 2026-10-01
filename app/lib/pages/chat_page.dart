import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/chat_api.dart';
import '../services/chat_ws.dart';
import 'chat_conversation_page.dart';
import 'friends_page.dart';
import 'group_create_page.dart';

/// 聊天 (社区 Tab): 会话列表 + 搜索 + 全部/私聊/群聊 过滤,
/// 右上角 新朋友 / 发起群聊, 长按删除/退群, WS 实时更新.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _search = TextEditingController();

  List<Conversation> _conversations = [];
  bool _loading = true;
  bool _failed = false;
  int _tab = 0; // 0 全部 1 私聊 2 群聊
  int _friendReqCount = 0;

  StreamSubscription<Map<String, dynamic>>? _wsSub;

  @override
  void initState() {
    super.initState();
    ChatWs.instance.connect();
    _load();
    _wsSub = ChatWs.instance.events.listen(_onWsEvent);
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await ChatApi.conversations();
      if (!mounted) return;
      setState(() {
        _conversations = list;
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

  void _syncUnreadBadge() {
    var sum = 0;
    for (final c in _conversations) {
      sum += c.unreadCount;
    }
    ChatApi.unreadCount.value = sum;
  }

  void _onWsEvent(Map<String, dynamic> e) {
    if (!mounted) return;
    final type = e['type'];
    if (type == 'friend_request') {
      setState(() => _friendReqCount++);
      return;
    }
    if (type != 'message') return;
    final convId = e['conversation_id'];
    final idx = _conversations.indexWhere((c) => c.id == convId);
    if (idx < 0) {
      // 新会话 -> 整体刷新.
      _load();
      return;
    }
    final msg = ChatMessage.fromJson(e['message']);
    setState(() {
      final c = _conversations[idx];
      final updated = c.copyWith(
        lastMessage: LastMessage(
          content: msg.content,
          senderName: msg.senderName,
          createdAt: msg.createdAt,
        ),
        unreadCount: c.unreadCount + 1,
      );
      _conversations
        ..removeAt(idx)
        ..insert(0, updated); // 顶到最前
      _syncUnreadBadge();
    });
  }

  // ---------- 过滤 ----------

  List<Conversation> get _filtered {
    var list = _conversations;
    if (_tab == 1) {
      list = list.where((c) => !c.isGroup).toList();
    } else if (_tab == 2) {
      list = list.where((c) => c.isGroup).toList();
    }
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where((c) => c.displayName.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  // ---------- 导航 ----------

  Future<void> _openConversation(Conversation c) async {
    // 进入房间即清零本地未读.
    final idx = _conversations.indexWhere((x) => x.id == c.id);
    if (idx >= 0 && _conversations[idx].unreadCount > 0) {
      setState(() {
        _conversations[idx] = _conversations[idx].copyWith(unreadCount: 0);
        _syncUnreadBadge();
      });
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
          builder: (_) => ChatConversationPage(conversation: c)),
    );
    // 返回后重新同步 (已读状态/最后消息可能已变).
    _load();
  }

  Future<void> _openFriends() async {
    setState(() => _friendReqCount = 0);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const FriendsPage()),
    );
    _load();
  }

  Future<void> _openGroupCreate() async {
    final created = await Navigator.of(context).push<Conversation>(
      MaterialPageRoute<Conversation>(builder: (_) => const GroupCreatePage()),
    );
    if (created != null && mounted) {
      _load();
      _openConversation(created);
    }
  }

  // ---------- 删除 / 退群 ----------

  Future<void> _confirmDelete(Conversation c) async {
    final isGroup = c.isGroup;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: McColors.surfaceContainerLow,
        title: Text(isGroup ? '退出群聊' : '删除会话',
            style: McText.sans(size: 15, weight: FontWeight.w700)),
        content: Text(
          isGroup ? '退出后将不再接收该群消息' : '删除后聊天记录将从列表隐藏',
          style: McText.sans(size: 13, color: McColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消',
                style: McText.sans(color: McColors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                Text('确定', style: McText.sans(color: McColors.bear)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ChatApi.deleteConversation(c.id);
      if (!mounted) return;
      setState(() {
        _conversations.removeWhere((x) => x.id == c.id);
        _syncUnreadBadge();
      });
    } catch (_) {
      _toast(isGroup ? '退群失败' : '删除失败');
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
    return Container(
      color: McColors.surfaceContainerLowest,
      child: Column(
        children: [
          _buildHeader(),
          _buildSearch(),
          _buildTabs(),
          const SizedBox(height: 6),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
      child: Row(
        children: [
          Text('聊天', style: McText.display(size: 18, weight: FontWeight.w700)),
          const Spacer(),
          // 新朋友 (好友请求角标).
          _headerAction(
            icon: Icons.person_add_alt,
            badge: _friendReqCount,
            onTap: _openFriends,
          ),
          _headerAction(
            icon: Icons.group_add_outlined,
            badge: 0,
            onTap: _openGroupCreate,
          ),
        ],
      ),
    );
  }

  Widget _headerAction(
      {required IconData icon, required int badge, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon, size: 22, color: McColors.onSurface),
            if (badge > 0)
              Positioned(
                top: -4,
                right: -6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: McColors.bear,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  constraints: const BoxConstraints(minWidth: 14),
                  child: Text(
                    badge > 99 ? '99+' : '$badge',
                    textAlign: TextAlign.center,
                    style: McText.mono(
                        size: 12,
                        weight: FontWeight.w700,
                        color: Colors.white,
                        height: 1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: McColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: McColors.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          style: McText.sans(size: 13),
          decoration: InputDecoration(
            icon: const Icon(Icons.search,
                size: 18, color: McColors.onSurfaceVariant),
            hintText: '搜索会话',
            hintStyle:
                McText.sans(size: 13, color: McColors.onSurfaceVariant),
            border: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      ),
    );
  }

  Widget _buildTabs() {
    const tabs = ['全部', '私聊', '群聊'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _tabChip(i, tabs[i]),
          ],
        ],
      ),
    );
  }

  Widget _tabChip(int i, String label) {
    final active = _tab == i;
    return GestureDetector(
      onTap: () => setState(() => _tab = i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? McColors.primaryContainer.withValues(alpha: 0.18)
              : McColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? McColors.primaryContainer.withValues(alpha: 0.5)
                : McColors.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          label,
          style: McText.sans(
            size: 12,
            weight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? McColors.primary : McColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
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
    if (_failed) {
      return _empty('加载失败, 下拉重试');
    }
    final list = _filtered;
    return RefreshIndicator(
      onRefresh: _load,
      color: McColors.primarySoft,
      backgroundColor: McColors.surfaceContainerHigh,
      child: list.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 120),
                _empty(_search.text.isEmpty ? '暂无会话, 去添加好友聊聊吧' : '没有匹配的会话'),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              itemCount: list.length,
              separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: McColors.outlineVariant.withValues(alpha: 0.3)),
              itemBuilder: (context, i) => _tile(list[i]),
            ),
    );
  }

  Widget _tile(Conversation c) {
    final last = c.lastMessage;
    final preview = last == null
        ? '暂无消息'
        : (c.isGroup && last.senderName.isNotEmpty
            ? '${last.senderName}: ${last.content}'
            : last.content);
    return InkWell(
      onTap: () => _openConversation(c),
      onLongPress: () => _confirmDelete(c),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            _avatar(c.displayName),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          c.displayName,
                          style: McText.sans(
                              size: 14,
                              weight: FontWeight.w600,
                              color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (c.isGroup) ...[
                        const SizedBox(width: 6),
                        Text(
                          '(${c.memberCount})',
                          style: McText.mono(
                              size: 12, color: McColors.onSurfaceVariant),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        chatTimeLabel(last?.createdAt),
                        style: McText.mono(
                          size: 12,
                          color: c.unreadCount > 0
                              ? McColors.bull
                              : McColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: McText.sans(
                              size: 12, color: McColors.onSurfaceVariant),
                        ),
                      ),
                      if (c.unreadCount > 0) ...[
                        const SizedBox(width: 10),
                        _unreadBadge(c.unreadCount),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _unreadBadge(int count) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: McColors.bear,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(color: McColors.bear.withValues(alpha: 0.5), blurRadius: 6),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: McText.mono(
            size: 12, weight: FontWeight.w700, color: Colors.white, height: 1),
      ),
    );
  }

  Widget _avatar(String name) {
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: McColors.primarySoft.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: McColors.primarySoft.withValues(alpha: 0.3)),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: McText.display(
            size: 17, weight: FontWeight.w700, color: McColors.primarySoft),
      ),
    );
  }

  Widget _empty(String text) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.forum_outlined, size: 40, color: McColors.outline),
        const SizedBox(height: 12),
        Text(text,
            style: McText.sans(size: 13, color: McColors.onSurfaceVariant)),
      ],
    );
  }
}

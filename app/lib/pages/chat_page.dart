import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/chat_api.dart';
import '../services/auth.dart';
import '../services/chat_db.dart';
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
  // 好友请求角标用全局 ChatApi.friendRequestCount (底部导航也读它).
  Set<int> _onlineIds = const {};

  StreamSubscription<Map<String, dynamic>>? _wsSub;
  bool _autoRetried = false;

  @override
  void initState() {
    super.initState();
    ChatWs.instance.connect();
    _load();
    _loadOnline();
    _wsSub = ChatWs.instance.events.listen(_onWsEvent);
    // 同步好友请求角标 (静默失败)
    _syncFriendRequests();
  }

  Future<void> _syncFriendRequests() async {
    try {
      await ChatApi.friendRequests();
    } catch (_) {/* 静默 */}
  }

  /// 拉在线好友集合 (静默, 失败不影响列表).
  Future<void> _loadOnline() async {
    final ids = await ChatApi.friendsOnline();
    if (!mounted) return;
    setState(() => _onlineIds = ids);
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _loadOnline(); // 下拉刷新顺带更新在线状态
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
      // 静默自动重试一次 (如赶上后端重启), 不打扰用户
      if (!_autoRetried) {
        _autoRetried = true;
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted && _failed) _load();
        });
      }
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
      ChatApi.friendRequestCount.value++;
      _loadOnline();
      return;
    }
    if (type == 'read') {
      // 对方已读 -> 私聊自己消息的回执实时变双勾.
      final idx =
          _conversations.indexWhere((c) => c.id == e['conversation_id']);
      if (idx < 0) return;
      final c = _conversations[idx];
      final last = c.lastMessage;
      if (c.isGroup || last == null || !last.isMine || last.read == true) {
        return;
      }
      final mid = e['message_id'];
      if (mid is int && mid < last.id) return; // 读的是更早的消息
      setState(() {
        _conversations[idx] =
            c.copyWith(lastMessage: last.copyWith(read: true));
      });
      return;
    }
    if (type == 'group_updated') {
      // 群改名 -> 更新列表中的群名.
      final idx =
          _conversations.indexWhere((c) => c.id == e['conversation_id']);
      if (idx < 0) return;
      final name = (e['name'] ?? '').toString();
      if (name.isEmpty) return;
      setState(() => _conversations[idx] = _conversations[idx].copyWith(name: name));
      return;
    }
    if (type == 'member_removed') {
      final convId = e['conversation_id'];
      final userId = e['user_id'];
      final idx = _conversations.indexWhere((c) => c.id == convId);
      if (idx < 0) return;
      // 我被移出 -> 移除会话 + 清本地缓存 + 提示.
      if (userId == AuthStore.instance.userId) {
        setState(() {
          _conversations.removeAt(idx);
          _syncUnreadBadge();
        });
        ChatDb.clearConversation(convId is int ? convId : 0);
        _toast('你已被移出群聊');
        return;
      }
      // 他人被移出 -> 成员数 -1.
      final c = _conversations[idx];
      setState(() {
        _conversations[idx] =
            c.copyWith(memberCount: (c.memberCount - 1).clamp(0, 1 << 31));
      });
      return;
    }
    if (type == 'member_added') {
      final convId = e['conversation_id'];
      final idx = _conversations.indexWhere((c) => c.id == convId);
      if (idx < 0) {
        // 我被拉进新群 -> 整体刷新让群出现.
        _load();
        return;
      }
      // 他人进群 -> 成员数 +1 (优先用服务端计数).
      final c = _conversations[idx];
      final cnt = (e['member_count'] as num?)?.toInt() ?? c.memberCount + 1;
      setState(() => _conversations[idx] = c.copyWith(memberCount: cnt));
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
    final mine = msg.senderId == AuthStore.instance.userId;
    setState(() {
      final c = _conversations[idx];
      final updated = c.copyWith(
        lastMessage: LastMessage(
          id: msg.id,
          content: msg.content,
          senderName: msg.senderName,
          msgType: msg.msgType,
          createdAt: msg.createdAt,
          isMine: mine,
          read: mine ? false : null, // 自己发的等对方已读事件翻双勾
        ),
        // 自己发的 (多端同步) 不涨未读.
        unreadCount: mine ? c.unreadCount : c.unreadCount + 1,
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
    ChatApi.friendRequestCount.value = 0;
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
      // 删除/退群同时清空本地消息缓存.
      ChatDb.clearConversation(c.id);
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
          _buildSectionHeader(),
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
          // 新朋友 (好友请求角标, 全局 notifier 驱动).
          ValueListenableBuilder<int>(
            valueListenable: ChatApi.friendRequestCount,
            builder: (context, count, _) => _headerAction(
              icon: Icons.person_add_alt,
              badge: count,
              onTap: _openFriends,
            ),
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

  /// 列表区小节头: 左侧标签 + 右侧在线好友计数.
  Widget _buildSectionHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          Text('会话',
              style: McText.sans(
                  size: 12,
                  weight: FontWeight.w600,
                  color: McColors.onSurfaceVariant,
                  letterSpacing: 0.4)),
          const Spacer(),
          if (_onlineIds.isNotEmpty)
            Text('${_onlineIds.length} 位好友在线',
                style: McText.sans(size: 12, color: McColors.outline)),
        ],
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
    // 失败且本地无会话: 按空态展示 (不吓用户), 点击/下拉重试; 有缓存则保留列表
    if (_failed && _conversations.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        color: McColors.primarySoft,
        backgroundColor: McColors.surfaceContainerHigh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            _empty('暂无会话, 去添加好友聊聊吧', retry: true),
          ],
        ),
      );
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
                  indent: 72,
                  color: McColors.outlineVariant.withValues(alpha: 0.3)),
              itemBuilder: (context, i) => _tile(list[i]),
            ),
    );
  }

  Widget _tile(Conversation c) {
    final last = c.lastMessage;
    final online =
        !c.isGroup && c.otherUser != null && _onlineIds.contains(c.otherUser!.id);
    return InkWell(
      onTap: () => _openConversation(c),
      onLongPress: () => _confirmDelete(c),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            _avatar(c, online: online),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 顶行: 名称 + 群组胶囊.
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          c.displayName,
                          style: McText.sans(
                              size: 15,
                              weight: FontWeight.w600,
                              color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (c.isGroup) ...[
                        const SizedBox(width: 6),
                        _groupPill(c.memberCount),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  // 底行: 预览整宽.
                  _preview(c),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 右列: 上时间 / 下 未读角标或已读回执 — 钉死右缘.
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  chatTimeLabel(last?.createdAt),
                  style: McText.mono(size: 12, color: McColors.outline),
                ),
                const SizedBox(height: 6),
                if (c.unreadCount > 0)
                  _unreadBadge(c.unreadCount)
                else if (!c.isGroup && last != null && last.isMine)
                  _receipt(last.read)
                else
                  const SizedBox(height: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 群组胶囊: '群组 1,840'.
  Widget _groupPill(int memberCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: McColors.primarySoft.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border:
            Border.all(color: McColors.primarySoft.withValues(alpha: 0.28)),
      ),
      child: Text(
        '群组 ${_fmtCount(memberCount)}',
        style: McText.sans(
            size: 12, weight: FontWeight.w500, color: McColors.primarySoft),
      ),
    );
  }

  /// 最后消息预览: 群带发送者前缀 (青), 自己消息带 '我: '.
  Widget _preview(Conversation c) {
    final last = c.lastMessage;
    if (last == null) {
      return Text('暂无消息',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: McText.sans(size: 12, color: McColors.onSurfaceVariant));
    }
    final base = McText.sans(size: 12, color: McColors.onSurfaceVariant);
    final prefix = last.isMine
        ? '我: '
        : (c.isGroup && last.senderName.isNotEmpty
            ? '${last.senderName}: '
            : '');
    if (prefix.isEmpty) {
      return Text(last.previewText,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: base);
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
              text: prefix,
              style: McText.sans(size: 12, color: McColors.secondary)),
          TextSpan(text: last.previewText, style: base),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// 私聊已读回执: 未读单勾 (暗), 已读双勾 (青绿).
  Widget _receipt(bool? read) {
    final seen = read == true;
    return Icon(
      seen ? Icons.done_all : Icons.check,
      size: 14,
      color: seen ? McColors.secondary : McColors.outline,
    );
  }

  static String _fmtCount(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final fromEnd = s.length - i;
      buf.write(s[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(',');
    }
    return buf.toString();
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

  /// 圆角方形头像 (48px, r12): 名字哈希选配色, 私聊在线时右下绿点.
  Widget _avatar(Conversation c, {required bool online}) {
    final name = c.displayName;
    // 小调色板: 主蓝 / 青 / 绿 / 金, 按名字哈希稳定取色.
    const palette = [
      McColors.primarySoft,
      McColors.secondary,
      McColors.tertiary,
      McColors.goldBright,
    ];
    var hash = 0;
    for (final ch in name.codeUnits) {
      hash = (hash * 31 + ch) & 0x7fffffff;
    }
    final color = palette[hash % palette.length];
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: McAvatar(
              name: name,
              url: c.isGroup ? null : c.otherUser?.avatarUrl,
              size: 48,
              radius: 12,
              bg: color.withValues(alpha: 0.16),
              fg: color,
            ),
          ),
          if (online)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: McColors.bull,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: McColors.surfaceContainerLowest, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _empty(String text, {bool retry = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.forum_outlined, size: 40, color: McColors.outline),
        const SizedBox(height: 12),
        Text(text,
            style: McText.sans(size: 13, color: McColors.onSurfaceVariant)),
        if (retry) ...[
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _load,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: McColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: McColors.outlineVariant),
              ),
              child: Text('重新加载',
                  style: McText.sans(size: 12, color: McColors.primarySoft)),
            ),
          ),
        ],
      ],
    );
  }
}

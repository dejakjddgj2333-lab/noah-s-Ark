import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/chat_api.dart';
import 'chat_conversation_page.dart';

/// 好友页: 好友 / 请求 / 添加 三个 Tab.
/// 好友列表可发起私聊; 请求页处理接受/拒绝; 添加页搜索用户 (relation 感知按钮).
class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  int _tab = 0;

  List<ChatUser> _friends = [];
  FriendRequests _requests =
      const FriendRequests(incoming: [], outgoing: []);
  bool _loadingFriends = true;
  bool _loadingRequests = true;

  // 添加 Tab.
  final _search = TextEditingController();
  Timer? _debounce;
  List<ChatUser> _results = [];
  bool _searching = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _loadFriends();
    _loadRequests();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    try {
      final list = await ChatApi.friends();
      if (!mounted) return;
      setState(() {
        _friends = list;
        _loadingFriends = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingFriends = false);
    }
  }

  Future<void> _loadRequests() async {
    try {
      final r = await ChatApi.friendRequests();
      if (!mounted) return;
      setState(() {
        _requests = r;
        _loadingRequests = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRequests = false);
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

  // ---------- 好友操作 ----------

  Future<void> _openDirect(ChatUser u) async {
    try {
      final conv = await ChatApi.openDirect(u.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
            builder: (_) => ChatConversationPage(conversation: conv)),
      );
    } catch (_) {
      _toast('打开会话失败');
    }
  }

  Future<void> _confirmDeleteFriend(ChatUser u) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: McColors.surfaceContainerLow,
        title: Text('删除好友',
            style: McText.sans(size: 15, weight: FontWeight.w700)),
        content: Text('确定删除好友 ${u.username} 吗?',
            style: McText.sans(size: 13, color: McColors.onSurfaceVariant)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消',
                style: McText.sans(color: McColors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('删除', style: McText.sans(color: McColors.bear)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ChatApi.deleteFriend(u.id);
      if (!mounted) return;
      setState(() => _friends.removeWhere((x) => x.id == u.id));
      _toast('已删除');
    } catch (_) {
      _toast('删除失败');
    }
  }

  // ---------- 请求操作 ----------

  Future<void> _accept(FriendRequest r) async {
    try {
      await ChatApi.acceptFriend(r.id);
      if (!mounted) return;
      _toast('已接受');
      _loadRequests();
      _loadFriends();
    } catch (_) {
      _toast('操作失败');
    }
  }

  Future<void> _reject(FriendRequest r) async {
    try {
      await ChatApi.rejectFriend(r.id);
      if (!mounted) return;
      _toast('已拒绝');
      _loadRequests();
    } catch (_) {
      _toast('操作失败');
    }
  }

  // ---------- 添加 / 搜索 ----------

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() {
        _results = [];
        _searched = false;
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _doSearch(q));
  }

  Future<void> _doSearch(String q) async {
    setState(() => _searching = true);
    try {
      final list = await ChatApi.searchUsers(q.trim());
      if (!mounted) return;
      setState(() {
        _results = list;
        _searching = false;
        _searched = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searched = true;
      });
    }
  }

  Future<void> _sendRequest(ChatUser u) async {
    try {
      await ChatApi.sendFriendRequest(u.id);
      if (!mounted) return;
      _toast('请求已发送');
      // 就地更新按钮状态.
      setState(() {
        final idx = _results.indexWhere((x) => x.id == u.id);
        if (idx >= 0) {
          _results[idx] = ChatUser(
              id: u.id, username: u.username, relation: 'outgoing');
        }
      });
    } catch (_) {
      _toast('发送失败');
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: McColors.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: McColors.surface,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: McColors.onSurface),
        title: Text('新朋友',
            style: McText.sans(size: 16, weight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          _buildTabs(),
          const SizedBox(height: 6),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    final labels = ['好友', '请求', '添加'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _tabChip(i, labels[i],
                badge: i == 1 ? _requests.pendingCount : 0),
          ],
        ],
      ),
    );
  }

  Widget _tabChip(int i, String label, {int badge = 0}) {
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: McText.sans(
                size: 12,
                weight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? McColors.primary : McColors.onSurfaceVariant,
              ),
            ),
            if (badge > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: McColors.bear,
                  borderRadius: BorderRadius.circular(999),
                ),
                constraints: const BoxConstraints(minWidth: 14),
                child: Text(
                  '$badge',
                  textAlign: TextAlign.center,
                  style: McText.mono(
                      size: 12,
                      weight: FontWeight.w700,
                      color: Colors.white,
                      height: 1),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_tab) {
      case 0:
        return _buildFriends();
      case 1:
        return _buildRequests();
      default:
        return _buildAdd();
    }
  }

  Widget _buildFriends() {
    if (_loadingFriends) return _spinner();
    if (_friends.isEmpty) return _empty('还没有好友, 去「添加」找人吧');
    return RefreshIndicator(
      onRefresh: _loadFriends,
      color: McColors.primarySoft,
      backgroundColor: McColors.surfaceContainerHigh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
        itemCount: _friends.length,
        separatorBuilder: (_, _) => Divider(
            height: 1, color: McColors.outlineVariant.withValues(alpha: 0.3)),
        itemBuilder: (context, i) {
          final u = _friends[i];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _avatar(u.username),
            title: Text(u.username,
                style:
                    McText.sans(size: 14, weight: FontWeight.w600)),
            onTap: () => _openDirect(u),
            onLongPress: () => _confirmDeleteFriend(u),
            trailing: const Icon(Icons.chat_bubble_outline,
                size: 18, color: McColors.onSurfaceVariant),
          );
        },
      ),
    );
  }

  Widget _buildRequests() {
    if (_loadingRequests) return _spinner();
    final incoming = _requests.incoming;
    final outgoing = _requests.outgoing;
    if (incoming.isEmpty && outgoing.isEmpty) {
      return _empty('暂无好友请求');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      children: [
        if (incoming.isNotEmpty) ...[
          _sectionLabel('收到的请求'),
          for (final r in incoming) _incomingTile(r),
          const SizedBox(height: 12),
        ],
        if (outgoing.isNotEmpty) ...[
          _sectionLabel('我发出的'),
          for (final r in outgoing) _outgoingTile(r),
        ],
      ],
    );
  }

  Widget _incomingTile(FriendRequest r) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _avatar(r.username),
          const SizedBox(width: 12),
          Expanded(
            child: Text(r.username,
                style: McText.sans(size: 14, weight: FontWeight.w600)),
          ),
          _smallButton('接受', McColors.bull, () => _accept(r)),
          const SizedBox(width: 8),
          _smallButton('拒绝', McColors.bear, () => _reject(r), outlined: true),
        ],
      ),
    );
  }

  Widget _outgoingTile(FriendRequest r) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _avatar(r.username),
          const SizedBox(width: 12),
          Expanded(
            child: Text(r.username,
                style: McText.sans(size: 14, weight: FontWeight.w600)),
          ),
          Text('等待验证',
              style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildAdd() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: McColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: McColors.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              style: McText.sans(size: 13),
              decoration: InputDecoration(
                icon: const Icon(Icons.search,
                    size: 18, color: McColors.onSurfaceVariant),
                hintText: '搜索用户名',
                hintStyle:
                    McText.sans(size: 13, color: McColors.onSurfaceVariant),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ),
        Expanded(child: _buildResults()),
      ],
    );
  }

  Widget _buildResults() {
    if (_searching) return _spinner();
    if (!_searched) return _empty('输入用户名搜索');
    if (_results.isEmpty) return _empty('未找到该用户');
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      itemCount: _results.length,
      separatorBuilder: (_, _) => Divider(
          height: 1, color: McColors.outlineVariant.withValues(alpha: 0.3)),
      itemBuilder: (context, i) {
        final u = _results[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              _avatar(u.username),
              const SizedBox(width: 12),
              Expanded(
                child: Text(u.username,
                    style: McText.sans(size: 14, weight: FontWeight.w600)),
              ),
              _relationButton(u),
            ],
          ),
        );
      },
    );
  }

  Widget _relationButton(ChatUser u) {
    switch (u.relation) {
      case 'self':
        return Text('自己',
            style: McText.sans(size: 12, color: McColors.onSurfaceVariant));
      case 'friend':
        return const McPill('好友', color: McColors.bull, bold: false);
      case 'outgoing':
        return const McPill('已发送', color: McColors.onSurfaceVariant,
            bold: false);
      case 'incoming':
        return _smallButton('接受', McColors.bull, () => _accept(
            FriendRequest(id: u.id, username: u.username)));
      default: // none
        return _smallButton('加好友', McColors.primarySoft, () => _sendRequest(u));
    }
  }

  Widget _smallButton(String label, Color color, VoidCallback onTap,
      {bool outlined = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(
          label,
          style: McText.sans(size: 12, weight: FontWeight.w600, color: color),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: McText.mono(size: 12, color: McColors.onSurfaceVariant)),
    );
  }

  Widget _avatar(String name) {
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();
    return Container(
      width: 42,
      height: 42,
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

  Widget _spinner() => const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: McColors.primarySoft),
        ),
      );

  Widget _empty(String text) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.people_outline, size: 40, color: McColors.outline),
          const SizedBox(height: 12),
          Text(text,
              style: McText.sans(size: 13, color: McColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

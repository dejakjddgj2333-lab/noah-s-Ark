import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme.dart';
import '../widgets/kit.dart';

/// 聊天好友/群组对话框 (对齐 web-terminal Chat.vue):
/// 好友管理 (列表/请求/搜索加好友) / 建群 / 拉人入群 / 通用确认框.

String chatUserName(Map<String, dynamic> u) {
  final n = u['nickname'] ?? u['username'];
  if (n != null && '$n'.isNotEmpty) return '$n';
  return '用户${u['id'] ?? ''}';
}

Widget _avatar(String name, {double size = 30, bool online = false}) {
  final initial = name.isEmpty ? 'U' : name.substring(0, 1).toUpperCase();
  return Stack(children: [
    Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Mc.cardHigh,
        border: Border.all(color: Mc.hairline),
      ),
      alignment: Alignment.center,
      child: Text(initial,
          style: Mc.mono(size * 0.4, w: FontWeight.w700, color: Mc.ink)),
    ),
    if (online)
      Positioned(
        right: 0,
        bottom: 0,
        child: Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Mc.bull,
            border: Border.all(color: Mc.surface, width: 1.5),
          ),
        ),
      ),
  ]);
}

/// 小文本按钮 (列表行动作用).
Widget _miniBtn(String label,
    {Color color = Mc.cobaltSoft, VoidCallback? onTap}) {
  return InkWell(
    borderRadius: BorderRadius.circular(6),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label, style: Mc.body(11, w: FontWeight.w600, color: color)),
    ),
  );
}

/// 通用深色确认框.
Future<bool?> confirmMcDialog(BuildContext context, String text) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Mc.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Mc.hairline)),
      content: Text(text, style: Mc.body(13)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('取消', style: Mc.body(12, color: Mc.muted)),
        ),
        McButton('确定', height: 32, onPressed: () => Navigator.pop(ctx, true)),
      ],
    ),
  );
}

/// 对话框外壳: 标题栏 + 关闭 + 内容区.
Widget _dialogShell(BuildContext context,
    {required String title,
    required Widget child,
    double width = 460,
    double height = 520}) {
  return Dialog(
    backgroundColor: Mc.surface,
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Mc.hairline)),
    child: SizedBox(
      width: width,
      height: height,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
          child: Row(children: [
            Expanded(child: Text(title, style: Mc.display(15))),
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: Mc.muted),
              onPressed: () => Navigator.pop(context),
            ),
          ]),
        ),
        const Divider(height: 1, color: Mc.hairline),
        Expanded(child: child),
      ]),
    ),
  );
}

/// 分段 tab (好友/请求/搜索).
Widget _segTabs(List<(String, String)> items, String cur, int badge,
    void Function(String) onTap) {
  return Container(
    margin: const EdgeInsets.fromLTRB(14, 10, 14, 4),
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: Mc.card,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Mc.hairline),
    ),
    child: Row(children: [
      for (final (key, label) in items)
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => onTap(key),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: cur == key ? Mc.cardHigh : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(label,
                    style: Mc.body(12,
                        w: cur == key ? FontWeight.w600 : FontWeight.w400,
                        color: cur == key ? Mc.cobaltSoft : Mc.muted)),
                if (key == 'req' && badge > 0) ...[
                  const SizedBox(width: 5),
                  McBadge('$badge', color: Mc.bear),
                ],
              ]),
            ),
          ),
        ),
    ]),
  );
}

// ==================== 好友管理对话框 ====================

/// onChatWith: 点"发消息"后由上层建单聊会话并跳转.
Future<void> showFriendDialog(BuildContext context,
    {String initialTab = 'list',
    required Future<void> Function(Map<String, dynamic> user) onChatWith}) {
  return showDialog(
      context: context,
      builder: (_) =>
          _FriendDialog(initialTab: initialTab, onChatWith: onChatWith));
}

class _FriendDialog extends StatefulWidget {
  const _FriendDialog({required this.initialTab, required this.onChatWith});
  final String initialTab;
  final Future<void> Function(Map<String, dynamic> user) onChatWith;

  @override
  State<_FriendDialog> createState() => _FriendDialogState();
}

class _FriendDialogState extends State<_FriendDialog> {
  late String _tab = widget.initialTab;
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _reqs = [];
  Set<int> _onlineIds = {};
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _searchRes = [];
  bool _searching = false;
  int _busyId = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadFriends();
    _loadReqs();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  static List<Map<String, dynamic>> _asList(dynamic res) {
    final raw = res is Map ? res['items'] : res;
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _loadFriends() async {
    try {
      final list = _asList(await ApiClient.I.friends());
      if (mounted) setState(() => _friends = list);
    } catch (_) {}
    try {
      final r = await ApiClient.I.friendsOnline();
      final ids = r is Map ? r['online_ids'] : null;
      if (mounted && ids is List) {
        setState(() =>
            _onlineIds = ids.whereType<num>().map((e) => e.toInt()).toSet());
      }
    } catch (_) {/* 在线状态失败静默 */}
  }

  Future<void> _loadReqs() async {
    try {
      final list = _asList(await ApiClient.I.friendRequests());
      if (mounted) setState(() => _reqs = list);
    } catch (_) {}
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() => _searchRes = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), _doSearch);
  }

  Future<void> _doSearch() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty || _searching) return;
    setState(() => _searching = true);
    try {
      final list = _asList(await ApiClient.I.searchUsers(q));
      if (mounted) setState(() => _searchRes = list);
    } catch (_) {
      if (mounted) setState(() => _searchRes = []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Future<void> _sendReq(Map<String, dynamic> u) async {
    final id = (u['id'] as num?)?.toInt();
    if (id == null || _busyId != 0) return;
    setState(() => _busyId = id);
    try {
      await ApiClient.I.friendRequest(id);
      u['relation'] = 'outgoing';
      _toast('好友申请已发送');
      _loadReqs();
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('申请失败');
    } finally {
      if (mounted) setState(() => _busyId = 0);
    }
  }

  Future<void> _accept(Map<String, dynamic> r) async {
    final id = (r['id'] as num?)?.toInt();
    if (id == null) return;
    try {
      await ApiClient.I.friendAccept(id);
      _toast('已添加为好友');
      _loadFriends();
      _loadReqs();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _reject(Map<String, dynamic> r) async {
    final id = (r['id'] as num?)?.toInt();
    if (id == null) return;
    try {
      await ApiClient.I.friendReject(id);
      _loadReqs();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _removeFriend(Map<String, dynamic> f) async {
    final id = (f['id'] as num?)?.toInt();
    if (id == null) return;
    final ok = await confirmMcDialog(context, '确定删除好友 ${chatUserName(f)} 吗?');
    if (ok != true) return;
    try {
      await ApiClient.I.friendRemove(id);
      setState(() => _friends.removeWhere((x) => x['id'] == f['id']));
      _toast('已删除好友');
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _chatWith(Map<String, dynamic> u) async {
    Navigator.pop(context);
    await widget.onChatWith(u);
  }

  @override
  Widget build(BuildContext context) {
    return _dialogShell(
      context,
      title: '好友',
      child: Column(children: [
        _segTabs(
            [('list', '好友'), ('req', '请求'), ('search', '搜索')], _tab,
            _reqs.length, (k) => setState(() => _tab = k)),
        if (_tab == 'search')
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: McInput(
              controller: _searchCtrl,
              hint: '输入用户名 / 昵称搜索',
              onChanged: _onSearchChanged,
            ),
          ),
        Expanded(child: _buildBody()),
      ]),
    );
  }

  Widget _buildBody() {
    if (_tab == 'list') return _buildFriendList();
    if (_tab == 'req') return _buildReqList();
    return _buildSearchList();
  }

  Widget _buildFriendList() {
    if (_friends.isEmpty) return const McEmpty('暂无好友, 去搜索添加');
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: _friends.length,
      itemBuilder: (_, i) {
        final f = _friends[i];
        final name = chatUserName(f);
        final id = (f['id'] as num?)?.toInt() ?? 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: ListTile(
            dense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            leading: _avatar(name, online: _onlineIds.contains(id)),
            title: Text(name, style: Mc.body(13),
                overflow: TextOverflow.ellipsis),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              _miniBtn('发消息', onTap: () => _chatWith(f)),
              const SizedBox(width: 6),
              _miniBtn('删除', color: Mc.bear, onTap: () => _removeFriend(f)),
            ]),
          ),
        );
      },
    );
  }

  Widget _buildReqList() {
    if (_reqs.isEmpty) return const McEmpty('暂无好友申请');
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: _reqs.length,
      itemBuilder: (_, i) {
        final r = _reqs[i];
        final name = chatUserName(r);
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: ListTile(
            dense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            leading: _avatar(name),
            title: Text(name, style: Mc.body(13),
                overflow: TextOverflow.ellipsis),
            subtitle: Text('请求添加你为好友',
                style: Mc.body(10, color: Mc.muted)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              _miniBtn('接受', color: Mc.bull, onTap: () => _accept(r)),
              const SizedBox(width: 6),
              _miniBtn('拒绝', color: Mc.muted, onTap: () => _reject(r)),
            ]),
          ),
        );
      },
    );
  }

  Widget _buildSearchList() {
    if (_searchCtrl.text.trim().isEmpty) {
      return const McEmpty('输入关键词搜索用户');
    }
    if (_searching) return const McLoading(label: '搜索中');
    if (_searchRes.isEmpty) return const McEmpty('无匹配用户');
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: _searchRes.length,
      itemBuilder: (_, i) {
        final u = _searchRes[i];
        final name = chatUserName(u);
        final relation = '${u['relation'] ?? 'none'}';
        final id = (u['id'] as num?)?.toInt() ?? 0;
        Widget action;
        if (relation == 'none') {
          action = _miniBtn(_busyId == id ? '发送中' : '加好友',
              onTap: _busyId == 0 ? () => _sendReq(u) : null);
        } else if (relation == 'friend') {
          action = _miniBtn('发消息', onTap: () => _chatWith(u));
        } else if (relation == 'incoming') {
          action = _miniBtn('去处理',
              color: Mc.amber, onTap: () => setState(() => _tab = 'req'));
        } else {
          action = Text('已申请', style: Mc.mono(11, color: Mc.muted));
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: ListTile(
            dense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            leading: _avatar(name),
            title: Text(name, style: Mc.body(13),
                overflow: TextOverflow.ellipsis),
            subtitle: Text('@${u['username'] ?? ''}',
                style: Mc.body(10, color: Mc.muted)),
            trailing: action,
          ),
        );
      },
    );
  }
}

// ==================== 建群对话框 ====================

/// onCreated: 建群成功后回调新会话 id, 由上层刷新列表并跳入.
Future<void> showGroupCreateDialog(BuildContext context,
    {required Future<void> Function(int convId) onCreated}) {
  return showDialog(
      context: context, builder: (_) => _GroupCreateDialog(onCreated: onCreated));
}

class _GroupCreateDialog extends StatefulWidget {
  const _GroupCreateDialog({required this.onCreated});
  final Future<void> Function(int convId) onCreated;

  @override
  State<_GroupCreateDialog> createState() => _GroupCreateDialogState();
}

class _GroupCreateDialogState extends State<_GroupCreateDialog> {
  final _nameCtrl = TextEditingController();
  List<Map<String, dynamic>> _friends = [];
  final _sel = <int>{};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ApiClient.I
        .friends()
        .then((res) => _FriendDialogState._asList(res))
        .then((list) {
      if (mounted) setState(() => _friends = list);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final conv = await ApiClient.I.createGroup(name, _sel.toList());
      final id = conv is Map ? (conv['id'] as num?)?.toInt() : null;
      if (!mounted) return;
      Navigator.pop(context);
      if (id != null) await widget.onCreated(id);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _dialogShell(
      context,
      title: '创建群聊',
      height: 480,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: McInput(controller: _nameCtrl, hint: '群名称 (必填)'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('从好友中选择成员 (已选 ${_sel.length})',
                style: Mc.body(11, color: Mc.muted)),
          ),
        ),
        Expanded(
          child: _friends.isEmpty
              ? const McEmpty('暂无好友, 可先发空群再拉人')
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _friends.length,
                  itemBuilder: (_, i) {
                    final f = _friends[i];
                    final id = (f['id'] as num?)?.toInt() ?? 0;
                    final name = chatUserName(f);
                    final on = _sel.contains(id);
                    return CheckboxListTile(
                      dense: true,
                      value: on,
                      onChanged: (_) =>
                          setState(() => on ? _sel.remove(id) : _sel.add(id)),
                      title: Text(name, style: Mc.body(13)),
                      secondary: _avatar(name, size: 26),
                      activeColor: Mc.cobalt,
                      checkColor: Colors.white,
                      controlAffinity: ListTileControlAffinity.trailing,
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            McButton('创建群聊',
                icon: Icons.group_add_outlined,
                busy: _busy,
                onPressed: _submit),
          ]),
        ),
      ]),
    );
  }
}

// ==================== 拉人入群对话框 ====================

/// 只能从好友里拉人, 且过滤已在群内的 (对齐 Chat.vue addCandidates).
Future<void> showAddMemberDialog(BuildContext context,
    {required int convId,
    required List<Map<String, dynamic>> members,
    required VoidCallback onAdded}) {
  return showDialog(
      context: context,
      builder: (_) =>
          _AddMemberDialog(convId: convId, members: members, onAdded: onAdded));
}

class _AddMemberDialog extends StatefulWidget {
  const _AddMemberDialog(
      {required this.convId, required this.members, required this.onAdded});
  final int convId;
  final List<Map<String, dynamic>> members;
  final VoidCallback onAdded;

  @override
  State<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<_AddMemberDialog> {
  List<Map<String, dynamic>> _candidates = [];
  final _sel = <int>{};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ApiClient.I
        .friends()
        .then((res) => _FriendDialogState._asList(res))
        .then((list) {
      if (!mounted) return;
      final inGroup = widget.members
          .map((m) => '${m['user_id'] ?? m['id']}')
          .toSet();
      setState(() => _candidates =
          list.where((f) => !inGroup.contains('${f['id']}')).toList());
    }).catchError((_) {});
  }

  Future<void> _submit() async {
    if (_sel.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      for (final uid in _sel) {
        await ApiClient.I.addChatMember(widget.convId, uid);
      }
      if (!mounted) return;
      Navigator.pop(context);
      widget.onAdded();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _dialogShell(
      context,
      title: '添加成员',
      height: 440,
      child: Column(children: [
        Expanded(
          child: _candidates.isEmpty
              ? const McEmpty('好友都已在群内')
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _candidates.length,
                  itemBuilder: (_, i) {
                    final f = _candidates[i];
                    final id = (f['id'] as num?)?.toInt() ?? 0;
                    final name = chatUserName(f);
                    final on = _sel.contains(id);
                    return CheckboxListTile(
                      dense: true,
                      value: on,
                      onChanged: (_) =>
                          setState(() => on ? _sel.remove(id) : _sel.add(id)),
                      title: Text(name, style: Mc.body(13)),
                      secondary: _avatar(name, size: 26),
                      activeColor: Mc.cobalt,
                      checkColor: Colors.white,
                      controlAffinity: ListTileControlAffinity.trailing,
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            McButton('添加 (已选 ${_sel.length})',
                icon: Icons.person_add_alt,
                busy: _busy,
                onPressed: _sel.isEmpty ? null : _submit),
          ]),
        ),
      ]),
    );
  }
}

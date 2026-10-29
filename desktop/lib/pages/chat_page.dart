import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../api/api_client.dart';
import '../state/auth_store.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/kit.dart';

/// 聊天 WebSocket 单例: JWT 鉴权 / 25s 心跳 / 指数退避重连 / 事件订阅.
/// 协议对齐 web-terminal/src/utils/chatWs.js; 事件 type: message / read / ping(忽略).
class _ChatWs {
  _ChatWs._();
  static final _ChatWs I = _ChatWs._();

  WebSocketChannel? _ws;
  bool _manualClose = false;
  Timer? _heartbeat;
  Timer? _reconnect;
  Duration _delay = const Duration(seconds: 1);
  static const _maxDelay = Duration(seconds: 30);
  final _listeners = <String, Set<void Function(Map<String, dynamic>)>>{};

  /// 连接状态: true = WS 在线 (停轮询), false = 断开 (回退 5s 轮询).
  final ValueNotifier<bool> live = ValueNotifier(false);

  void on(String type, void Function(Map<String, dynamic>) cb) {
    _listeners.putIfAbsent(type, () => {}).add(cb);
    connect();
  }

  void off(String type, void Function(Map<String, dynamic>) cb) {
    _listeners[type]?.remove(cb);
  }

  void connect() {
    final token = AuthStore.I.token;
    if (token == null || token.isEmpty) return;
    if (_ws != null) return;
    _manualClose = false;
    WebSocketChannel ch;
    try {
      ch = WebSocketChannel.connect(Uri.parse(
          'wss://shipapi.bdxapi.com/api/chat/ws?token=${Uri.encodeComponent(token)}'));
    } catch (_) {
      _scheduleReconnect();
      return;
    }
    _ws = ch;
    ch.ready.then((_) {
      if (_ws != ch) return;
      _delay = const Duration(seconds: 1); // 连上后重置退避
      live.value = true;
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
        try {
          _ws?.sink.add('ping'); // 服务端忽略非 JSON 帧
        } catch (_) {}
      });
    }).catchError((_) {});
    ch.stream.listen(_onFrame,
        onError: (_) => _onClosed(ch), onDone: () => _onClosed(ch));
  }

  void _onFrame(dynamic data) {
    if (data is! String) return;
    Map<String, dynamic> ev;
    try {
      final d = jsonDecode(data);
      if (d is! Map) return;
      ev = Map<String, dynamic>.from(d);
    } catch (_) {
      return;
    }
    final type = ev['type'];
    if (type is! String) return;
    final cbs = _listeners[type];
    if (cbs == null) return;
    for (final cb in List.of(cbs)) {
      try {
        cb(ev);
      } catch (_) {/* 单个订阅者异常不影响其他 */}
    }
  }

  void _onClosed(WebSocketChannel ch) {
    if (_ws != ch) return;
    _ws = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    live.value = false;
    if (!_manualClose && AuthStore.I.token != null) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnect != null || _manualClose) return;
    _reconnect = Timer(_delay, () {
      _reconnect = null;
      final d = _delay * 2; // 指数退避, 上限 30s
      _delay = d > _maxDelay ? _maxDelay : d;
      connect();
    });
  }

  /// logout / 页面 dispose: 主动关闭且不再重连.
  void disconnect() {
    _manualClose = true;
    _reconnect?.cancel();
    _reconnect = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    live.value = false;
    final ch = _ws;
    _ws = null;
    if (ch != null) {
      try {
        ch.sink.close();
      } catch (_) {}
    }
  }
}

/// 聊天页: 左会话列表 + 右消息区, WebSocket 实时 + 5s 轮询兜底, 仅文本消息.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _draft = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;

  List<Map<String, dynamic>> _convs = [];
  Map<String, dynamic>? _current;
  List<Map<String, dynamic>> _messages = [];

  bool _loadingConvs = true;
  String? _convsError;
  bool _loadingMsgs = false;
  String? _msgsError;
  bool _sending = false;
  String? _sendError;

  bool _wsLive = false;
  int? _peerReadId; // 单聊对方已读游标; null = 群聊/未收到回执, 不画回执

  // ---------- 群成员 (对齐 web-terminal Chat.vue: members/memberFilter/roleBadge) ----------
  List<Map<String, dynamic>> _members = [];
  String _memberFilter = 'all'; // all | online | admin
  bool _showMention = false;
  String _mentionQuery = ''; // @ 后已输入的过滤串

  // ---------- 钉选会话 (shared_preferences 'mc_pinned_chats', 对齐 Chat.vue pinnedChats) ----------
  final Set<String> _pinned = {};

  // ---------- 频道内搜索 (本地过滤已加载消息, 对齐 Chat.vue searchOpen/searchQuery) ----------
  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();

  // ---------- 输入工具: emoji 面板 (对齐 Chat.vue EMOJIS) ----------
  bool _showEmoji = false;
  static const _emojis = [
    '👍', '🔥', '🚀', '📈', '📉', '💰',
    '⚠️', '🎯', '🐳', '💎', '🤝', '😂',
  ];

  int? get _myId {
    final v = AuthStore.I.user?['id'];
    return v is num ? v.toInt() : int.tryParse('$v');
  }

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _wsLive = _ChatWs.I.live.value;
    _ChatWs.I.live.addListener(_onWsLiveChanged);
    _ChatWs.I.on('message', _onWsMessage);
    _ChatWs.I.on('read', _onWsRead);
    AuthStore.I.addListener(_onAuthChanged);
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
    _draft.addListener(_onDraftChanged);
    _loadPinned();
  }

  @override
  void dispose() {
    _ChatWs.I.live.removeListener(_onWsLiveChanged);
    _ChatWs.I.off('message', _onWsMessage);
    _ChatWs.I.off('read', _onWsRead);
    _ChatWs.I.disconnect();
    AuthStore.I.removeListener(_onAuthChanged);
    _timer?.cancel();
    _draft.removeListener(_onDraftChanged);
    _draft.dispose();
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onWsLiveChanged() {
    if (!mounted) return;
    setState(() => _wsLive = _ChatWs.I.live.value);
  }

  void _onAuthChanged() {
    if (AuthStore.I.token == null) _ChatWs.I.disconnect();
  }

  // ---------- 数据 ----------
  static List<Map<String, dynamic>> _asList(dynamic res) {
    final raw = res is Map ? res['items'] : res;
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _loadConversations() async {
    setState(() {
      _loadingConvs = true;
      _convsError = null;
    });
    try {
      final list = _asList(await ApiClient.I.conversations());
      if (!mounted) return;
      setState(() {
        _convs = list;
        _loadingConvs = false;
      });
      if (_current == null && list.isNotEmpty) _select(list.first);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingConvs = false;
        _convsError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingConvs = false;
        _convsError = '会话列表加载失败';
      });
    }
  }

  Future<void> _loadMessages({bool silent = false, bool scroll = false}) async {
    final c = _current;
    if (c == null) return;
    final cid = (c['id'] as num).toInt();
    if (!silent) {
      setState(() {
        _loadingMsgs = true;
        _msgsError = null;
      });
    }
    try {
      final res = await ApiClient.I.chatMessages(cid, {'limit': 50});
      // 接口最新在前, 反转为时间正序
      final list = _asList(res).reversed.toList();
      if (!mounted || _current?['id'] != cid) return;
      setState(() {
        _messages = list;
        _loadingMsgs = false;
        _msgsError = null;
      });
      if (scroll) _scrollBottom();
      _markRead();
    } on ApiException catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _loadingMsgs = false;
        _msgsError = e.message;
      });
    } catch (_) {
      if (!mounted || silent) return;
      setState(() {
        _loadingMsgs = false;
        _msgsError = '消息加载失败';
      });
    }
  }

  /// 推进已读游标到最大 message_id, 并清本地未读角标.
  void _markRead() {
    final c = _current;
    if (c == null || _messages.isEmpty) return;
    var maxId = 0;
    for (final m in _messages) {
      final id = m['id'];
      if (id is num && id.toInt() > maxId) maxId = id.toInt();
    }
    if (maxId == 0) return;
    ApiClient.I.markRead((c['id'] as num).toInt(), maxId).catchError((_) {});
    if ((c['unread_count'] ?? 0) != 0) {
      setState(() => c['unread_count'] = 0);
    }
  }

  Future<void> _select(Map<String, dynamic> c) async {
    if (_current?['id'] == c['id']) return;
    setState(() {
      _current = c;
      _messages = [];
      _sendError = null;
      _peerReadId = null;
      _members = [];
      _showMention = false;
      _searchCtrl.clear(); // 切换会话清空搜索词 (对齐 web select)
    });
    await _loadMessages(scroll: true);
    // 群聊加载成员列表 (静默降级); 单聊跳过
    if (c['type'] != 'direct') {
      unawaited(_loadMembers((c['id'] as num).toInt()));
    }
    // Seed peer read cursor so receipts render before the next `read` event.
    try {
      final id = (_current?['id'] as num?)?.toInt();
      if (id == null || _current?['id'] != c['id']) return;
      final rs = await ApiClient.I.peerReadState(id);
      final pid = rs is Map ? rs['peer_last_read_message_id'] : null;
      if (mounted && pid is num && _current?['id'] == c['id']) {
        setState(() => _peerReadId = pid.toInt());
      }
    } catch (_) {/* no read state available */}
  }

  void _poll() {
    if (_ChatWs.I.live.value) return; // WS 在线时停掉 5s 轮询
    if (_current != null && !_loadingMsgs) {
      _loadMessages(silent: true);
    }
  }

  // ---------- WebSocket 实时事件 (对齐 web-terminal Chat.vue) ----------

  /// type=message: {conversation_id, message{id, msg_type, content, sender, created_at}}
  void _onWsMessage(Map<String, dynamic> ev) {
    if (!mounted) return;
    final convId = ev['conversation_id'];
    final raw = ev['message'];
    if (convId == null || raw is! Map || raw['id'] == null) return;
    final msg = Map<String, dynamic>.from(raw);
    final mine = _isMine(msg);
    final cur = _current;
    if (cur != null && '${cur['id']}' == '$convId') {
      // 当前房间: 按 message id 去重后追加, 贴底时跟随滚动, 并推进已读
      if (!_messages.any((x) => '${x['id']}' == '${msg['id']}')) {
        final nearBottom = !_scroll.hasClients ||
            _scroll.position.maxScrollExtent - _scroll.position.pixels < 120;
        setState(() => _messages.add(msg));
        if (nearBottom) _scrollBottom();
      }
      _markRead();
      return;
    }
    // 其他房间: 未读+1 (自己发的不计), 更新 last_message 并顶到最前
    final idx = _convs.indexWhere((x) => '${x['id']}' == '$convId');
    if (idx >= 0) {
      setState(() {
        final c = _convs.removeAt(idx);
        if (!mine) {
          final u = c['unread_count'];
          c['unread_count'] = (u is num ? u.toInt() : 0) + 1;
        }
        final sender = msg['sender'];
        c['last_message'] = {
          'id': msg['id'],
          'msg_type': msg['msg_type'],
          'content': msg['content'],
          'sender_name':
              sender is Map ? (sender['nickname'] ?? sender['username'] ?? '') : '',
          'created_at': msg['created_at'],
          'is_mine': mine,
          'read': null,
        };
        _convs.insert(0, c);
      });
    } else {
      _loadConversations(); // 未知会话 (新会话), 重新拉列表
    }
  }

  /// type=read: {conversation_id, message_id} — 对方已读回执, 只推进游标.
  void _onWsRead(Map<String, dynamic> ev) {
    if (!mounted) return;
    final cur = _current;
    if (cur == null || '${ev['conversation_id']}' != '${cur['id']}') return;
    final id = int.tryParse('${ev['message_id']}');
    if (id == null) return;
    if (_peerReadId == null || id > _peerReadId!) {
      setState(() => _peerReadId = id);
    }
  }

  Future<void> _send() async {
    final text = _draft.text.trim();
    final c = _current;
    if (text.isEmpty || c == null || _sending) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await ApiClient.I
          .sendChatMessage((c['id'] as num).toInt(), {'type': 'text', 'content': text});
      if (!mounted) return;
      _draft.clear();
      await _loadMessages(silent: true, scroll: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _sendError = '发送失败: ${e.message}');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('发送失败: ${e.message}')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _sendError = '发送失败, 请稍后重试');
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('发送失败, 请稍后重试')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  // ---------- 展示辅助 ----------
  bool _isMine(Map<String, dynamic> m) {
    final sender = m['sender'];
    final sid = sender is Map ? sender['id'] : null;
    final my = _myId;
    return sid != null && my != null && '$sid' == '$my';
  }

  String _nameOf(Map<String, dynamic> m) {
    final sender = m['sender'];
    if (sender is Map) {
      final n = sender['nickname'] ?? sender['username'];
      if (n != null && '$n'.isNotEmpty) return '$n';
    }
    return _isMine(m) ? '我' : '用户${sender is Map ? sender['id'] ?? '' : ''}';
  }

  String _convTitle(Map<String, dynamic> c) =>
      (c['title'] ?? c['name'] ?? '会话 ${c['id']}') as String;

  // ---------- 群成员: 加载 / 过滤 / 提及 (对齐 Chat.vue) ----------

  /// 当前是否群聊 (单聊不显示成员栏, 不启用 @ 面板).
  bool get _isGroup => _current != null && _current!['type'] != 'direct';

  Future<void> _loadMembers(int cid) async {
    try {
      final list = _asList(await ApiClient.I.chatMembers(cid));
      if (!mounted || '${_current?['id']}' != '$cid') return;
      setState(() => _members = list);
    } catch (_) {
      // 静默降级: 空列表提示 暂无成员, 不影响聊天主流程
      if (!mounted || '${_current?['id']}' != '$cid') return;
      setState(() => _members = []);
    }
  }

  String _memberName(Map<String, dynamic> m) {
    final n = m['nickname'] ?? m['username'];
    if (n != null && '$n'.isNotEmpty) return '$n';
    return '用户${m['user_id'] ?? m['id'] ?? ''}';
  }

  /// owner → 群主; 非 member 角色 → 管理; 否则无徽标.
  String _roleBadge(Map<String, dynamic> m) {
    final role = m['role'];
    if (role == 'owner') return '群主';
    if (role != null && role != 'member') return '管理';
    return '';
  }

  bool _isAdminMember(Map<String, dynamic> m) => _roleBadge(m).isNotEmpty;

  bool _isOnlineMember(Map<String, dynamic> m) =>
      m['online'] != false && m['is_online'] != false;

  List<Map<String, dynamic>> get _filteredMembers {
    if (_memberFilter == 'online') return _members.where(_isOnlineMember).toList();
    if (_memberFilter == 'admin') return _members.where(_isAdminMember).toList();
    return _members;
  }

  /// 输入监听: 光标前最近一个 @ 到光标之间为提及过滤串时弹出成员面板.
  void _onDraftChanged() {
    if (!_isGroup || _members.isEmpty) {
      if (_showMention) setState(() => _showMention = false);
      return;
    }
    final sel = _draft.selection;
    final text = _draft.text;
    if (!sel.isValid || sel.start < 0) {
      if (_showMention) setState(() => _showMention = false);
      return;
    }
    final upto = text.substring(0, sel.start);
    final at = upto.lastIndexOf('@');
    final frag = at < 0 ? null : upto.substring(at + 1);
    final show = frag != null &&
        frag.length <= 20 &&
        !frag.contains(RegExp(r'\s'));
    if (show != _showMention || (show && frag != _mentionQuery)) {
      setState(() {
        _showMention = show;
        _mentionQuery = show ? frag : '';
      });
    }
  }

  /// 点击提及面板成员: 把 `@名字 ` 替换进输入框 (替换 @query 段).
  void _pickMember(Map<String, dynamic> m) {
    final name = _memberName(m);
    final insert = '@$name ';
    final text = _draft.text;
    final sel = _draft.selection;
    if (sel.isValid && sel.start >= 0) {
      final upto = text.substring(0, sel.start);
      final at = upto.lastIndexOf('@');
      if (at >= 0) {
        final next = text.replaceRange(at, sel.start, insert);
        _draft.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: at + insert.length),
        );
      } else {
        _draft.value = TextEditingValue(
          text: text + insert,
          selection: TextSelection.collapsed(offset: text.length + insert.length),
        );
      }
    } else {
      _draft.value = TextEditingValue(
        text: text + insert,
        selection: TextSelection.collapsed(offset: text.length + insert.length),
      );
    }
    setState(() => _showMention = false);
  }

  // ---------- 钉选会话 ----------

  Future<void> _loadPinned() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final list = sp.getStringList('mc_pinned_chats') ?? [];
      if (!mounted) return;
      setState(() {
        _pinned
          ..clear()
          ..addAll(list);
      });
    } catch (_) {/* 读取失败按无钉选处理 */}
  }

  bool _isPinned(Map<String, dynamic> c) => _pinned.contains('${c['id']}');

  Future<void> _togglePin(Map<String, dynamic> c) async {
    final id = '${c['id']}';
    setState(() {
      if (!_pinned.remove(id)) _pinned.add(id);
    });
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList('mc_pinned_chats', _pinned.toList());
    } catch (_) {/* 持久化失败不阻塞 UI */}
  }

  /// 钉选会话排最前, 组内保持原顺序 (稳定排序).
  List<Map<String, dynamic>> get _sortedConvs {
    if (_pinned.isEmpty) return _convs;
    final idx = <String, int>{
      for (var i = 0; i < _convs.length; i++) '${_convs[i]['id']}': i
    };
    final list = List.of(_convs);
    list.sort((a, b) {
      final pa = _pinned.contains('${a['id']}') ? 0 : 1;
      final pb = _pinned.contains('${b['id']}') ? 0 : 1;
      if (pa != pb) return pa - pb;
      return (idx['${a['id']}'] ?? 0).compareTo(idx['${b['id']}'] ?? 0);
    });
    return list;
  }

  // ---------- 频道内搜索 ----------

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) _searchCtrl.clear();
    });
  }

  /// 当前展示消息: 有关键词时按内容本地过滤.
  List<Map<String, dynamic>> get _shownMessages {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _messages;
    return _messages
        .where((m) => '${m['content'] ?? ''}'.toLowerCase().contains(q))
        .toList();
  }

  // ---------- 输入条插入工具 (对齐 Chat.vue insertText/insertCode/insertTicker) ----------

  /// 在光标处插入文本并把光标移到插入内容之后.
  void _insertText(String t) {
    final text = _draft.text;
    final sel = _draft.selection;
    if (sel.isValid && sel.start >= 0) {
      final next = text.replaceRange(sel.start, sel.end, t);
      final p = sel.start + t.length;
      _draft.value = TextEditingValue(
          text: next, selection: TextSelection.collapsed(offset: p));
    } else {
      _draft.value = TextEditingValue(
          text: text + t,
          selection: TextSelection.collapsed(offset: text.length + t.length));
    }
  }

  void _insertCode() => _insertText('\n```\n\n```\n');

  /// 拉 BTC-USDT 行情, 生成 `[BTC $价 ±x%]` 文本卡插入输入框 (静默降级).
  Future<void> _insertTicker() async {
    try {
      final res = await ApiClient.I.ticker('BTC-USDT');
      if (res is! Map) return;
      final raw = res['data'];
      final Map d = raw is List && raw.isNotEmpty && raw.first is Map
          ? raw.first as Map
          : (raw is Map ? raw : const {});
      final last = double.tryParse('${d['last']}');
      if (last == null) return;
      final open = double.tryParse('${d['open24h']}');
      double? pct;
      if (open != null && open != 0) pct = (last - open) / open * 100;
      _insertText('[BTC \$${_fmtThousands(d['last'])}'
          '${pct != null ? ' ${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%' : ''}]');
    } catch (_) {/* 静默降级 */}
  }

  /// 千分位格式化, 保留原始小数位 (对齐 web toLocaleString).
  static String _fmtThousands(dynamic v) {
    final s = '$v';
    final dot = s.indexOf('.');
    final intPart = (dot < 0 ? s : s.substring(0, dot)).replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return dot < 0 ? intPart : '$intPart${s.substring(dot)}';
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _buildSidebar(),
      const VerticalDivider(width: 1, color: Mc.hairline),
      Expanded(child: _buildMain()),
      if (_isGroup) ...[
        const VerticalDivider(width: 1, color: Mc.hairline),
        _buildMemberRail(),
      ],
    ]);
  }

  /// 右栏: 在线成员列表 (仅群聊) — 标题 + 全部/在线/管理 分段过滤 + 成员行.
  Widget _buildMemberRail() {
    final list = _filteredMembers;
    return Container(
      width: 212,
      color: Mc.surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const McTag('ONLINE', color: Mc.bull),
            const SizedBox(height: 4),
            Text('在线成员 (${list.length})', style: Mc.display(14)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: _buildMemberFilter(),
        ),
        const Divider(height: 1, color: Mc.hairline),
        Expanded(
          child: list.isEmpty
              ? const McEmpty('暂无成员')
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: list.length > 30 ? 30 : list.length,
                  itemBuilder: (_, i) => _MemberTile(
                    name: _memberName(list[i]),
                    badge: _roleBadge(list[i]),
                    online: _isOnlineMember(list[i]),
                    isMe: '${list[i]['user_id'] ?? list[i]['id']}' == '$_myId',
                    onTap: () => _pickMember(list[i]),
                  ),
                ),
        ),
      ]),
    );
  }

  /// 全部 / 在线 / 管理 小分段控件.
  Widget _buildMemberFilter() {
    const items = [('all', '全部'), ('online', '在线'), ('admin', '管理')];
    return Container(
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
              onTap: () => setState(() => _memberFilter = key),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(
                  color: _memberFilter == key
                      ? Mc.cardHigh
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text(label,
                    style: Mc.body(11,
                        w: _memberFilter == key
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color:
                            _memberFilter == key ? Mc.cobaltSoft : Mc.muted)),
              ),
            ),
          ),
      ]),
    );
  }

  /// 提及成员面板: 过滤匹配, 点击插入 @名字.
  Widget _buildMentionPanel() {
    final q = _mentionQuery.toLowerCase();
    final list = _members
        .where((m) => q.isEmpty || _memberName(m).toLowerCase().contains(q))
        .take(8)
        .toList();
    return Container(
      width: 224,
      constraints: const BoxConstraints(maxHeight: 208),
      decoration: BoxDecoration(
        color: Mc.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Mc.hairline),
      ),
      child: list.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                  child: Text('暂无成员',
                      style: Mc.mono(11, color: Mc.muted))),
            )
          : ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.all(6),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final m = list[i];
                final name = _memberName(m);
                return InkWell(
                  borderRadius: BorderRadius.circular(6),
                  hoverColor: Mc.cardHigh,
                  onTap: () => _pickMember(m),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(children: [
                      _MemberAvatar(name: name, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(name,
                            style: Mc.body(12),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ]),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 300,
      color: Mc.surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const McTag('CHANNELS', color: Mc.cobaltSoft),
              const SizedBox(height: 4),
              Text('情报频道', style: Mc.display(15)),
            ]),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18, color: Mc.muted),
              tooltip: '刷新会话',
              onPressed: _loadConversations,
            ),
          ]),
        ),
        const Divider(height: 1, color: Mc.hairline),
        Expanded(child: _buildConvList()),
      ]),
    );
  }

  Widget _buildConvList() {
    if (_loadingConvs) return const McLoading(label: '加载会话中');
    if (_convsError != null) {
      return McError(_convsError!, onRetry: _loadConversations);
    }
    if (_convs.isEmpty) return const McEmpty('暂无会话');
    final list = _sortedConvs;
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: list.length,
      itemBuilder: (_, i) => _ConvTile(
        conv: list[i],
        title: _convTitle(list[i]),
        selected: _current?['id'] == list[i]['id'],
        pinned: _isPinned(list[i]),
        onTap: () => _select(list[i]),
        onTogglePin: () => _togglePin(list[i]),
      ),
    );
  }

  Widget _buildMain() {
    final c = _current;
    return Column(children: [
      Container(
        height: Mc.topbarHeight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: const BoxDecoration(
          color: Mc.surface,
          border: Border(bottom: BorderSide(color: Mc.hairline)),
        ),
        child: Row(children: [
          Text('#', style: Mc.mono(16, w: FontWeight.w700, color: Mc.cobalt)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(c == null ? '聊天室' : _convTitle(c),
                style: Mc.display(15), overflow: TextOverflow.ellipsis),
          ),
          McTag(_wsLive ? 'WS LIVE' : 'POLLING',
              color: _wsLive ? Mc.bull : Mc.muted),
          const SizedBox(width: 10),
          Text('${_messages.length} 条消息',
              style: Mc.mono(11, color: Mc.muted)),
          const SizedBox(width: 10),
          _buildPinButton(c),
          IconButton(
            icon: Icon(Icons.search,
                size: 18, color: _searchOpen ? Mc.cobaltSoft : Mc.muted),
            tooltip: '搜索此频道历史消息',
            onPressed: c == null ? null : _toggleSearch,
          ),
        ]),
      ),
      if (_searchOpen) _buildSearchBar(),
      Expanded(child: _buildMessages()),
      _buildComposer(),
    ]);
  }

  /// 会话头部钉选按钮: 已钉选 = Cobalt 着色, 未钉选 = 描边灰 (对齐 web).
  Widget _buildPinButton(Map<String, dynamic>? c) {
    final pinned = c != null && _isPinned(c);
    return Material(
      color: pinned ? Mc.cobalt.withValues(alpha: 0.2) : Mc.card,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: c == null ? null : () => _togglePin(c),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border:
                Border.all(color: pinned ? Mc.cobaltSoft : Mc.hairline),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.push_pin,
                size: 13, color: pinned ? Mc.cobaltSoft : Mc.muted),
            const SizedBox(width: 4),
            Text(pinned ? '已钉选' : '钉选',
                style: Mc.mono(11,
                    color: pinned ? Mc.cobaltSoft : Mc.muted)),
          ]),
        ),
      ),
    );
  }

  /// 频道内搜索条: 关键词输入 + 匹配计数 + 关闭 (对齐 web search bar).
  Widget _buildSearchBar() {
    final q = _searchCtrl.text.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Mc.cardHigh.withValues(alpha: 0.4),
        border: const Border(bottom: BorderSide(color: Mc.hairline)),
      ),
      child: Row(children: [
        const Icon(Icons.search, size: 15, color: Mc.muted),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            autofocus: true,
            style: Mc.body(12),
            cursorColor: Mc.cobaltSoft,
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: '在当前频道消息中搜索…',
              hintStyle:
                  Mc.body(12, color: Mc.muted.withValues(alpha: 0.6)),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (q.isNotEmpty) ...[
          McBadge('匹配 ${_shownMessages.length} 条', color: Mc.cobaltSoft),
          const SizedBox(width: 4),
        ],
        IconButton(
          icon: const Icon(Icons.close, size: 14, color: Mc.muted),
          tooltip: '关闭搜索',
          onPressed: _toggleSearch,
        ),
      ]),
    );
  }

  Widget _buildMessages() {
    if (_current == null) return const McEmpty('请选择左侧会话开始聊天');
    if (_loadingMsgs) return const McLoading(label: '加载消息中');
    if (_msgsError != null) {
      return McError(_msgsError!, onRetry: () => _loadMessages(scroll: true));
    }
    if (_messages.isEmpty) return const McEmpty('暂无消息, 来说第一句');
    final list = _shownMessages;
    if (list.isEmpty) return const McEmpty('无匹配消息');
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final m = list[i];
        if (m['msg_type'] == 'system' || m['type'] == 'system') {
          return _SystemMsg(text: '${m['content'] ?? ''}');
        }
        final mine = _isMine(m);
        // 单聊已读回执: 我方消息 id <= 对方已读游标 视为已读
        final mid = m['id'];
        final bool? read = mine &&
                _current?['type'] == 'direct' &&
                _peerReadId != null &&
                mid is num
            ? mid.toInt() <= _peerReadId!
            : null;
        return _Bubble(
          mine: mine,
          name: _nameOf(m),
          content: '${m['content'] ?? ''}',
          time: Fmt.mdHm(m['created_at']),
          read: read,
        );
      },
    );
  }

  Widget _buildComposer() {
    final enabled = _current != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: const BoxDecoration(
        color: Mc.surface,
        border: Border(top: BorderSide(color: Mc.hairline)),
      ),
      child: Stack(clipBehavior: Clip.none, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_sendError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_sendError!, style: Mc.body(11, color: Mc.bear)),
            ),
          Row(children: [
            Expanded(
              child: McInput(
                controller: _draft,
                hint: enabled
                    ? (_isGroup ? '输入消息, @ 提及成员, 回车发送' : '输入消息, 回车发送')
                    : '请先选择会话',
                onSubmitted: enabled ? (_) => _send() : null,
              ),
            ),
            const SizedBox(width: 10),
            McButton(
              '发送',
              icon: Icons.send,
              busy: _sending,
              onPressed: enabled ? _send : null,
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _toolBtn(
              icon: Icons.emoji_emotions_outlined,
              tooltip: '插入表情',
              active: _showEmoji,
              onTap: enabled
                  ? () => setState(() {
                        _showEmoji = !_showEmoji;
                        if (_showEmoji) _showMention = false;
                      })
                  : null,
            ),
            _toolBtn(
              icon: Icons.code,
              tooltip: '插入代码块',
              onTap: enabled ? _insertCode : null,
            ),
            _toolBtn(
              icon: Icons.insights,
              tooltip: '插入 BTC 实时行情',
              onTap: enabled ? _insertTicker : null,
            ),
            const Spacer(),
            const McTag('ENTER TO SEND'),
          ]),
        ]),
        // 提及成员面板 / emoji 面板: 弹出在输入框上方, 覆盖消息区底部
        if (_showMention && _isGroup)
          Positioned(left: 0, bottom: 104, child: _buildMentionPanel()),
        if (_showEmoji)
          Positioned(left: 0, bottom: 104, child: _buildEmojiPanel()),
      ]),
    );
  }

  /// 输入工具小图标按钮 (对齐 web 工具条).
  Widget _toolBtn({
    required IconData icon,
    required String tooltip,
    VoidCallback? onTap,
    bool active = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: active ? Mc.cardHigh : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 16, color: active ? Mc.ink : Mc.muted),
        ),
      ),
    );
  }

  /// emoji 面板: 6 列网格, 点击插入输入框并关闭 (对齐 web EMOJIS grid).
  Widget _buildEmojiPanel() {
    return Container(
      width: 224,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Mc.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Mc.hairline),
      ),
      child: GridView.count(
        crossAxisCount: 6,
        shrinkWrap: true,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final e in _emojis)
            InkWell(
              borderRadius: BorderRadius.circular(6),
              hoverColor: Mc.cardHigh,
              onTap: () {
                _insertText(e);
                setState(() => _showEmoji = false);
              },
              child: Center(
                  child: Text(e, style: const TextStyle(fontSize: 16))),
            ),
        ],
      ),
    );
  }
}

/// 会话列表项.
class _ConvTile extends StatelessWidget {
  const _ConvTile({
    required this.conv,
    required this.title,
    required this.selected,
    required this.pinned,
    required this.onTap,
    required this.onTogglePin,
  });
  final Map<String, dynamic> conv;
  final String title;
  final bool selected;

  /// 已钉选: 行尾显示图钉, 点击取消钉选 (对齐 web push_pin).
  final bool pinned;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;

  @override
  Widget build(BuildContext context) {
    final unread = conv['unread_count'] is num
        ? (conv['unread_count'] as num).toInt()
        : 0;
    final last = conv['last_message'];
    final preview = last is Map ? '${last['content'] ?? ''}' : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? Mc.cardHigh : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: Mc.cardHigh.withValues(alpha: 0.5),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: selected
                  ? const Border(
                      left: BorderSide(color: Mc.cobalt, width: 2))
                  : null,
            ),
            child: Row(children: [
              Text('#',
                  style: Mc.mono(13,
                      w: FontWeight.w700,
                      color: selected ? Mc.cobaltSoft : Mc.muted)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Mc.body(12,
                              w: selected ? FontWeight.w600 : FontWeight.w400,
                              color: selected ? Mc.ink : Mc.muted),
                          overflow: TextOverflow.ellipsis),
                      if (preview.isNotEmpty)
                        Text(preview,
                            style: Mc.body(10, color: Mc.muted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                    ]),
              ),
              if (pinned)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTogglePin,
                  child: const Padding(
                    padding: EdgeInsets.all(3),
                    child:
                        Icon(Icons.push_pin, size: 13, color: Mc.cobaltSoft),
                  ),
                ),
              if (unread > 0)
                McBadge(unread > 99 ? '99+' : '$unread',
                    color: selected ? Mc.cobaltSoft : Mc.bear),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 消息气泡: 己方右对齐 Cobalt, 对方左对齐 Card.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.mine,
    required this.name,
    required this.content,
    required this.time,
    this.read,
  });
  final bool mine;
  final String name;
  final String content;
  final String time;

  /// 已读回执: null 不显示, true 已读, false 已送达.
  final bool? read;

  @override
  Widget build(BuildContext context) {
    final meta = Row(mainAxisSize: MainAxisSize.min, children: [
      if (mine) ...[
        if (read != null) ...[
          Icon(read! ? Icons.done_all : Icons.done,
              size: 13, color: read! ? Mc.bull : Mc.muted),
          const SizedBox(width: 4),
        ],
        Text(time, style: Mc.mono(10, color: Mc.muted)),
        const SizedBox(width: 8),
        Text('$name (我)',
            style: Mc.body(11, w: FontWeight.w600, color: Mc.cobaltSoft)),
      ] else ...[
        Text(name, style: Mc.body(11, w: FontWeight.w600, color: Mc.ink)),
        const SizedBox(width: 8),
        Text(time, style: Mc.mono(10, color: Mc.muted)),
      ],
    ]);
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: mine ? Mc.cobalt : Mc.card,
        borderRadius: BorderRadius.circular(10),
        border: mine ? null : Border.all(color: Mc.hairline),
      ),
      child: _msgContent(content, mine),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [meta, const SizedBox(height: 4), bubble],
      ),
    );
  }
}

/// 消息正文: ``` 包裹段渲染为等宽字体深色底代码块, 其余段走高亮 span.
Widget _msgContent(String content, bool mine) {
  final base = Mc.body(12, color: mine ? Colors.white : Mc.ink);
  final parts = content.split('```');
  if (parts.length < 3) {
    return SelectableText.rich(_richSpans(content, base, mine));
  }
  final children = <Widget>[];
  for (var i = 0; i < parts.length; i++) {
    var seg = parts[i];
    if (i.isOdd) {
      // 代码块: 去掉围栏相邻的首尾换行
      if (seg.startsWith('\n')) seg = seg.substring(1);
      if (seg.endsWith('\n')) seg = seg.substring(0, seg.length - 1);
      children.add(Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Mc.canvas,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Mc.hairline),
        ),
        child: SelectableText(seg.isEmpty ? ' ' : seg,
            style: Mc.mono(11, color: mine ? Colors.white : Mc.ink)),
      ));
    } else if (seg.isNotEmpty) {
      children.add(SelectableText.rich(_richSpans(seg, base, mine)));
    }
  }
  if (children.isEmpty) {
    return SelectableText.rich(_richSpans(content, base, mine));
  }
  return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children);
}

/// 普通文本高亮: @提及 + `[BTC $… ±x%]` 行情卡 (涨跌色 up/down).
TextSpan _richSpans(String text, TextStyle base, bool mine) {
  final spans = <TextSpan>[];
  final re = RegExp(
      r'@[^\s@]+|\[BTC \$[\d,]+(?:\.\d+)?(?: [+-]\d+(?:\.\d+)?%)?\]');
  var i = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > i) spans.add(TextSpan(text: text.substring(i, m.start)));
    final tok = m.group(0)!;
    if (tok.startsWith('@')) {
      spans.add(TextSpan(
          text: tok,
          style: TextStyle(
              color: mine ? Colors.white : Mc.cobaltSoft,
              fontWeight: FontWeight.w600)));
    } else {
      spans.add(TextSpan(
          text: tok,
          style: Mc.mono(12,
              w: FontWeight.w600,
              color: tok.contains('-') ? Mc.down : Mc.up)));
    }
    i = m.end;
  }
  if (i < text.length) spans.add(TextSpan(text: text.substring(i)));
  if (spans.isEmpty) spans.add(TextSpan(text: text));
  return TextSpan(style: base, children: spans);
}

/// 成员头像: 首字符圆形.
class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({required this.name, this.size = 28, this.isMe = false});
  final String name;
  final double size;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final initial =
        name.isEmpty ? 'U' : name.substring(0, 1).toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isMe ? Mc.cobalt : Mc.cardHigh,
        border: Border.all(color: isMe ? Mc.cobaltSoft : Mc.hairline),
      ),
      alignment: Alignment.center,
      child: Text(initial,
          style: Mc.mono(size * 0.4,
              w: FontWeight.w700, color: isMe ? Colors.white : Mc.ink)),
    );
  }
}

/// 成员列表行: 头像 + 名字 + 群主/管理徽标 + 在线绿点.
class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.name,
    required this.badge,
    required this.online,
    required this.isMe,
    required this.onTap,
  });
  final String name;
  final String badge;
  final bool online;
  final bool isMe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: Mc.cardHigh.withValues(alpha: 0.5),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(children: [
              _MemberAvatar(name: name, isMe: isMe),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(isMe ? '$name (我)' : name,
                          style: Mc.body(12,
                              w: isMe ? FontWeight.w600 : FontWeight.w400,
                              color: isMe ? Mc.cobaltSoft : Mc.ink),
                          overflow: TextOverflow.ellipsis),
                      if (badge.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        McBadge(badge, color: Mc.amber),
                      ],
                    ]),
              ),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: online ? Mc.bull : Mc.hairline,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 系统消息胶囊.
class _SystemMsg extends StatelessWidget {
  const _SystemMsg({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Mc.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Mc.hairline),
            ),
            child:
                Text('系统: $text', style: Mc.mono(10, color: Mc.muted)),
          ),
        ),
      );
}

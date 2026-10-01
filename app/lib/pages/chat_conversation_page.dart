import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/auth.dart';
import '../services/chat_api.dart';
import '../services/chat_ws.dart';
import 'market_detail_page.dart';

/// 聊天房间: 倒序消息流, 向上翻页, 回复 / 表情表态 / 复制, 币种标签跳转行情,
/// 乐观发送 (pending → 成功/失败重试), WS 实时追加 + 已读上报.
class ChatConversationPage extends StatefulWidget {
  const ChatConversationPage({super.key, required this.conversation});

  final Conversation conversation;

  @override
  State<ChatConversationPage> createState() => _ChatConversationPageState();
}

enum _SendState { sending, failed }

/// 本地乐观消息 (未确认).
class _Pending {
  _Pending({
    required this.content,
    this.replyTo,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String content;
  final ChatMessage? replyTo;
  _SendState state = _SendState.sending;
  final DateTime createdAt;
}

class _ChatConversationPageState extends State<ChatConversationPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  // 最新消息在前 (index 0 = 最新, 配合 reverse ListView 显示在底部).
  final List<ChatMessage> _messages = [];
  final List<_Pending> _pending = []; // 最新在前

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _loadFailed = false;

  ChatMessage? _replyingTo;
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  static final _coinTag = RegExp(r'\$([A-Za-z0-9]{2,10})');
  static const _emojis = ['👍', '❤️', '🔥', '😂', '😮', '😢'];

  int get _myId => AuthStore.instance.userId ?? -1;
  bool get _isGroup => widget.conversation.isGroup;

  @override
  void initState() {
    super.initState();
    ChatWs.instance.connect();
    _loadInitial();
    _wsSub = ChatWs.instance.events.listen(_onWsEvent);
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _scroll.dispose();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ---------- 加载 ----------

  Future<void> _loadInitial() async {
    try {
      final list = await ChatApi.messages(widget.conversation.id);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(list);
        _hasMore = list.length >= 50;
        _loading = false;
        _loadFailed = false;
      });
      _markRead();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  void _maybeLoadMore() {
    // reverse 列表: 滚动到顶端 (最大偏移) 即最旧消息处.
    if (!_hasMore || _loadingMore || _loading) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 80) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_messages.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final older = await ChatApi.messages(widget.conversation.id,
          beforeId: _messages.last.id);
      if (!mounted) return;
      setState(() {
        _messages.addAll(older);
        _hasMore = older.length >= 50;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _markRead() async {
    if (_messages.isEmpty) return;
    try {
      await ChatApi.markRead(widget.conversation.id, _messages.first.id);
    } catch (_) {
      // 静默失败.
    }
  }

  // ---------- WS ----------

  void _onWsEvent(Map<String, dynamic> e) {
    if (!mounted) return;
    final type = e['type'];
    final convId = e['conversation_id'];
    if (convId != widget.conversation.id) return;
    if (type == 'message') {
      final msg = ChatMessage.fromJson(e['message']);
      if (msg.id == 0) return;
      if (_messages.any((m) => m.id == msg.id)) return;
      setState(() => _messages.insert(0, msg));
      _markRead();
    } else if (type == 'reaction') {
      final mid = e['message_id'];
      final reactions = Reaction.parseList(e['reactions']);
      final idx = _messages.indexWhere((m) => m.id == mid);
      if (idx >= 0) {
        setState(() =>
            _messages[idx] = _messages[idx].copyWith(reactions: reactions));
      }
    }
  }

  // ---------- 发送 ----------

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final pending = _Pending(content: text, replyTo: _replyingTo);
    setState(() {
      _pending.insert(0, pending);
      _replyingTo = null;
    });
    _controller.clear();
    await _deliver(pending);
  }

  Future<void> _deliver(_Pending pending) async {
    try {
      final msg = await ChatApi.sendMessage(
        widget.conversation.id,
        pending.content,
        replyToId: pending.replyTo?.id,
      );
      if (!mounted) return;
      setState(() {
        _pending.remove(pending);
        if (!_messages.any((m) => m.id == msg.id)) _messages.insert(0, msg);
      });
      _markRead();
    } catch (_) {
      if (!mounted) return;
      setState(() => pending.state = _SendState.failed);
      _toast('发送失败, 点击重试');
    }
  }

  void _retry(_Pending pending) {
    setState(() => pending.state = _SendState.sending);
    _deliver(pending);
  }

  // ---------- 表态 ----------

  Future<void> _toggleReaction(ChatMessage msg, String emoji) async {
    try {
      final reactions = await ChatApi.toggleReaction(msg.id, emoji);
      if (!mounted) return;
      final idx = _messages.indexWhere((m) => m.id == msg.id);
      if (idx >= 0) {
        setState(
            () => _messages[idx] = _messages[idx].copyWith(reactions: reactions));
      }
    } catch (_) {
      _toast('操作失败');
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
        centerTitle: false,
        titleSpacing: 0,
        iconTheme: const IconThemeData(color: McColors.onSurface),
        title: Row(
          children: [
            _avatar(widget.conversation.displayName, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.conversation.displayName,
                    style:
                        McText.sans(size: 15, weight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_isGroup)
                    Text(
                      '${widget.conversation.memberCount} 位成员',
                      style: McText.sans(
                          size: 12, color: McColors.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _buildList()),
          _buildComposer(),
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
    if (_loadFailed) {
      return _emptyState('加载失败, 下拉重试', onRetry: _loadInitial);
    }
    if (_messages.isEmpty && _pending.isEmpty) {
      return _emptyState('还没有消息, 说点什么吧');
    }

    final loaderCount = (_hasMore || _loadingMore) ? 1 : 0;
    final total = _pending.length + _messages.length + loaderCount;

    return RefreshIndicator(
      onRefresh: _loadInitial,
      color: McColors.primarySoft,
      backgroundColor: McColors.surfaceContainerHigh,
      child: ListView.builder(
        controller: _scroll,
        reverse: true,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        itemCount: total,
        itemBuilder: (context, index) {
          if (index < _pending.length) {
            return _buildPending(_pending[index]);
          }
          final mi = index - _pending.length;
          if (mi < _messages.length) {
            return _buildMessage(mi);
          }
          // 顶部加载指示.
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: McColors.onSurfaceVariant),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMessage(int index) {
    final msg = _messages[index];
    final mine = msg.senderId == _myId;

    // 5 分钟间隔时间分隔条 (与上一条更新消息比较, index-1 即更新的).
    Widget? divider;
    final created = msg.createdAt;
    if (index > 0) {
      final newer = _messages[index - 1];
      final b = newer.createdAt;
      if (created != null && b != null &&
          b.difference(created).inMinutes.abs() >= 5) {
        divider = _timeDivider(created);
      }
    } else if (created != null) {
      divider = _timeDivider(created);
    }

    return Column(
      children: [
        ?divider,
        _bubbleRow(msg, mine),
      ],
    );
  }

  Widget _buildPending(_Pending p) {
    final bubble = Container(
      constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: McColors.primaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: McColors.primaryContainer.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (p.replyTo != null) _quoteBlock(p.replyTo!.senderName, p.replyTo!.content),
          _contentText(p.content, mine: true),
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (p.state == _SendState.sending)
                const Icon(Icons.schedule, size: 12,
                    color: McColors.onSurfaceVariant)
              else
                const Icon(Icons.error_outline,
                    size: 12, color: McColors.bear),
              const SizedBox(width: 4),
              Text(
                p.state == _SendState.sending ? '发送中' : '失败 · 点我重试',
                style: McText.sans(
                    size: 12,
                    color: p.state == _SendState.sending
                        ? McColors.onSurfaceVariant
                        : McColors.bear),
              ),
            ],
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: p.state == _SendState.failed ? () => _retry(p) : null,
            child: bubble,
          ),
        ],
      ),
    );
  }

  Widget _bubbleRow(ChatMessage msg, bool mine) {
    final bubble = GestureDetector(
      onLongPress: () => _showActions(msg),
      child: Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: mine
              ? McColors.primaryContainer.withValues(alpha: 0.28)
              : McColors.surfaceContainer,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(mine ? 12 : 3),
            bottomRight: Radius.circular(mine ? 3 : 12),
          ),
          border: Border.all(
            color: mine
                ? McColors.primaryContainer.withValues(alpha: 0.35)
                : McColors.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (msg.replyTo != null)
              _quoteBlock(msg.replyTo!.senderName, msg.replyTo!.content),
            _contentText(msg.content, mine: mine),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine) ...[
            _avatar(msg.senderName, size: 30),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (_isGroup && !mine)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3, left: 2),
                    child: Text(
                      msg.senderName,
                      style: McText.sans(
                          size: 12, color: McColors.onSurfaceVariant),
                    ),
                  ),
                bubble,
                if (msg.reactions.isNotEmpty) _reactionRow(msg, mine),
              ],
            ),
          ),
          if (mine) ...[
            const SizedBox(width: 8),
            _avatar(msg.senderName.isEmpty ? '我' : msg.senderName, size: 30),
          ],
        ],
      ),
    );
  }

  Widget _quoteBlock(String sender, String content) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLowest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: const Border(
          left: BorderSide(color: McColors.secondary, width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(sender,
              style: McText.sans(
                  size: 12,
                  weight: FontWeight.w600,
                  color: McColors.secondary)),
          const SizedBox(height: 1),
          Text(
            content,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: McText.sans(size: 12, color: McColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// 正文 + 币种标签 ($BTC 等) 渲染为可点击 chip.
  Widget _contentText(String content, {required bool mine}) {
    final matches = _coinTag.allMatches(content).toList();
    if (matches.isEmpty) {
      return Text(content,
          style: McText.sans(size: 14, height: 1.4, color: McColors.onSurface));
    }
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in matches) {
      if (m.start > last) {
        spans.add(TextSpan(text: content.substring(last, m.start)));
      }
      final tag = m.group(1)!.toUpperCase();
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: GestureDetector(
            onTap: () => _openCoin(tag),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: McColors.secondary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: McColors.secondary.withValues(alpha: 0.35)),
              ),
              child: Text(
                '\$$tag',
                style: McText.mono(
                    size: 12,
                    weight: FontWeight.w700,
                    color: McColors.secondary),
              ),
            ),
          ),
        ),
      ));
      last = m.end;
    }
    if (last < content.length) {
      spans.add(TextSpan(text: content.substring(last)));
    }
    return Text.rich(
      TextSpan(
        style: McText.sans(size: 14, height: 1.4, color: McColors.onSurface),
        children: spans,
      ),
    );
  }

  void _openCoin(String symbol) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MarketDetailPage(
          instId: '$symbol-USDT-SWAP',
          symbol: symbol,
        ),
      ),
    );
  }

  Widget _reactionRow(ChatMessage msg, bool mine) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 5,
        runSpacing: 4,
        alignment: mine ? WrapAlignment.end : WrapAlignment.start,
        children: [
          for (final r in msg.reactions)
            GestureDetector(
              onTap: () => _toggleReaction(msg, r.emoji),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: r.mine
                      ? McColors.primaryContainer.withValues(alpha: 0.3)
                      : McColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: r.mine
                        ? McColors.primarySoft.withValues(alpha: 0.6)
                        : McColors.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  '${r.emoji} ${r.count}',
                  style: McText.sans(
                    size: 12,
                    weight: r.mine ? FontWeight.w700 : FontWeight.w400,
                    color: r.mine
                        ? McColors.primarySoft
                        : McColors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _timeDivider(DateTime dt) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Text(
          chatBubbleTime(dt),
          style: McText.mono(size: 12, color: McColors.onSurfaceVariant),
        ),
      ),
    );
  }

  void _showActions(ChatMessage msg) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: McColors.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              // 表情表态行.
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final e in _emojis)
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          _toggleReaction(msg, e);
                        },
                        child: Text(e, style: const TextStyle(fontSize: 26)),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              _actionTile(ctx, Icons.reply, '回复', () {
                setState(() => _replyingTo = msg);
                _focus.requestFocus();
              }),
              _actionTile(ctx, Icons.copy, '复制', () {
                Clipboard.setData(ClipboardData(text: msg.content));
                _toast('已复制');
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _actionTile(
      BuildContext ctx, IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, size: 20, color: McColors.onSurfaceVariant),
      title: Text(label, style: McText.sans(size: 14)),
      onTap: () {
        Navigator.pop(ctx);
        onTap();
      },
    );
  }

  Widget _buildComposer() {
    return Container(
      decoration: BoxDecoration(
        color: McColors.surface,
        border: Border(
          top: BorderSide(color: McColors.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyingTo != null) _replyBar(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: McColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color:
                                McColors.outlineVariant.withValues(alpha: 0.6)),
                      ),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        minLines: 1,
                        maxLines: 5,
                        style: McText.sans(size: 14),
                        decoration: InputDecoration(
                          hintText: '发消息...',
                          hintStyle: McText.sans(
                              size: 14, color: McColors.onSurfaceVariant),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _send,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: McColors.primaryContainer,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: McColors.primaryContainer
                                .withValues(alpha: 0.4),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.send_rounded,
                          size: 20, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _replyBar() {
    final r = _replyingTo!;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 0),
      child: Row(
        children: [
          const Icon(Icons.reply, size: 16, color: McColors.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '回复 ${r.senderName}',
                  style: McText.sans(
                      size: 12,
                      weight: FontWeight.w600,
                      color: McColors.secondary),
                ),
                Text(
                  r.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: McText.sans(
                      size: 12, color: McColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close,
                size: 18, color: McColors.onSurfaceVariant),
            onPressed: () => setState(() => _replyingTo = null),
          ),
        ],
      ),
    );
  }

  Widget _avatar(String name, {double size = 32}) {
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: McColors.primarySoft.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border:
            Border.all(color: McColors.primarySoft.withValues(alpha: 0.3)),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: McText.display(
            size: size * 0.42,
            weight: FontWeight.w700,
            color: McColors.primarySoft),
      ),
    );
  }

  Widget _emptyState(String text, {VoidCallback? onRetry}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.chat_bubble_outline,
              size: 40, color: McColors.outline),
          const SizedBox(height: 12),
          Text(text,
              style:
                  McText.sans(size: 13, color: McColors.onSurfaceVariant)),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onRetry,
              child: const McPill('重新加载', color: McColors.primarySoft),
            ),
          ],
        ],
      ),
    );
  }
}

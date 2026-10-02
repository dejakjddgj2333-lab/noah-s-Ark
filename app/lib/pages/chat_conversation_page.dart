import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/auth.dart';
import '../services/call_service.dart';
import '../services/chat_api.dart';
import '../services/chat_db.dart';
import '../services/chat_ws.dart';
import 'group_info_page.dart';
import 'market_detail_page.dart';
import 'media_viewer_page.dart';

/// 聊天房间: 本地消息秒开 + 服务器合并 (微信式, 服务器仅relay),
/// 倒序消息流, 向上翻页, 回复 / 表情表态 / 复制, 币种标签跳转行情,
/// 图片/语音/视频媒体消息, 乐观发送 (pending → 成功/失败重试),
/// WS 实时追加 + 已读上报. 群聊右上角进群信息页.
class ChatConversationPage extends StatefulWidget {
  const ChatConversationPage({super.key, required this.conversation});

  final Conversation conversation;

  @override
  State<ChatConversationPage> createState() => _ChatConversationPageState();
}

enum _SendState { sending, failed }

/// 本地乐观消息 (未确认). 支持文本与媒体.
class _Pending {
  _Pending({
    required this.content,
    this.msgType = 'text',
    this.localBytes,
    this.filename,
    this.duration,
    this.replyTo,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String content;
  final String msgType; // text|image|audio|video
  final Uint8List? localBytes; // 媒体本地预览 + 上传源
  final String? filename;
  final int? duration;
  final ChatMessage? replyTo;
  _SendState state = _SendState.sending;
  final DateTime createdAt;

  bool get isMedia => msgType != 'text';
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
  int _peerReadId = 0; // 私聊对方已读游标 (自己气泡 已读/未读 判定)

  // 媒体 (按需创建: web 不碰原生插件通道; dispose 只清已创建的)
  final _picker = ImagePicker();
  AudioRecorder? _recorderInst;
  AudioRecorder get _recorder => _recorderInst ??= AudioRecorder();
  AudioPlayer? _playerInst;
  AudioPlayer get _player => _playerInst ??= AudioPlayer();
  int? _playingId; // 正在播放的语音消息 id
  bool _voiceMode = false; // 语音输入模式 (替换输入框为 按住说话)
  bool _recording = false;
  bool _recordCancel = false; // 上滑超过阈值 → 松开取消
  double? _recordStartDy; // 长按起始 Y, 用于上滑取消检测
  bool _attachOpen = false; // + 附件面板
  String? _recordPath;
  DateTime? _recordStart;
  StreamSubscription<PlayerState>? _playerSub;

  static final _coinTag = RegExp(r'\$([A-Za-z0-9]{2,10})');
  static const _emojis = ['👍', '❤️', '🔥', '😂', '😮', '😢'];

  int get _myId => AuthStore.instance.userId ?? -1;
  bool get _isGroup => widget.conversation.isGroup;

  @override
  void initState() {
    super.initState();
    ChatWs.instance.connect();
    _loadInitial();
    if (!_isGroup) _loadPeerRead();
    _wsSub = ChatWs.instance.events.listen(_onWsEvent);
    _scroll.addListener(_maybeLoadMore);
    // 播放结束/停止后复位语音图标.
    _playerSub = _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      if (s == PlayerState.completed || s == PlayerState.stopped) {
        setState(() => _playingId = null);
      }
    });
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _playerSub?.cancel();
    _playerInst?.dispose();
    if (_recording) _recorderInst?.stop();
    _recorderInst?.dispose();
    _scroll.dispose();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ---------- 加载 (本地优先 + 服务器合并) ----------

  Future<void> _loadInitial() async {
    // 1. 本地消息立即渲染 (网络前).
    final local = ChatDb.messagesFor(widget.conversation.id);
    if (local.isNotEmpty) {
      final localMsgs = [
        for (final m in local) ChatMessage.fromJson(m),
      ]..sort((a, b) => b.id.compareTo(a.id)); // 最新在前
      if (mounted) {
        setState(() {
          _messages
            ..clear()
            ..addAll(localMsgs);
          _loading = false;
        });
      }
    }
    // 2. 拉服务器最新, 合并去重 (保留本地独有的, 服务器retention后可能更少).
    try {
      final server = await ChatApi.messages(widget.conversation.id);
      await ChatDb.saveMessages(
          widget.conversation.id, server.map((m) => m.toMap()));
      if (!mounted) return;
      setState(() {
        final byId = {for (final m in _messages) m.id: m};
        for (final m in server) {
          if (m.id != 0) byId[m.id] = m; // 服务器覆盖 (reactions 等最新)
        }
        final merged = byId.values.where((m) => m.id != 0).toList()
          ..sort((a, b) => b.id.compareTo(a.id));
        _messages
          ..clear()
          ..addAll(merged);
        _hasMore = server.length >= 50;
        _loading = false;
        _loadFailed = false;
      });
      _markRead();
      _jumpToBottom(); // 初始定位到最新消息
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = _messages.isEmpty; // 有本地缓存则不算失败
      });
    }
  }

  void _maybeLoadMore() {
    // 正序列表: 滚动到顶部 (小偏移) 即最旧消息处. 内容不足一屏时不触发 (maxScrollExtent=0).
    if (!_hasMore || _loadingMore || _loading) return;
    if (_scroll.position.maxScrollExtent > 0 &&
        _scroll.position.pixels <= 80) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_messages.isEmpty) return;
    setState(() => _loadingMore = true);
    // 记录旧滚动位置, 顶部插入后补偿保持视觉不动.
    final oldPixels = _scroll.position.pixels;
    final oldMax = _scroll.position.maxScrollExtent;
    try {
      final older = await ChatApi.messages(widget.conversation.id,
          beforeId: _messages.last.id);
      await ChatDb.saveMessages(
          widget.conversation.id, older.map((m) => m.toMap()));
      if (!mounted) return;
      setState(() {
        final existing = {for (final m in _messages) m.id};
        final fresh =
            older.where((m) => m.id != 0 && !existing.contains(m.id)).toList();
        _messages.addAll(fresh);
        _hasMore = older.length >= 50;
        _loadingMore = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final delta = _scroll.position.maxScrollExtent - oldMax;
        if (delta > 0) _scroll.jumpTo(oldPixels + delta);
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
      final stick = _nearBottom; // 插入前判定是否贴底
      setState(() => _messages.insert(0, msg));
      if (stick) _jumpToBottom(); // 贴底才跟滚, 翻历史时不拽动
      ChatDb.saveMessage(widget.conversation.id, msg.toMap());
      _markRead();
    } else if (type == 'reaction') {
      final mid = e['message_id'];
      final reactions = Reaction.parseList(e['reactions']);
      final idx = _messages.indexWhere((m) => m.id == mid);
      if (idx >= 0) {
        setState(() =>
            _messages[idx] = _messages[idx].copyWith(reactions: reactions));
      }
    } else if (type == 'read') {
      // 对方已读推进游标 → 自己气泡回执实时翻 已读.
      final mid = e['message_id'];
      if (mid is int && mid > _peerReadId) {
        setState(() => _peerReadId = mid);
      }
    }
  }

  /// 私聊对方已读游标 (静默, 失败按 0 全未读).
  Future<void> _loadPeerRead() async {
    try {
      final v = await ChatApi.peerReadState(widget.conversation.id);
      if (v != null && mounted) setState(() => _peerReadId = v);
    } catch (_) {/* 静默 */}
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
    _jumpToBottom(); // 自己发的乐观气泡顶到可视区
    await _deliver(pending);
  }

  /// 统一投递: 文本直接发, 媒体先上传再发.
  Future<void> _deliver(_Pending pending) async {
    try {
      ChatMessage msg;
      if (pending.isMedia) {
        final url =
            await ChatApi.uploadFile(pending.localBytes!, _uploadName(pending));
        msg = await ChatApi.sendMessage(
          widget.conversation.id,
          pending.content,
          replyToId: pending.replyTo?.id,
          msgType: pending.msgType,
          fileUrl: url,
          duration: pending.duration,
        );
      } else {
        msg = await ChatApi.sendMessage(
          widget.conversation.id,
          pending.content,
          replyToId: pending.replyTo?.id,
        );
      }
      if (!mounted) return;
      setState(() {
        _pending.remove(pending);
        if (!_messages.any((m) => m.id == msg.id)) _messages.insert(0, msg);
      });
      ChatDb.saveMessage(widget.conversation.id, msg.toMap());
      _markRead();
    } catch (_) {
      if (!mounted) return;
      setState(() => pending.state = _SendState.failed);
      _toast('发送失败, 点击重试');
    }
  }

  String _uploadName(_Pending p) {
    final n = p.filename;
    if (n != null && n.contains('.')) return n;
    final ext = switch (p.msgType) {
      'image' => 'jpg',
      'video' => 'mp4',
      'audio' => 'm4a',
      _ => 'bin',
    };
    return 'file.$ext';
  }

  void _retry(_Pending pending) {
    setState(() => pending.state = _SendState.sending);
    _deliver(pending);
  }

  // ---------- 媒体选择 ----------

  Future<void> _pickImages() async {
    _closeAttach();
    try {
      final files =
          await _picker.pickMultiImage(imageQuality: 70, maxWidth: 1600);
      for (final f in files) {
        await _sendMedia(f, 'image');
      }
    } catch (_) {
      _toast('选择图片失败');
    }
  }

  Future<void> _pickCamera() async {
    _closeAttach();
    try {
      final f = await _picker.pickImage(
          source: ImageSource.camera, imageQuality: 70, maxWidth: 1600);
      if (f != null) await _sendMedia(f, 'image');
    } catch (_) {
      _toast('拍摄失败');
    }
  }

  Future<void> _pickVideo() async {
    _closeAttach();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: McColors.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: McColors.onSurfaceVariant),
              title: Text('从相册选择', style: McText.sans(size: 14)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined,
                  color: McColors.onSurfaceVariant),
              title: Text('拍摄', style: McText.sans(size: 14)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final f = await _picker.pickVideo(source: source);
      if (f != null) await _sendMedia(f, 'video');
    } catch (_) {
      _toast('选择视频失败');
    }
  }

  /// 选/拍好媒体 → 乐观气泡 → 上传 → 发送.
  Future<void> _sendMedia(XFile file, String msgType, {int? duration}) async {
    try {
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final pending = _Pending(
        content: '',
        msgType: msgType,
        localBytes: bytes,
        filename: file.name,
        duration: duration,
        replyTo: _replyingTo,
      );
      setState(() {
        _pending.insert(0, pending);
        _replyingTo = null;
      });
      await _deliver(pending);
    } catch (_) {
      _toast('发送失败');
    }
  }

  // ---------- 语音 (按住说话, Web 不支持隐藏) ----------

  Future<void> _startRecord() async {
    if (kIsWeb) {
      _toast('网页版暂不支持语音, 请用 App');
      return;
    }
    if (_recording) return;
    try {
      if (!await _recorder.hasPermission()) {
        _toast('需要麦克风权限');
        return;
      }
      final dir = await getTemporaryDirectory();
      _recordPath =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: _recordPath!);
      _recordStart = DateTime.now();
      if (mounted) setState(() => _recording = true);
    } catch (_) {
      _toast('录音失败');
    }
  }

  Future<void> _stopRecord({bool cancel = false}) async {
    if (!_recording) return;
    try {
      final path = await _recorder.stop();
      final started = _recordStart;
      final dur = started == null
          ? 1
          : DateTime.now().difference(started).inSeconds.clamp(1, 3600);
      if (mounted) setState(() => _recording = false);
      if (cancel || path == null) return;
      final bytes = await XFile(path).readAsBytes();
      if (!mounted) return;
      final pending = _Pending(
        content: '',
        msgType: 'audio',
        localBytes: bytes,
        filename: 'voice.m4a',
        duration: dur,
      );
      setState(() => _pending.insert(0, pending));
      await _deliver(pending);
    } catch (_) {
      if (mounted) setState(() => _recording = false);
    }
  }

  // ---------- 语音播放 ----------

  Future<void> _toggleAudio(ChatMessage msg) async {
    final url = msg.mediaUrl;
    if (url == null) return;
    if (_playingId == msg.id) {
      await _player.stop();
      if (mounted) setState(() => _playingId = null);
      return;
    }
    try {
      await _player.stop(); // 新播放前停掉旧的
      await _player.play(UrlSource(url));
      if (mounted) setState(() => _playingId = msg.id);
    } catch (_) {
      _toast('播放失败');
    }
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

  void _closeAttach() {
    if (_attachOpen) setState(() => _attachOpen = false);
  }

  /// 发起 1:1 语音通话 (私聊). 断线/占用由 CallService toast;
  /// 弹页由 main.dart 监听 CallService 阶段统一处理, 这里不再 push (否则双页).
  Future<void> _startVoiceCall() async {
    final other = widget.conversation.otherUser;
    if (other == null) return;
    await CallService.instance.startCall(
      other.id,
      other.username,
      conversationId: widget.conversation.id,
    );
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
            _avatar(widget.conversation.displayName, size: 32,
                url: widget.conversation.otherUser?.avatarUrl),
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
        actions: [
          if (!_isGroup && widget.conversation.otherUser != null)
            IconButton(
              icon: const Icon(Icons.call_outlined, color: McColors.onSurface),
              onPressed: _startVoiceCall,
            ),
          if (_isGroup)
            IconButton(
              icon: const Icon(Icons.more_horiz, color: McColors.onSurface),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      GroupInfoPage(conversation: widget.conversation),
                ),
              ),
            ),
        ],
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
    final total = loaderCount + _messages.length + _pending.length;

    return RefreshIndicator(
      onRefresh: _loadInitial,
      color: McColors.primarySoft,
      backgroundColor: McColors.surfaceContainerHigh,
      child: ListView.builder(
        controller: _scroll,
        // 正序展示: 内容从顶部开始排 (旧->新), 初始/新消息自动滚到底.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        itemCount: total,
        itemBuilder: (context, index) {
          // 顶部加载指示.
          if (loaderCount == 1 && index == 0) {
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
          }
          final mi0 = index - loaderCount;
          if (mi0 < _messages.length) {
            // _messages 内部最新在前, 展示翻转为旧->新.
            return _buildMessage(_messages.length - 1 - mi0);
          }
          return _buildPending(_pending[mi0 - _messages.length]);
        },
      ),
    );
  }

  /// 滚到底部 (等帧结束列表布局完).
  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  bool get _nearBottom =>
      !_scroll.hasClients ||
      _scroll.position.maxScrollExtent - _scroll.position.pixels < 240;

  Widget _buildMessage(int index) {
    final msg = _messages[index];
    final mine = msg.senderId == _myId;

    // 5 分钟间隔时间分隔条 (与更旧一条比较, _messages 最新在前, index+1 即更旧的).
    Widget? divider;
    final created = msg.createdAt;
    if (index < _messages.length - 1) {
      final older = _messages[index + 1];
      final b = older.createdAt;
      if (created != null && b != null &&
          created.difference(b).inMinutes.abs() >= 5) {
        divider = _timeDivider(created);
      }
    } else if (created != null) {
      divider = _timeDivider(created); // 最旧一条总带时间
    }

    return Column(
      children: [
        ?divider,
        _bubbleRow(msg, mine),
      ],
    );
  }

  // ---------- 乐观消息 ----------

  Widget _buildPending(_Pending p) {
    final failed = p.state == _SendState.failed;
    final status = Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (failed)
            const Icon(Icons.error_outline, size: 12, color: McColors.bear)
          else
            const Icon(Icons.schedule,
                size: 12, color: McColors.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            failed ? '失败 · 点我重试' : '发送中',
            style: McText.sans(
                size: 12,
                color: failed ? McColors.bear : McColors.onSurfaceVariant),
          ),
        ],
      ),
    );

    Widget body;
    if (p.isMedia) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _pendingMedia(p),
          status,
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (p.replyTo != null)
            _quoteBlock(p.replyTo!.senderName, p.replyTo!.content),
          _contentText(p.content, mine: true),
          status,
        ],
      );
    }

    final bubble = Container(
      constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72),
      padding: p.isMedia && p.msgType != 'audio'
          ? const EdgeInsets.all(3)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: McColors.primaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: McColors.primaryContainer.withValues(alpha: 0.3)),
      ),
      child: body,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: failed ? () => _retry(p) : null,
            child: bubble,
          ),
        ],
      ),
    );
  }

  /// 乐观媒体预览 (本地字节).
  Widget _pendingMedia(_Pending p) {
    switch (p.msgType) {
      case 'image':
        return ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200, maxHeight: 200),
            child: p.localBytes != null
                ? Image.memory(p.localBytes!, fit: BoxFit.cover)
                : _mediaPlaceholder(Icons.image_outlined),
          ),
        );
      case 'video':
        return _videoThumb(null);
      case 'audio':
        return _audioContent(p.duration, false);
      default:
        return _mediaPlaceholder(Icons.insert_drive_file_outlined);
    }
  }

  // ---------- 消息气泡 ----------

  Widget _bubbleRow(ChatMessage msg, bool mine) {
    final media = msg.isMedia && msg.msgType != 'audio';
    final bubble = GestureDetector(
      onLongPress: () => _showActions(msg),
      child: Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72),
        padding: media
            ? const EdgeInsets.all(3)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
            _bubbleContent(msg, mine),
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
            _avatar(msg.senderName, size: 30, url: msg.senderAvatar),
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
                // 私聊自己气泡: 已读/未读 标记.
                if (mine && !_isGroup)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 2),
                    child: Text(
                      msg.id <= _peerReadId ? '已读' : '未读',
                      style: McText.sans(
                        size: 12,
                        color: msg.id <= _peerReadId
                            ? McColors.primarySoft
                            : McColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (msg.reactions.isNotEmpty) _reactionRow(msg, mine),
              ],
            ),
          ),
          if (mine) ...[
            const SizedBox(width: 8),
            _avatar(msg.senderName.isEmpty ? '我' : msg.senderName,
                size: 30, url: AuthStore.instance.avatarUrl),
          ],
        ],
      ),
    );
  }

  /// 气泡正文: 按 msg_type 渲染 文本/图片/视频/语音.
  Widget _bubbleContent(ChatMessage msg, bool mine) {
    switch (msg.msgType) {
      case 'image':
        return _imageContent(msg);
      case 'video':
        return GestureDetector(
          onTap: () => _openVideo(msg),
          child: _videoThumb(msg.duration),
        );
      case 'audio':
        return GestureDetector(
          onTap: () => _toggleAudio(msg),
          child: _audioContent(msg.duration, _playingId == msg.id,
              mine: mine),
        );
      default:
        return _contentText(msg.content, mine: mine);
    }
  }

  Widget _imageContent(ChatMessage msg) {
    final url = msg.mediaUrl;
    return GestureDetector(
      onTap: url == null ? null : () => _openImage(url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200, maxHeight: 200),
          child: url == null
              ? _mediaPlaceholder(Icons.image_outlined)
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      _mediaPlaceholder(Icons.broken_image_outlined),
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return _mediaPlaceholder(null, loading: true);
                  },
                ),
        ),
      ),
    );
  }

  /// 视频缩略: 深色盒 + 播放键 (+ 时长).
  Widget _videoThumb(int? duration) {
    return Container(
      width: 200,
      height: 120,
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(9),
        border:
            Border.all(color: McColors.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(Icons.play_circle_outline,
              size: 44, color: Colors.white70),
          if (duration != null)
            Positioned(
              right: 6,
              bottom: 4,
              child: Text(
                _fmtDuration(duration),
                style: McText.mono(size: 12, color: Colors.white70),
              ),
            ),
        ],
      ),
    );
  }

  /// 语音气泡: 播放/暂停图标 + 时长.
  Widget _audioContent(int? duration, bool playing, {bool mine = true}) {
    // 宽度随时长略增 (1s→80, 60s→180).
    final sec = (duration ?? 1).clamp(1, 60);
    final width = 80.0 + (sec - 1) * (100.0 / 59.0);
    return SizedBox(
      width: width,
      child: Row(
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Icon(
            playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
            size: 26,
            color: mine ? McColors.primarySoft : McColors.secondary,
          ),
          const SizedBox(width: 6),
          Text(
            '$sec″',
            style: McText.sans(size: 14, color: McColors.onSurface),
          ),
        ],
      ),
    );
  }

  Widget _mediaPlaceholder(IconData? icon, {bool loading = false}) {
    return Container(
      width: 200,
      height: 140,
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: McColors.primarySoft),
            )
          : Icon(icon ?? Icons.image_outlined,
              size: 34, color: McColors.outline),
    );
  }

  void _openImage(String url) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ImageViewerPage(url: url)),
    );
  }

  void _openVideo(ChatMessage msg) {
    final url = msg.mediaUrl;
    if (url == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => VideoPlayerPage(url: url)),
    );
  }

  static String _fmtDuration(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
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
              // 媒体消息无可复制文本, 跳过复制项.
              if (msg.msgType == 'text')
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

  // ---------- 输入区 ----------

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
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 语音/键盘切换 (web 不支持语音, 隐藏).
                  if (!kIsWeb) ...[
                    _roundIconBtn(
                      _voiceMode ? Icons.keyboard : Icons.mic_none,
                      () {
                        setState(() {
                          _voiceMode = !_voiceMode;
                          _attachOpen = false;
                        });
                        if (!_voiceMode) _focus.requestFocus();
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: _voiceMode ? _holdToTalk() : _textInput()),
                  const SizedBox(width: 8),
                  // + 附件面板. 发送走键盘 send 键 / web 回车, 无独立发送钮.
                  _roundIconBtn(
                    _attachOpen ? Icons.close : Icons.add_circle_outline,
                    () {
                      setState(() {
                        _attachOpen = !_attachOpen;
                        if (_attachOpen) {
                          _voiceMode = false;
                          _focus.unfocus();
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
            if (_attachOpen) _attachPanel(),
          ],
        ),
      ),
    );
  }

  Widget _roundIconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: McColors.surfaceContainer,
          shape: BoxShape.circle,
          border: Border.all(
              color: McColors.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Icon(icon, size: 20, color: McColors.onSurface),
      ),
    );
  }

  Widget _textInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: McColors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: McColors.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        minLines: 1,
        maxLines: 5,
        // 手机键盘显示发送键; web/桌面回车发送 (换行 Shift+Enter).
        textInputAction: TextInputAction.send,
        style: McText.sans(size: 14),
        decoration: InputDecoration(
          hintText: '发消息...',
          hintStyle:
              McText.sans(size: 14, color: McColors.onSurfaceVariant),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
        onSubmitted: (_) => _send(),
      ),
    );
  }

  /// 按住说话 (语音录制). 上滑 >80px 取消.
  Widget _holdToTalk() {
    return GestureDetector(
      onLongPressStart: (d) {
        _recordStartDy = d.globalPosition.dy;
        _recordCancel = false;
        _startRecord();
      },
      onLongPressMoveUpdate: (d) {
        if (!_recording || _recordStartDy == null) return;
        final cancel = _recordStartDy! - d.globalPosition.dy > 80;
        if (cancel != _recordCancel) {
          setState(() => _recordCancel = cancel);
        }
      },
      onLongPressEnd: (_) {
        final cancel = _recordCancel;
        _recordCancel = false;
        _recordStartDy = null;
        _stopRecord(cancel: cancel);
      },
      onLongPressCancel: () {
        _recordCancel = false;
        _recordStartDy = null;
        _stopRecord(cancel: true);
      },
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: _recording
              ? (_recordCancel
                  ? McColors.bear.withValues(alpha: 0.15)
                  : McColors.primaryContainer.withValues(alpha: 0.3))
              : McColors.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _recording
                ? (_recordCancel
                    ? McColors.bear
                    : McColors.primaryContainer)
                : McColors.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          _recording
              ? (_recordCancel ? '松开手指, 取消发送' : '松开发送 · 上滑取消')
              : '按住 说话',
          style: McText.sans(
            size: 14,
            weight: FontWeight.w600,
            color: _recording
                ? (_recordCancel ? McColors.bear : McColors.primarySoft)
                : McColors.onSurface,
          ),
        ),
      ),
    );
  }

  /// + 附件面板 (微信式 grid): 相册 / 拍摄 / 视频.
  Widget _attachPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          _attachItem(Icons.photo_library_outlined, '相册', _pickImages),
          const SizedBox(width: 32),
          _attachItem(Icons.photo_camera_outlined, '拍摄', _pickCamera),
          const SizedBox(width: 32),
          _attachItem(Icons.videocam_outlined, '视频', _pickVideo),
        ],
      ),
    );
  }

  Widget _attachItem(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: McColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: McColors.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Icon(icon, size: 26, color: McColors.primarySoft),
          ),
          const SizedBox(height: 6),
          Text(label,
              style:
                  McText.sans(size: 12, color: McColors.onSurfaceVariant)),
        ],
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
                  r.msgType == 'text' ? r.content : '[${_mediaLabel(r.msgType)}]',
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

  static String _mediaLabel(String msgType) => switch (msgType) {
        'image' => '图片',
        'video' => '视频',
        'audio' => '语音',
        _ => '消息',
      };

  Widget _avatar(String name, {double size = 32, String? url}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border:
            Border.all(color: McColors.primarySoft.withValues(alpha: 0.3)),
      ),
      child: McAvatar(name: name, url: url, size: size, radius: size / 2),
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

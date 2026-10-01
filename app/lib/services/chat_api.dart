import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api.dart';
import 'auth.dart';

/// 聊天 REST 客户端 + 数据模型. 全部接口前缀 /api/chat, 需 Bearer token.
/// 解析容错: 字段缺失/类型异常一律回退默认值, 不抛给 UI.
class ChatApi {
  ChatApi._();

  static const _prefix = '/api/chat';

  /// 全局未读总数 (底部导航角标), 会话列表加载/新消息事件时更新.
  static final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  static String? get _token => AuthStore.instance.token;

  static void _syncUnread(List<Conversation> list) {
    var sum = 0;
    for (final c in list) {
      sum += c.unreadCount;
    }
    unreadCount.value = sum;
  }

  // ---------- 用户 / 好友 ----------

  /// 搜索用户. relation: self|friend|outgoing|incoming|none.
  static Future<List<ChatUser>> searchUsers(String query) async {
    final q = Uri.encodeQueryComponent(query);
    final raw = await McApi.getList('$_prefix/users/search?q=$q', token: _token);
    return [for (final e in raw) ChatUser.fromJson(e)];
  }

  static Future<void> sendFriendRequest(int toUserId) =>
      McApi.post('$_prefix/friends/request', {'to_user_id': toUserId},
          token: _token);

  static Future<void> acceptFriend(int fromUserId) =>
      McApi.post('$_prefix/friends/accept', {'from_user_id': fromUserId},
          token: _token);

  static Future<void> rejectFriend(int fromUserId) =>
      McApi.post('$_prefix/friends/reject', {'from_user_id': fromUserId},
          token: _token);

  static Future<void> deleteFriend(int userId) =>
      McApi.del('$_prefix/friends/$userId', token: _token);

  static Future<List<ChatUser>> friends() async {
    final raw = await McApi.getList('$_prefix/friends', token: _token);
    return [for (final e in raw) ChatUser.fromJson(e)];
  }

  /// 待处理好友请求数 (聊天页新朋友图标 + 底部导航角标共用).
  static final ValueNotifier<int> friendRequestCount = ValueNotifier<int>(0);

  /// 好友请求: incoming + outgoing 两组. 顺带刷新请求角标.
  static Future<FriendRequests> friendRequests() async {
    final resp = await McApi.get('$_prefix/friends/requests', token: _token);
    final r = FriendRequests.fromJson(resp);
    friendRequestCount.value = r.incoming.length;
    return r;
  }

  // ---------- 会话 ----------

  static Future<Conversation> openDirect(int otherUserId) async {
    final resp = await McApi.post(
        '$_prefix/conversations/direct', {'other_user_id': otherUserId},
        token: _token);
    return Conversation.fromJson(resp);
  }

  static Future<Conversation> createGroup(
      String name, List<int> memberIds) async {
    final resp = await McApi.post('$_prefix/conversations/group',
        {'name': name, 'member_ids': memberIds},
        token: _token);
    return Conversation.fromJson(resp);
  }

  /// 会话列表 (最新在前). 顺带刷新全局未读角标.
  static Future<List<Conversation>> conversations() async {
    final raw = await McApi.getList('$_prefix/conversations', token: _token);
    final list = [for (final e in raw) Conversation.fromJson(e)];
    _syncUnread(list);
    return list;
  }

  /// 删除/退出会话 (direct: 隐藏; group: 退群). 204.
  static Future<void> deleteConversation(int id) =>
      McApi.del('$_prefix/conversations/$id', token: _token);

  /// 当前在线好友 id 集合 (经 WS 连接). 失败静默返回空集, 不影响列表渲染.
  static Future<Set<int>> friendsOnline() async {
    try {
      final resp = await McApi.get('$_prefix/friends/online', token: _token);
      final raw = resp['online_ids'];
      if (raw is! List) return const {};
      return {for (final e in raw) _toInt(e)};
    } catch (_) {
      return const {};
    }
  }

  // ---------- 消息 ----------

  /// 拉取历史消息 (最新在前). before_id 用于向上翻页.
  static Future<List<ChatMessage>> messages(int conversationId,
      {int? beforeId, int limit = 50}) async {
    final buf = StringBuffer('$_prefix/conversations/$conversationId/messages?limit=$limit');
    if (beforeId != null) buf.write('&before_id=$beforeId');
    final raw = await McApi.getList(buf.toString(), token: _token);
    return [for (final e in raw) ChatMessage.fromJson(e)];
  }

  static Future<ChatMessage> sendMessage(int conversationId, String content,
      {int? replyToId, String? msgType, String? fileUrl, int? duration}) async {
    final resp = await McApi.post(
        '$_prefix/conversations/$conversationId/messages',
        {
          'content': content,
          'reply_to_id': ?replyToId,
          'msg_type': ?msgType,
          'file_url': ?fileUrl,
          'duration': ?duration,
        },
        token: _token);
    return ChatMessage.fromJson(resp);
  }

  /// 上传文件 (图片/语音/视频). multipart 字段 'file', Bearer 鉴权.
  /// 返回相对路径 file_url (如 `/api/chat/files/<uuid>.jpg`), 加载时前缀 McApi.baseUrl.
  /// 全平台通用: 传字节而非路径, Web 无 File 也可用.
  static Future<String> uploadFile(Uint8List bytes, String filename) async {
    final req = http.MultipartRequest(
        'POST', Uri.parse('${McApi.baseUrl}$_prefix/files'));
    if (_token != null) req.headers['Authorization'] = 'Bearer $_token';
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await req.send().timeout(const Duration(seconds: 60));
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode >= 400) {
      String msg = '上传失败 (${streamed.statusCode})';
      try {
        final data = jsonDecode(body);
        final detail = data is Map ? data['detail'] : null;
        if (detail is String) msg = detail;
      } catch (_) {/* 用默认 */}
      throw ApiException(streamed.statusCode, msg);
    }
    final data = jsonDecode(body);
    final url = data is Map ? data['file_url'] : null;
    if (url is! String || url.isEmpty) {
      throw ApiException(streamed.statusCode, '上传响应缺少 file_url');
    }
    return url;
  }

  // ---------- 群管理 ----------

  /// 群成员列表 (群主在前). role: owner|member.
  static Future<List<GroupMember>> members(int conversationId) async {
    final raw =
        await McApi.getList('$_prefix/conversations/$conversationId/members',
            token: _token);
    return [for (final e in raw) GroupMember.fromJson(e)];
  }

  /// 群主重命名群.
  static Future<Conversation> renameConversation(
      int conversationId, String name) async {
    final resp = await McApi.put(
        '$_prefix/conversations/$conversationId', {'name': name},
        token: _token);
    return Conversation.fromJson(resp);
  }

  /// 群主移除成员. 204.
  static Future<void> removeMember(int conversationId, int userId) =>
      McApi.del('$_prefix/conversations/$conversationId/members/$userId',
          token: _token);

  /// 拉人进群: 任一成员可用. 返回最新 member_count.
  static Future<int> addGroupMember(int conversationId, int userId) async {
    final resp = await McApi.post(
        '$_prefix/conversations/$conversationId/members',
        {'user_id': userId},
        token: _token);
    return (resp['member_count'] as num?)?.toInt() ?? 0;
  }

  static Future<void> markRead(int conversationId, int messageId) =>
      McApi.post('$_prefix/conversations/$conversationId/read',
          {'message_id': messageId},
          token: _token);

  /// 表情表态 (toggle). 返回最新 reactions.
  static Future<List<Reaction>> toggleReaction(int messageId, String emoji) async {
    final resp = await McApi.post(
        '$_prefix/messages/$messageId/reactions', {'emoji': emoji},
        token: _token);
    return Reaction.parseList(resp['reactions']);
  }
}

/// 用户 (搜索结果 / 好友). relation 仅搜索接口返回.
class ChatUser {
  const ChatUser({
    required this.id,
    required this.username,
    this.relation = 'none',
  });

  final int id;
  final String username;
  final String relation; // self|friend|outgoing|incoming|none

  factory ChatUser.fromJson(dynamic raw) {
    final m = raw is Map ? raw : const <String, dynamic>{};
    return ChatUser(
      id: _toInt(m['id']),
      username: (m['username'] ?? '').toString(),
      relation: (m['relation'] ?? 'none').toString(),
    );
  }
}

/// 一条好友请求.
class FriendRequest {
  const FriendRequest({
    required this.id,
    required this.username,
    this.createdAt,
  });

  final int id;
  final String username;
  final DateTime? createdAt;

  factory FriendRequest.fromJson(dynamic raw) {
    final m = raw is Map ? raw : const <String, dynamic>{};
    return FriendRequest(
      id: _toInt(m['id']),
      username: (m['username'] ?? '').toString(),
      createdAt: parseServerTime(m['created_at']),
    );
  }
}

/// incoming + outgoing 好友请求集合.
class FriendRequests {
  const FriendRequests({required this.incoming, required this.outgoing});

  final List<FriendRequest> incoming;
  final List<FriendRequest> outgoing;

  int get pendingCount => incoming.length;

  factory FriendRequests.fromJson(dynamic raw) {
    final m = raw is Map ? raw : const <String, dynamic>{};
    List<FriendRequest> parse(dynamic v) =>
        v is List ? [for (final e in v) FriendRequest.fromJson(e)] : const [];
    return FriendRequests(
      incoming: parse(m['incoming']),
      outgoing: parse(m['outgoing']),
    );
  }
}

/// 会话 (列表项).
class Conversation {
  const Conversation({
    required this.id,
    required this.type,
    required this.name,
    required this.memberCount,
    this.otherUser,
    this.lastMessage,
    this.unreadCount = 0,
  });

  final int id;
  final String type; // 'direct' | 'group'
  final String name;
  final int memberCount;
  final ChatUser? otherUser; // direct 会话的对方
  final LastMessage? lastMessage;
  final int unreadCount;

  bool get isGroup => type == 'group';

  /// 显示名: 群用 name, 私聊优先对方用户名.
  String get displayName {
    if (isGroup) return name.isEmpty ? '群聊' : name;
    final other = otherUser?.username ?? '';
    if (other.isNotEmpty) return other;
    return name.isEmpty ? '私聊' : name;
  }

  Conversation copyWith({
    String? name,
    int? memberCount,
    LastMessage? lastMessage,
    int? unreadCount,
  }) =>
      Conversation(
        id: id,
        type: type,
        name: name ?? this.name,
        memberCount: memberCount ?? this.memberCount,
        otherUser: otherUser,
        lastMessage: lastMessage ?? this.lastMessage,
        unreadCount: unreadCount ?? this.unreadCount,
      );

  factory Conversation.fromJson(dynamic raw) {
    final m = raw is Map ? raw : const <String, dynamic>{};
    final other = m['other_user'];
    final last = m['last_message'];
    return Conversation(
      id: _toInt(m['id']),
      type: (m['type'] ?? 'direct').toString(),
      name: (m['name'] ?? '').toString(),
      memberCount: _toInt(m['member_count']),
      otherUser: other is Map ? ChatUser.fromJson(other) : null,
      lastMessage: last is Map ? LastMessage.fromJson(last) : null,
      unreadCount: _toInt(m['unread_count']),
    );
  }
}

/// 会话最后一条消息预览.
class LastMessage {
  const LastMessage({
    this.id = 0,
    required this.content,
    required this.senderName,
    this.msgType = 'text',
    this.createdAt,
    this.isMine = false,
    this.read,
  });

  /// 消息 id (WS read 事件按它比对回执).
  final int id;
  final String content;
  final String senderName;
  final String msgType; // text|image|audio|video
  final DateTime? createdAt;

  /// 是否我发送 (决定私聊预览是否显示已读回执).
  final bool isMine;

  /// 私聊且 isMine 时: 对方是否已读; 其他情况为 null.
  final bool? read;

  /// 预览文本: 媒体消息显示 [图片]/[视频]/[语音] 占位.
  String get previewText {
    if (msgType == 'text') return content;
    return switch (msgType) {
      'image' => '[图片]',
      'video' => '[视频]',
      'audio' => '[语音]',
      _ => content,
    };
  }

  LastMessage copyWith({bool? read}) => LastMessage(
        id: id,
        content: content,
        senderName: senderName,
        msgType: msgType,
        createdAt: createdAt,
        isMine: isMine,
        read: read ?? this.read,
      );

  factory LastMessage.fromJson(dynamic raw) {
    final m = raw is Map ? raw : const <String, dynamic>{};
    final readRaw = m['read'];
    return LastMessage(
      id: _toInt(m['id']),
      content: (m['content'] ?? '').toString(),
      senderName: (m['sender_name'] ?? '').toString(),
      msgType: (m['msg_type'] ?? 'text').toString(),
      createdAt: parseServerTime(m['created_at']),
      isMine: m['is_mine'] == true,
      read: readRaw is bool ? readRaw : null,
    );
  }
}

/// 一条聊天消息.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.content,
    this.msgType = 'text',
    this.fileUrl,
    this.duration,
    this.replyTo,
    this.createdAt,
    this.reactions = const [],
  });

  final int id;
  final int senderId;
  final String senderName;
  final String content;

  /// 消息类型: text|image|audio|video.
  final String msgType;

  /// 媒体相对路径 (image/audio/video 才有). 加载时前缀 McApi.baseUrl.
  final String? fileUrl;

  /// 音/视频时长 (秒).
  final int? duration;

  final ReplyRef? replyTo;
  final DateTime? createdAt;
  final List<Reaction> reactions;

  bool get isMedia => msgType != 'text' && fileUrl != null;

  /// 媒体完整 URL (相对 file_url + baseUrl).
  String? get mediaUrl =>
      fileUrl == null ? null : '${McApi.baseUrl}$fileUrl';

  ChatMessage copyWith({List<Reaction>? reactions}) => ChatMessage(
        id: id,
        senderId: senderId,
        senderName: senderName,
        content: content,
        msgType: msgType,
        fileUrl: fileUrl,
        duration: duration,
        replyTo: replyTo,
        createdAt: createdAt,
        reactions: reactions ?? this.reactions,
      );

  /// 序列化为与 fromJson 同构的 Map, 供本地存储 (ChatDb).
  Map<String, dynamic> toMap() => {
        'id': id,
        'sender': {'id': senderId, 'username': senderName},
        'content': content,
        'msg_type': msgType,
        if (fileUrl != null) 'file_url': fileUrl,
        if (duration != null) 'duration': duration,
        if (replyTo != null)
          'reply_to': {
            'id': replyTo!.id,
            'sender_name': replyTo!.senderName,
            'content': replyTo!.content,
          },
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
        'reactions': [
          for (final r in reactions)
            {'emoji': r.emoji, 'count': r.count, 'mine': r.mine},
        ],
      };

  factory ChatMessage.fromJson(dynamic raw) {
    final m = raw is Map ? raw : const <String, dynamic>{};
    final sender = m['sender'];
    final senderMap = sender is Map ? sender : const <String, dynamic>{};
    final reply = m['reply_to'];
    final dur = m['duration'];
    return ChatMessage(
      id: _toInt(m['id']),
      senderId: _toInt(senderMap['id']),
      senderName: (senderMap['username'] ?? '').toString(),
      content: (m['content'] ?? '').toString(),
      msgType: (m['msg_type'] ?? 'text').toString(),
      fileUrl: m['file_url']?.toString(),
      duration: dur == null ? null : _toInt(dur),
      replyTo: reply is Map ? ReplyRef.fromJson(reply) : null,
      createdAt: parseServerTime(m['created_at']),
      reactions: Reaction.parseList(m['reactions']),
    );
  }
}

/// 群成员.
class GroupMember {
  const GroupMember({
    required this.id,
    required this.username,
    this.role = 'member',
  });

  final int id;
  final String username;
  final String role; // owner|member

  bool get isOwner => role == 'owner';

  factory GroupMember.fromJson(dynamic raw) {
    final m = raw is Map ? raw : const <String, dynamic>{};
    return GroupMember(
      id: _toInt(m['id']),
      username: (m['username'] ?? '').toString(),
      role: (m['role'] ?? 'member').toString(),
    );
  }
}

/// 被引用回复的消息摘要.
class ReplyRef {
  const ReplyRef({
    required this.id,
    required this.senderName,
    required this.content,
  });

  final int id;
  final String senderName;
  final String content;

  factory ReplyRef.fromJson(dynamic raw) {
    final m = raw is Map ? raw : const <String, dynamic>{};
    return ReplyRef(
      id: _toInt(m['id']),
      senderName: (m['sender_name'] ?? '').toString(),
      content: (m['content'] ?? '').toString(),
    );
  }
}

/// 表情表态计数.
class Reaction {
  const Reaction({
    required this.emoji,
    required this.count,
    required this.mine,
  });

  final String emoji;
  final int count;
  final bool mine;

  static List<Reaction> parseList(dynamic raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is Map)
          Reaction(
            emoji: (e['emoji'] ?? '').toString(),
            count: _toInt(e['count']),
            mine: e['mine'] == true,
          ),
    ];
  }
}

int _toInt(dynamic v) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

String _two(int v) => v.toString().padLeft(2, '0');

/// 服务器时间为 UTC 裸值 (无时区后缀): 补 Z 按 UTC 解析.
DateTime? parseServerTime(dynamic raw) {
  var s = (raw ?? '').toString();
  if (s.isEmpty) return null;
  if (!s.endsWith('Z') && !RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(s)) {
    s = '${s}Z';
  }
  return DateTime.tryParse(s);
}

/// 转东八区时钟值 (无论设备时区; 返回仍是 UTC 实例, 读字段即为北京时间).
DateTime toBeijingClock(DateTime dt) => dt.toUtc().add(const Duration(hours: 8));

/// 会话列表时间: 今天 HH:mm, 昨天 '昨天', 更早 MM-dd. 统一东八区.
String chatTimeLabel(DateTime? dt) {
  if (dt == null) return '';
  final local = toBeijingClock(dt);
  final nowBj = toBeijingClock(DateTime.now());
  final today = DateTime.utc(nowBj.year, nowBj.month, nowBj.day);
  final day = DateTime.utc(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return '${_two(local.hour)}:${_two(local.minute)}';
  if (diff == 1) return '昨天';
  return '${_two(local.month)}-${_two(local.day)}';
}

/// 消息气泡时间 (HH:mm, 东八区).
String chatBubbleTime(DateTime? dt) {
  if (dt == null) return '';
  final local = toBeijingClock(dt);
  return '${_two(local.hour)}:${_two(local.minute)}';
}

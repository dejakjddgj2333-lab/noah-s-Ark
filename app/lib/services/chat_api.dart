import 'package:flutter/foundation.dart';

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

  /// 好友请求: incoming + outgoing 两组.
  static Future<FriendRequests> friendRequests() async {
    final resp = await McApi.get('$_prefix/friends/requests', token: _token);
    return FriendRequests.fromJson(resp);
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
      {int? replyToId}) async {
    final resp = await McApi.post(
        '$_prefix/conversations/$conversationId/messages',
        {
          'content': content,
          'reply_to_id': ?replyToId,
        },
        token: _token);
    return ChatMessage.fromJson(resp);
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
      createdAt: DateTime.tryParse((m['created_at'] ?? '').toString()),
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
    LastMessage? lastMessage,
    int? unreadCount,
  }) =>
      Conversation(
        id: id,
        type: type,
        name: name,
        memberCount: memberCount,
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
    required this.content,
    required this.senderName,
    this.createdAt,
  });

  final String content;
  final String senderName;
  final DateTime? createdAt;

  factory LastMessage.fromJson(dynamic raw) {
    final m = raw is Map ? raw : const <String, dynamic>{};
    return LastMessage(
      content: (m['content'] ?? '').toString(),
      senderName: (m['sender_name'] ?? '').toString(),
      createdAt: DateTime.tryParse((m['created_at'] ?? '').toString()),
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
    this.replyTo,
    this.createdAt,
    this.reactions = const [],
  });

  final int id;
  final int senderId;
  final String senderName;
  final String content;
  final ReplyRef? replyTo;
  final DateTime? createdAt;
  final List<Reaction> reactions;

  ChatMessage copyWith({List<Reaction>? reactions}) => ChatMessage(
        id: id,
        senderId: senderId,
        senderName: senderName,
        content: content,
        replyTo: replyTo,
        createdAt: createdAt,
        reactions: reactions ?? this.reactions,
      );

  factory ChatMessage.fromJson(dynamic raw) {
    final m = raw is Map ? raw : const <String, dynamic>{};
    final sender = m['sender'];
    final senderMap = sender is Map ? sender : const <String, dynamic>{};
    final reply = m['reply_to'];
    return ChatMessage(
      id: _toInt(m['id']),
      senderId: _toInt(senderMap['id']),
      senderName: (senderMap['username'] ?? '').toString(),
      content: (m['content'] ?? '').toString(),
      replyTo: reply is Map ? ReplyRef.fromJson(reply) : null,
      createdAt: DateTime.tryParse((m['created_at'] ?? '').toString()),
      reactions: Reaction.parseList(m['reactions']),
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

/// 会话列表时间: 今天 HH:mm, 昨天 '昨天', 更早 MM-dd.
String chatTimeLabel(DateTime? dt) {
  if (dt == null) return '';
  final local = dt.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return '${_two(local.hour)}:${_two(local.minute)}';
  if (diff == 1) return '昨天';
  return '${_two(local.month)}-${_two(local.day)}';
}

/// 消息气泡时间 (HH:mm).
String chatBubbleTime(DateTime? dt) {
  if (dt == null) return '';
  final local = dt.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)}';
}

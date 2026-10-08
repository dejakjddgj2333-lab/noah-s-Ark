import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';
import 'auth.dart';

/// 聊天 WebSocket 单例: 登录后连接, 登出断开, 指数退避自动重连 (1s→30s).
/// 事件为广播流, JSON Map: {type:'message'|'reaction'|'friend_request'|'ping', ...}.
/// 'ping' 心跳无需响应, 已忽略.
class ChatWs {
  ChatWs._();
  static final ChatWs instance = ChatWs._();

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  bool _connected = false;
  int _retryCount = 0;

  final _eventController = StreamController<Map<String, dynamic>>.broadcast();

  /// 聊天事件广播流.
  Stream<Map<String, dynamic>> get events => _eventController.stream;

  bool get isConnected => _connected;

  /// 发送 JSON 消息到服务器 (语音通话信令). 未连接时静默 no-op, 返回是否已发送.
  bool send(Map<String, dynamic> payload) {
    if (!_connected || _channel == null) return false;
    try {
      _channel!.sink.add(jsonEncode(payload));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 由 McApi.baseUrl 推导 ws(s) 地址. http→ws, https→wss.
  static String wsUrl(String token) {
    final base = McApi.baseUrl.replaceFirst('http', 'ws');
    return '$base/api/chat/ws?token=$token';
  }

  /// 登录后调用. 已连接或已在重连流程中则忽略.
  void connect() {
    final token = AuthStore.instance.token;
    if (token == null || _channel != null) return;
    _connect(token);
  }

  void _connect(String token) {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl(token)));
    } catch (_) {
      _scheduleReconnect();
      return;
    }
    _sub = _channel!.stream.listen(
      _onMessage,
      onError: (_) => _scheduleReconnect(),
      onDone: _scheduleReconnect,
      cancelOnError: true,
    );
    _connected = true;
    _retryCount = 0;
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return;
      if (json['type'] == 'ping') return; // 心跳, 无需响应.
      if (!_eventController.isClosed) _eventController.add(json);
    } catch (_) {
      // 单条坏消息不影响连接.
    }
  }

  void _scheduleReconnect() {
    _cleanupChannel();
    // 仅登录状态下自动重连.
    if (AuthStore.instance.token == null) return;
    _retryCount++;
    final delay = Duration(seconds: (1 << (_retryCount - 1)).clamp(1, 30));
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, connect);
  }

  void _cleanupChannel() {
    _connected = false;
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  /// 登出时调用: 停止重连并关闭连接.
  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _retryCount = 0;
    _cleanupChannel();
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// OKX 公共行情 WebSocket 推送 (tickers 频道, 数值字段为字符串).
class TickerPush {
  const TickerPush({
    required this.instId,
    required this.last,
    required this.open24h,
    required this.high24h,
    required this.low24h,
    required this.volCcy24h,
  });

  final String instId;
  final double last;
  final double open24h;
  final double high24h;
  final double low24h;

  /// 24H 成交量 (SWAP 为合约张数), 名义美元 = volCcy24h * last.
  final double volCcy24h;

  double get changePct =>
      open24h > 0 ? (last - open24h) / open24h * 100 : 0;

  /// 名义成交额 (USD) — 榜单排序/显示用.
  double get notionalUsd => volCcy24h * last;
}

/// 直连 OKX 公共 WS (wss://ws.okx.com:8443/ws/v5/public) 单例,
/// 订阅多个交易对 tickers 频道, 自动重连 + 心跳.
class TickerWs {
  TickerWs._();
  static final TickerWs instance = TickerWs._();

  static const _url = 'wss://ws.okx.com:8443/ws/v5/public';

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  Set<String> _instIds = {};
  bool _disposed = false;
  int _retryCount = 0;

  final _pushController = StreamController<TickerPush>.broadcast();
  Stream<TickerPush> get stream => _pushController.stream;

  final _connController = StreamController<bool>.broadcast();
  Stream<bool> get connStream => _connController.stream;

  /// 增量订阅一组交易对. 首次调用触发连接, 后续只订阅新增的.
  void subscribe(Set<String> instIds) {
    if (instIds.isEmpty) return;
    final newIds = instIds.difference(_instIds);
    _instIds = _instIds.union(instIds);
    if (_channel == null) {
      _connect();
    } else if (newIds.isNotEmpty) {
      _sendSubscribe(newIds);
    }
  }

  void _connect() {
    if (_disposed) return;
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_url));
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
    _retryCount = 0;
    if (!_connController.isClosed) _connController.add(true);
    _sendSubscribe(_instIds);
    // OKX 要求 30s 内必须有消息, 25s 心跳.
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      _channel?.sink.add('ping');
    });
  }

  void _sendSubscribe(Set<String> instIds) {
    if (instIds.isEmpty) return;
    _channel?.sink.add(
      jsonEncode({
        'op': 'subscribe',
        'args': [
          for (final id in instIds) {'channel': 'tickers', 'instId': id},
        ],
      }),
    );
  }

  void _onMessage(dynamic raw) {
    if (raw is! String || raw == 'pong') return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json.containsKey('event')) return; // subscribe/error 回执
      final data = json['data'] as List?;
      if (data == null || data.isEmpty) return;
      for (final row in data) {
        final map = row as Map<String, dynamic>;
        final instId = map['instId'] as String?;
        final last = double.tryParse(map['last']?.toString() ?? '');
        if (instId == null || last == null) continue;
        _pushController.add(
          TickerPush(
            instId: instId,
            last: last,
            open24h: double.tryParse(map['open24h']?.toString() ?? '') ?? 0,
            high24h: double.tryParse(map['high24h']?.toString() ?? '') ?? 0,
            low24h: double.tryParse(map['low24h']?.toString() ?? '') ?? 0,
            volCcy24h: double.tryParse(map['volCcy24h']?.toString() ?? '') ?? 0,
          ),
        );
      }
    } catch (_) {
      // 单条坏消息不影响连接.
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _cleanup(keepController: true);
    if (!_connController.isClosed) _connController.add(false);
    // 指数退避: 1s → 2s → 4s ... 封顶 30s.
    _retryCount++;
    final delay = Duration(seconds: (1 << (_retryCount - 1)).clamp(1, 30));
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _connect);
  }

  void _cleanup({bool keepController = false}) {
    _pingTimer?.cancel();
    _pingTimer = null;
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
    if (!keepController) {
      _reconnectTimer?.cancel();
      _pushController.close();
      _connController.close();
    }
  }

  void dispose() {
    _disposed = true;
    _cleanup();
  }
}

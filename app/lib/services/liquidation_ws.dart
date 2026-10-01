import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Binance 合约强平推送 (单条).
///
/// 方向语义: S=SELL → 卖出强平 → 多单被爆 (long);
///           S=BUY  → 买入强平 → 空单被爆 (short).
class LiqPush {
  const LiqPush({
    required this.symbol,
    required this.baseCcy,
    required this.side,
    required this.price,
    required this.qty,
    required this.notionalUsd,
    required this.ts,
  });

  /// 交易对, 如 'BTCUSDT'.
  final String symbol;

  /// 基础币, 剥掉尾部 USDT/USDC, 如 'BTC'.
  final String baseCcy;

  /// 'long' = 多单爆仓, 'short' = 空单爆仓.
  final String side;

  final double price;
  final double qty;

  /// 名义美元 = price * qty.
  final double notionalUsd;

  /// 强平时间戳 (ms).
  final int ts;
}

/// 直连 Binance 合约强平 WS (wss://fstream.binance.com/ws/!forceOrder@arr)
/// 单例: 单一全市场流, 无需订阅 API. 有监听才连接, 无监听断开, 自动重连.
///
/// Binance 服务端发 ping 帧, web_socket_channel 自动回 pong,
/// 无需应用层心跳 (区别于 OKX).
class LiquidationWs {
  LiquidationWs._();
  static final LiquidationWs instance = LiquidationWs._();

  static const _url = 'wss://fstream.binance.com/ws/!forceOrder@arr';

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  int _retryCount = 0;
  bool _listening = false;

  late final _pushController = StreamController<LiqPush>.broadcast(
    onListen: _onListen,
    onCancel: _onCancel,
  );

  /// 广播流; 首个监听者触发连接, 最后一个取消后断开.
  Stream<LiqPush> get stream => _pushController.stream;

  void _onListen() {
    _listening = true;
    _connect();
  }

  void _onCancel() {
    // broadcast 流: 所有监听者都取消后才触发.
    if (!_pushController.hasListener) {
      _listening = false;
      _disconnect();
    }
  }

  void _connect() {
    if (!_listening || _channel != null) return;
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
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final data = json['data'];
      if (data is! Map) return;
      final o = data['o'];
      if (o is! Map) return;
      final symbol = o['s']?.toString();
      final sideRaw = o['S']?.toString().toUpperCase();
      final price = double.tryParse(o['p']?.toString() ?? '') ?? 0;
      final qty = double.tryParse(o['q']?.toString() ?? '') ?? 0;
      final ts = int.tryParse(o['T']?.toString() ?? '') ?? 0;
      if (symbol == null || sideRaw == null || price <= 0) return;
      // SELL = 卖出强平 = 多单爆仓; BUY = 买入强平 = 空单爆仓.
      final side = sideRaw == 'SELL' ? 'long' : 'short';
      _pushController.add(
        LiqPush(
          symbol: symbol,
          baseCcy: _baseCcy(symbol),
          side: side,
          price: price,
          qty: qty,
          notionalUsd: price * qty,
          ts: ts,
        ),
      );
    } catch (_) {
      // 单条坏消息不影响连接.
    }
  }

  static String _baseCcy(String symbol) {
    var s = symbol;
    if (s.endsWith('USDT')) return s.substring(0, s.length - 4);
    if (s.endsWith('USDC')) return s.substring(0, s.length - 4);
    return s;
  }

  void _scheduleReconnect() {
    if (!_listening) return;
    _closeChannel();
    // 指数退避: 1s → 2s → 4s ... 封顶 30s.
    _retryCount++;
    final delay = Duration(seconds: (1 << (_retryCount - 1)).clamp(1, 30));
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _connect);
  }

  void _closeChannel() {
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
  }

  void _disconnect() {
    _reconnectTimer?.cancel();
    _closeChannel();
  }
}

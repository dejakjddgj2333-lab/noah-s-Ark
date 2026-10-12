/// Live Activities (盯盘): Dart 侧封装.
///
/// 原生通道 mc.live (AppDelegate.swift):
///   startActivity(symbol) → 启动锁屏/灵动岛活动, 原生回传 pushToken
///   endActivity() → 结束
/// 拿到 activity pushToken 后上报服务端, 之后价格更新由服务端
/// 60s 一轮 APNs (push-type liveactivity) 推到锁屏.
/// 仅 iOS 16.1+; 其它平台/低版本调用返回 false.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'auth.dart';

class LiveActivityService {
  LiveActivityService._() {
    _channel.setMethodCallHandler(_onNativeCall);
  }
  static final LiveActivityService instance = LiveActivityService._();

  static const _channel = MethodChannel('mc.live');

  bool _active = false;
  String _symbol = '';
  String? _activityToken;

  bool get active => _active;
  String get symbol => _symbol;

  /// 状态变化回调 (详情页刷新盯盘按钮).
  final ValueNotifier<int> version = ValueNotifier(0);

  bool get _supported => !kIsWeb && Platform.isIOS;

  /// 开启盯盘. 返回 null=成功, 否则为失败原因 key.
  Future<String?> start(String symbol) async {
    if (!_supported) return 'unsupported';
    if ((AuthStore.instance.token ?? '').isEmpty) return 'login';
    try {
      final ok = await _channel.invokeMethod<bool>(
          'startActivity', {'symbol': symbol});
      if (ok != true) return 'unsupported';
      _active = true;
      _symbol = symbol;
      version.value++;
      return null;
    } on PlatformException catch (e) {
      return e.code == 'unsupported' ? 'unsupported' : 'failed';
    }
  }

  Future<void> stop() async {
    if (!_supported || !_active) return;
    _active = false;
    final token = _activityToken;
    _activityToken = null;
    version.value++;
    try {
      await _channel.invokeMethod('endActivity');
    } catch (_) {}
    if (token != null) {
      try {
        await McApi.del('/api/push/live-activity?token=$token',
            token: AuthStore.instance.token);
      } catch (_) {}
    }
  }

  /// 原生回调: activity push token 就绪 → 上报服务端.
  Future<void> _onNativeCall(MethodCall call) async {
    if (call.method != 'onActivityToken') return;
    final token = (call.arguments as String?) ?? '';
    if (token.isEmpty || !_active) return;
    _activityToken = token;
    try {
      await McApi.post('/api/push/live-activity', {
        'symbol': _symbol,
        'token': token,
      }, token: AuthStore.instance.token);
    } catch (_) {
      // 上报失败: 服务端不推更新, activity 本地仍可显示
    }
  }
}

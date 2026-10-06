import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api.dart';

/// 推送服务: 本地通知 + APNs device_token 上报.
///
/// 策略 (在线/离线):
/// - 在线: WS 实时收到消息 → [showLocal] 弹本地通知 (不经苹果服务器).
/// - 离线: 后端 push_if_offline 走 APNs 远程推送 (系统直接弹, 无需 App 处理).
///
/// device_token 由 iOS AppDelegate 经 channel `mc.push` 回传, 这里上报后端.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  static const _channel = MethodChannel('mc.push');
  final _fln = FlutterLocalNotificationsPlugin();

  String? _token; // 当前 APNs device_token
  String? _authToken; // 登录 token (由 AuthStore 注入, 避免循环 import)
  bool _inited = false;

  /// 登录 token 注入/清除 (AuthStore 登录/登出时调用).
  void setAuthToken(String? token) {
    _authToken = token;
  }

  /// App 启动时初始化 (main 里调用). 幂等.
  Future<void> init() async {
    if (_inited) return;
    _inited = true;

    // 本地通知插件初始化
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false, // 权限申请交给 AppDelegate 统一做
      requestSoundPermission: false,
      requestBadgePermission: false,
    );
    await _fln.initialize(
      const InitializationSettings(iOS: ios, android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );

    // 接收原生回传的 device_token → 上报后端
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPushToken' && call.arguments is String) {
        _token = call.arguments as String;
        await _upload();
      }
    });
  }

  /// 上报 token 到后端 (需登录). 重复上报后端幂等.
  Future<void> _upload() async {
    final t = _token;
    final auth = _authToken;
    if (t == null || auth == null) return;
    try {
      await McApi.post('/api/push/token', {
        'token': t,
        'platform': Platform.isIOS ? 'ios' : 'android',
      }, token: auth);
    } catch (_) {/* 静默, 下次登录/启动重试 */}
  }

  /// 登录后调用: 若 token 已到则补上报 (登录前拿到 token 的情况).
  Future<void> onLogin() => _upload();

  /// 注销推送 (通知开关关闭 / 登出).
  Future<void> unregister() async {
    final t = _token;
    final auth = _authToken;
    if (t == null || auth == null) return;
    try {
      await McApi.del('/api/push/token?token=$t', token: auth);
    } catch (_) {/* 静默 */}
  }

  int _notifId = 0;

  /// 弹本地通知 (在线时 WS 消息触发).
  Future<void> showLocal(String title, String body) async {
    const details = NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
      ),
      android: AndroidNotificationDetails(
        'mc_default',
        '通知',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _fln.show(_notifId++, title, body, details);
  }
}

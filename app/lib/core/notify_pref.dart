import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/push_service.dart';

/// 通知开关偏好 (本地持久化) + 绑定真实推送注册/注销.
/// 任一开关开 = 注册 APNs; 全关 = 注销 device_token.
class NotifyPref extends ChangeNotifier {
  NotifyPref._();
  static final NotifyPref instance = NotifyPref._();

  static const String _kMarket = 'mc_notify_market';
  static const String _kNotice = 'mc_notify_notice';

  bool market = true; // 行情提醒
  bool notice = true; // 公告通知

  bool get anyEnabled => market || notice;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    market = sp.getBool(_kMarket) ?? true;
    notice = sp.getBool(_kNotice) ?? true;
    notifyListeners();
  }

  Future<void> setMarket(bool v) async {
    if (v == market) return;
    market = v;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kMarket, v);
    await _syncPush();
  }

  Future<void> setNotice(bool v) async {
    if (v == notice) return;
    notice = v;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kNotice, v);
    await _syncPush();
  }

  /// 开关状态同步到推送注册: 全开→注销, 有开→确保已上报.
  Future<void> _syncPush() async {
    if (anyEnabled) {
      await PushService.instance.onLogin(); // 确保 token 已上报
    } else {
      await PushService.instance.unregister();
    }
  }
}

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 通知开关偏好 (本地持久化).
/// 目前仅本地开关; 真正的 APNs 远程推送需后端 device_token 上报 + 推送服务, 待接入.
class NotifyPref extends ChangeNotifier {
  NotifyPref._();
  static final NotifyPref instance = NotifyPref._();

  static const String _kMarket = 'mc_notify_market';
  static const String _kNotice = 'mc_notify_notice';

  bool market = true; // 行情提醒
  bool notice = true; // 公告通知

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
    // TODO(push): 开启时注册 APNs device_token 并上报后端, 关闭时注销.
  }

  Future<void> setNotice(bool v) async {
    if (v == notice) return;
    notice = v;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kNotice, v);
    // TODO(push): 同上, 接 APNs.
  }
}

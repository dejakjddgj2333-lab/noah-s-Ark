import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'chat_api.dart';
import 'chat_ws.dart';

/// 登录状态: token + 用户信息, 持久化到 SharedPreferences.
class AuthStore extends ChangeNotifier {
  AuthStore._();
  static final AuthStore instance = AuthStore._();

  String? token;
  int? userId;
  String? username;
  String? email;

  bool get loggedIn => token != null;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    token = sp.getString('mc_token');
    userId = sp.getInt('mc_uid');
    username = sp.getString('mc_username');
    email = sp.getString('mc_email');
    notifyListeners();
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    if (token == null) {
      await sp.remove('mc_token');
      await sp.remove('mc_uid');
      await sp.remove('mc_username');
      await sp.remove('mc_email');
    } else {
      await sp.setString('mc_token', token!);
      await sp.setInt('mc_uid', userId!);
      await sp.setString('mc_username', username!);
      await sp.setString('mc_email', email!);
    }
  }

  /// 发注册验证码. 返回 dev 调试码 (SMTP 未配置时后端回显), 否则 null.
  Future<String?> sendEmailCode(String email) async {
    final resp = await McApi.post('/api/auth/send-email-code', {
      'email': email,
      'purpose': 'register',
    });
    return resp['debug_code'] as String?;
  }

  Future<void> register({
    required String username,
    required String password,
    required String email,
    required String code,
    String? inviteCode,
  }) async {
    final resp = await McApi.post('/api/auth/register', {
      'username': username,
      'password': password,
      'email': email,
      'code': code,
      if (inviteCode != null && inviteCode.isNotEmpty)
        'invite_code': inviteCode,
    });
    await _applyToken(resp);
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    final resp = await McApi.post('/api/auth/login', {
      'username': username,
      'password': password,
    });
    await _applyToken(resp);
  }

  Future<void> _applyToken(Map<String, dynamic> resp) async {
    token = resp['token'] as String;
    final user = resp['user'] as Map<String, dynamic>;
    userId = user['id'] as int;
    username = user['username'] as String;
    email = user['email'] as String?;
    await _save();
    notifyListeners();
    // 登录/注册成功后启动聊天长连接.
    ChatWs.instance.connect();
  }

  Future<void> logout() async {
    token = null;
    userId = null;
    username = null;
    email = null;
    await _save();
    // 登出断开聊天长连接, 清空未读角标.
    ChatWs.instance.disconnect();
    ChatApi.unreadCount.value = 0;
    notifyListeners();
  }
}

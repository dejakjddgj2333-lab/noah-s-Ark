import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'chat_api.dart';
import 'chat_db.dart';
import 'chat_ws.dart';

/// 登录状态: token + 用户信息, 持久化到 SharedPreferences.
class AuthStore extends ChangeNotifier {
  AuthStore._() {
    // token 过期/失效: 任一接口 401 即自动登出, 回到登录页.
    McApi.onUnauthorized = () async {
      if (token != null) await logout();
    };
  }
  static final AuthStore instance = AuthStore._();

  String? token;
  int? userId;
  String? username;
  String? email;
  String? nickname;
  String? avatarUrl; // 相对路径 /api/auth/avatars/<uuid>
  bool hasFundPassword = false; // 资金密码已设置
  bool has2fa = false; // 谷歌验证已绑定
  String? antiPhishingCode; // 防钓鱼码

  /// 从 /me 或 login 的 user 对象同步安全设置状态.
  void _applySecurity(Map<String, dynamic> user) {
    hasFundPassword = user['has_fund_password'] == true;
    has2fa = user['has_2fa'] == true;
    final ap = (user['anti_phishing_code'] ?? '').toString();
    antiPhishingCode = ap.isEmpty ? null : ap;
  }

  /// 展示名: 昵称优先, 空回退用户名.
  String get displayName =>
      (nickname != null && nickname!.isNotEmpty)
          ? nickname!
          : (username ?? '');

  bool get loggedIn => token != null;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    token = sp.getString('mc_token');
    userId = sp.getInt('mc_uid');
    username = sp.getString('mc_username');
    email = sp.getString('mc_email');
    nickname = sp.getString('mc_nickname');
    avatarUrl = sp.getString('mc_avatar');
    notifyListeners();
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    if (token == null) {
      await sp.remove('mc_token');
      await sp.remove('mc_uid');
      await sp.remove('mc_username');
      await sp.remove('mc_email');
      await sp.remove('mc_nickname');
      await sp.remove('mc_avatar');
    } else {
      await sp.setString('mc_token', token!);
      await sp.setInt('mc_uid', userId!);
      await sp.setString('mc_username', username!);
      if (email != null) {
        await sp.setString('mc_email', email!);
      }
      if (nickname != null && nickname!.isNotEmpty) {
        await sp.setString('mc_nickname', nickname!);
      } else {
        await sp.remove('mc_nickname');
      }
      if (avatarUrl != null && avatarUrl!.isNotEmpty) {
        await sp.setString('mc_avatar', avatarUrl!);
      } else {
        await sp.remove('mc_avatar');
      }
    }
  }

  /// 静默从服务端同步资料 (昵称/头像可能在别处改过).
  Future<void> refreshProfile() async {
    if (token == null) return;
    try {
      final resp = await McApi.get('/api/auth/me', token: token);
      final nick = (resp['nickname'] ?? '').toString();
      nickname = nick.isEmpty ? null : nick;
      final av = (resp['avatar_url'] ?? '').toString();
      avatarUrl = av.isEmpty ? null : av;
      email = (resp['email'] ?? email)?.toString();
      _applySecurity(resp);
      await _save();
      notifyListeners();
    } catch (_) {/* 静默 */}
  }

  /// 改昵称 (空串清除). 成功后本地同步.
  Future<void> updateNickname(String nickname) async {    final resp = await McApi.put('/api/auth/profile', {
      'nickname': nickname,
    }, token: token);
    this.nickname = (resp['nickname'] ?? '').toString().isEmpty
        ? null
        : resp['nickname'].toString();
    await _save();
    notifyListeners();
  }

  /// 改登录密码: 校验旧密码, 通过则更新. 抛 ApiException(含后端 detail 文案).
  Future<void> changePassword(String oldPassword, String newPassword) async {
    await McApi.post('/api/auth/change-password', {
      'old_password': oldPassword,
      'new_password': newPassword,
    }, token: token);
  }

  /// 上传头像 (jpg/png/webp/gif, ≤10MB). 成功后本地同步.
  Future<void> uploadAvatar(Uint8List bytes, String filename) async {
    final req = http.MultipartRequest(
        'POST', Uri.parse('${McApi.baseUrl}/api/auth/avatar'));
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    req.files.add(http.MultipartFile.fromBytes('file', bytes,
        filename: filename));
    final resp = await req.send();
    if (resp.statusCode >= 400) {
      throw Exception('avatar upload failed: ${resp.statusCode}');
    }
    final body = jsonDecode(await resp.stream.bytesToString());
    avatarUrl = (body['avatar_url'] ?? '').toString();
    await _save();
    notifyListeners();
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
      'device_name': _deviceName(),
      'platform': _platform(),
    });
    await _applyToken(resp);
  }

  /// 设备名/平台上报 (登录设备管理用).
  static String _platform() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  static String _deviceName() {
    if (kIsWeb) return 'Web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'iPhone';
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.macOS:
        return 'Mac';
      case TargetPlatform.windows:
        return 'Windows PC';
      case TargetPlatform.linux:
        return 'Linux';
      case TargetPlatform.fuchsia:
        return 'Fuchsia';
    }
  }

  // ---------- 安全设置 ----------

  /// 资金密码: 设置 (需登录密码).
  Future<void> setFundPassword(String fundPassword, String loginPassword) async {
    await McApi.post('/api/auth/fund-password/set', {
      'fund_password': fundPassword,
      'login_password': loginPassword,
    }, token: token);
  }

  /// 资金密码: 修改.
  Future<void> changeFundPassword(String oldPw, String newPw) async {
    await McApi.post('/api/auth/fund-password/change', {
      'old_fund_password': oldPw,
      'new_fund_password': newPw,
    }, token: token);
  }

  /// 2FA: 生成密钥, 返回 {secret, otpauth_url}.
  Future<Map<String, dynamic>> totpSetup() async {
    return McApi.post('/api/auth/2fa/setup', {}, token: token);
  }

  /// 2FA: 绑定 (校验验证码).
  Future<void> totpEnable(String code) async {
    await McApi.post('/api/auth/2fa/enable', {'code': code}, token: token);
  }

  /// 2FA: 解绑 (校验验证码).
  Future<void> totpDisable(String code) async {
    await McApi.post('/api/auth/2fa/disable', {'code': code}, token: token);
  }

  /// 防钓鱼码: 设置 (空串=清除).
  Future<void> setAntiPhishing(String code) async {
    await McApi.post('/api/auth/anti-phishing', {'code': code}, token: token);
  }

  /// 登录设备列表.
  Future<List<dynamic>> devices() async {
    return McApi.getList('/api/auth/devices', token: token);
  }

  /// 下线设备.
  Future<void> removeDevice(int id) async {
    await McApi.del('/api/auth/devices/$id', token: token);
  }

  Future<void> _applyToken(Map<String, dynamic> resp) async {
    token = resp['token'] as String;
    final user = resp['user'] as Map<String, dynamic>;
    userId = user['id'] as int;
    username = user['username'] as String;
    email = user['email'] as String?;
    final nick = (user['nickname'] ?? '').toString();
    nickname = nick.isEmpty ? null : nick;
    final av = (user['avatar_url'] ?? '').toString();
    avatarUrl = av.isEmpty ? null : av;
    _applySecurity(user);
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
    nickname = null;
    avatarUrl = null;
    await _save();
    // 登出断开聊天长连接, 清空未读与好友请求角标, 清空本地消息库.
    ChatWs.instance.disconnect();
    ChatApi.unreadCount.value = 0;
    ChatApi.friendRequestCount.value = 0;
    await ChatDb.clearAll();
    notifyListeners();
  }
}

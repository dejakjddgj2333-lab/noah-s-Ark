import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';

/// Session state: token + current user, persisted across launches.
class AuthStore extends ChangeNotifier {
  AuthStore._();
  static final AuthStore I = AuthStore._();

  static const _kToken = 'mc_token';
  static const _kUser = 'mc_user';

  String? token;
  Map<String, dynamic>? user;
  bool ready = false;

  Future<void> init() async {
    final sp = await SharedPreferences.getInstance();
    token = sp.getString(_kToken);
    final raw = sp.getString(_kUser);
    if (raw != null) {
      try {
        user = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {}
    }
    ApiClient.I.token = token;
    ApiClient.I.onUnauthorized = logout;
    ready = true;
    notifyListeners();
    // Refresh profile silently; stale cache still renders.
    if (token != null) refreshMe();
  }

  bool get loggedIn => token != null;

  Future<void> login(String username, String password) async {
    final res = await ApiClient.I.login(username, password);
    final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
    final t = (map['access_token'] ?? map['token']) as String?;
    if (t == null) throw ApiException('登录响应缺少 token');
    token = t;
    ApiClient.I.token = t;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kToken, t);
    await refreshMe();
    notifyListeners();
  }

  Future<void> refreshMe() async {
    try {
      final res = await ApiClient.I.me();
      if (res is Map) {
        user = Map<String, dynamic>.from(res);
        final sp = await SharedPreferences.getInstance();
        await sp.setString(_kUser, jsonEncode(user));
        notifyListeners();
      }
    } catch (_) {/* keep stale cache */}
  }

  Future<void> logout() async {
    token = null;
    user = null;
    ApiClient.I.token = null;
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kToken);
    await sp.remove(_kUser);
    notifyListeners();
  }

  String get displayName =>
      (user?['nickname'] ?? user?['username'] ?? '') as String;
}

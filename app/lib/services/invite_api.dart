import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';
import 'auth.dart';

/// 邀请绑定信息 (对应后端 /api/invite/me).
class InviteInfo {
  InviteInfo({
    required this.inviteCode,
    required this.inviterId,
    required this.inviterUsername,
    required this.canBind,
    required this.bindBlockReason,
  });

  final String inviteCode;
  final int? inviterId;
  final String? inviterUsername;
  final bool canBind;
  final String? bindBlockReason;

  bool get bound => inviterId != null;

  factory InviteInfo.fromJson(Map<String, dynamic> j) => InviteInfo(
        inviteCode: j['invite_code'] as String,
        inviterId: j['inviter_id'] as int?,
        inviterUsername: j['inviter_username'] as String?,
        canBind: j['can_bind'] as bool? ?? false,
        bindBlockReason: j['bind_block_reason'] as String?,
      );
}

/// 邀请绑定接口. bind 走带 token 的 POST (McApi.post 不支持 token, 这里直连).
class InviteApi {
  static Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${AuthStore.instance.token}',
      };

  static Future<InviteInfo> me() async {
    final resp = await McApi.get(
      '/api/invite/me',
      token: AuthStore.instance.token,
    );
    return InviteInfo.fromJson(resp);
  }

  static Future<InviteInfo> bind(String inviteCode) async {
    final resp = await http
        .post(
          Uri.parse('${McApi.baseUrl}/api/invite/bind'),
          headers: _authHeaders,
          body: jsonEncode({'invite_code': inviteCode.trim()}),
        )
        .timeout(const Duration(seconds: 10));
    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    if (resp.statusCode >= 400) {
      final detail = data['detail'];
      throw ApiException(
        resp.statusCode,
        detail is String ? detail : '绑定失败 (${resp.statusCode})',
      );
    }
    return InviteInfo.fromJson(data as Map<String, dynamic>);
  }
}

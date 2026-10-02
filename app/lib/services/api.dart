import 'dart:convert';

import 'package:http/http.dart' as http;

/// 明策 API 客户端. 默认走线上后端 (push 到 GitHub 自动部署);
/// 本地联调用 --dart-define=API_BASE=http://localhost:8000 覆盖.
class McApi {
  McApi._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://shipapi.bdxapi.com',
  );

  /// 401 全局回调 (token 过期/失效). AuthStore 注册, 自动登出回登录页.
  /// 仅在请求带了 token 时触发 — 登录接口 401 是密码错误, 不触发.
  static Future<void> Function()? onUnauthorized;

  static void _checkUnauthorized(http.Response resp, String? token) {
    if (resp.statusCode == 401 && token != null) {
      final cb = onUnauthorized;
      if (cb != null) cb();
    }
  }

  static Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final resp = await http
        .post(
          Uri.parse('$baseUrl$path'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 10));
    _checkUnauthorized(resp, token);
    return _decode(resp);
  }

  static Future<Map<String, dynamic>> get(String path, {String? token}) async {
    final resp = await http.get(
      Uri.parse('$baseUrl$path'),
      headers: {if (token != null) 'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 10));
    _checkUnauthorized(resp, token);
    return _decode(resp);
  }

  /// GET 返回 JSON 数组的接口 (聊天列表等). 非数组时返回空 List (不抛异常).
  static Future<List<dynamic>> getList(String path, {String? token}) async {
    final resp = await http.get(
      Uri.parse('$baseUrl$path'),
      headers: {if (token != null) 'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 10));
    _checkUnauthorized(resp, token);
    if (resp.statusCode == 204 || resp.bodyBytes.isEmpty) {
      return const [];
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    if (resp.statusCode >= 400) {
      final detail = data is Map ? data['detail'] : null;
      final msg = detail is String
          ? detail
          : (detail is List && detail.isNotEmpty
              ? (detail[0]['msg'] ?? '请求失败').toString()
              : '请求失败 (${resp.statusCode})');
      throw ApiException(resp.statusCode, msg);
    }
    return data is List ? data : const [];
  }

  /// DELETE 请求. 204 无 body 时返回空 Map (不抛异常).
  static Future<Map<String, dynamic>> del(String path, {String? token}) async {
    final resp = await http.delete(
      Uri.parse('$baseUrl$path'),
      headers: {if (token != null) 'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 10));
    _checkUnauthorized(resp, token);
    return _decode(resp);
  }

  /// PUT 请求 (JSON body).
  static Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final resp = await http
        .put(
          Uri.parse('$baseUrl$path'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 10));
    _checkUnauthorized(resp, token);
    return _decode(resp);
  }

  static Map<String, dynamic> _decode(http.Response resp) {
    if (resp.statusCode == 204 || resp.bodyBytes.isEmpty) {
      return <String, dynamic>{};
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    if (resp.statusCode >= 400) {
      // FastAPI detail: str 或校验错误数组
      final detail = data['detail'];
      final msg = detail is String
          ? detail
          : (detail is List && detail.isNotEmpty
              ? (detail[0]['msg'] ?? '请求失败').toString()
              : '请求失败 (${resp.statusCode})');
      throw ApiException(resp.statusCode, msg);
    }
    return data as Map<String, dynamic>;
  }
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

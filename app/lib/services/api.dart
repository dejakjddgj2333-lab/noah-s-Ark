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
    return _decode(resp);
  }

  static Future<Map<String, dynamic>> get(String path, {String? token}) async {
    final resp = await http.get(
      Uri.parse('$baseUrl$path'),
      headers: {if (token != null) 'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 10));
    return _decode(resp);
  }

  /// GET 返回 JSON 数组的接口 (聊天列表等). 非数组时返回空 List (不抛异常).
  static Future<List<dynamic>> getList(String path, {String? token}) async {
    final resp = await http.get(
      Uri.parse('$baseUrl$path'),
      headers: {if (token != null) 'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 10));
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

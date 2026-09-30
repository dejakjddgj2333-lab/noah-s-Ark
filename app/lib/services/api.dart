import 'dart:convert';

import 'package:http/http.dart' as http;

/// 明策 API 客户端. baseUrl 按平台调整: web 直连, Android 模拟器用 10.0.2.2.
class McApi {
  McApi._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://localhost:8000',
  );

  static Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final resp = await http
        .post(
          Uri.parse('$baseUrl$path'),
          headers: {'Content-Type': 'application/json'},
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

  static Map<String, dynamic> _decode(http.Response resp) {
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

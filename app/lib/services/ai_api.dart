import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';

/// AI 助手接口 (DeepSeek; 对话为 SSE 流式, 其余普通 JSON).
/// 对齐 web-terminal /ai 与 desktop AiPage.
class AiApi {
  AiApi._();

  /// 当日市场综述 {date, text, cached}
  static Future<Map<String, dynamic>> dailySummary(String token,
      {String lang = 'zh'}) {
    return McApi.get('/api/ai/daily-summary?lang=$lang', token: token);
  }

  /// K线技术分析 {ok, report, cached, error}
  static Future<Map<String, dynamic>> klineAnalysis(String token, String instId,
      {String bar = '1D'}) {
    return McApi.get('/api/ai/kline-analysis?inst_id=$instId&bar=$bar',
        token: token);
  }

  /// SSE 流式对话. onDelta 逐段回调; 返回完整文本.
  /// 外部取消: 调返回 StreamSubscription? 不行 — 用 [cancel] 包装的 Future,
  /// 这里暴露 token 式取消: 传入 AiChatCancel, cancel() 即断流.
  static Future<String> chatStream({
    required String token,
    required String message,
    required List<Map<String, String>> history,
    String lang = 'zh',
    required void Function(String delta) onDelta,
    AiChatCancel? cancel,
  }) async {
    final client = http.Client();
    cancel?._bind(client);
    try {
      final req = http.Request(
          'POST', Uri.parse('${McApi.baseUrl}/api/ai/market-chat'))
        ..headers['Content-Type'] = 'application/json'
        ..headers['Authorization'] = 'Bearer $token'
        ..body = jsonEncode(
            {'message': message, 'history': history, 'lang': lang});
      final resp = await client.send(req).timeout(
          const Duration(seconds: 15)); // 首字节超时; 流本身不限时
      if (resp.statusCode == 401) {
        final cb = McApi.onUnauthorized;
        if (cb != null) cb();
      }
      if (resp.statusCode >= 400) {
        final body = await resp.stream.bytesToString();
        String msg = '请求失败 (${resp.statusCode})';
        try {
          final data = jsonDecode(body);
          if (data is Map && data['detail'] is String) {
            msg = data['detail'] as String;
          }
        } catch (_) {}
        throw ApiException(resp.statusCode, msg);
      }
      final full = StringBuffer();
      var buf = '';
      await for (final chunk in resp.stream) {
        if (cancel?.cancelled == true) break;
        buf += utf8.decode(chunk, allowMalformed: true);
        final lines = buf.split('\n');
        buf = lines.removeLast(); // 最后一段可能不完整, 留到下次
        for (final raw in lines) {
          final line = raw.trim();
          if (!line.startsWith('data:')) continue;
          final payload = line.substring(5).trim();
          if (payload == '[DONE]') return full.toString();
          try {
            final d = jsonDecode(payload);
            final delta = d is Map ? d['delta'] as String? : null;
            if (delta != null && delta.isNotEmpty) {
              full.write(delta);
              onDelta(delta);
            }
          } catch (_) {}
        }
      }
      return full.toString();
    } finally {
      client.close();
    }
  }
}

/// 流式对话取消令牌: cancel() 后流读到下一段即停.
class AiChatCancel {
  bool cancelled = false;
  http.Client? _client;

  void _bind(http.Client c) => _client = c;

  void cancel() {
    cancelled = true;
    _client?.close(); // 立即断开, 不等下一段
  }
}

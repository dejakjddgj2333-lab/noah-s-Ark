import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../state/auth_store.dart';
import '../theme.dart';
import '../widgets/kit.dart';

/// AI 助手页: 左对话 (DeepSeek SSE 流式) + 右每日综述 (对齐 web /ai)。
/// 对话按用户存 SharedPreferences, 重启不丢 (最多留 50 条)。
class AiPage extends StatefulWidget {
  const AiPage({super.key});

  @override
  State<AiPage> createState() => _AiPageState();
}

class _Msg {
  _Msg(this.role, [this.content = '']);
  final String role; // user | assistant
  String content;
  Map<String, String> toJson() => {'role': role, 'content': content};
}

class _AiPageState extends State<AiPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _msgs = [];
  bool _sending = false;
  CancelToken? _cancel;

  Map<String, dynamic>? _summary; // {date, text, cached}
  bool _summaryLoading = true;

  static const _maxKeep = 50;
  String get _lsKey =>
      'ai_chat_${AuthStore.I.user?['id'] ?? 'anon'}';

  static const _quicks = [
    '今天市场怎么样?',
    'BTC 现在怎么看?',
    '最近有什么重要新闻?',
    '恐慌贪婪指数说明什么?',
  ];

  @override
  void initState() {
    super.initState();
    _restore();
    _loadSummary();
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---------- 持久化 ----------
  Future<void> _restore() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_lsKey);
      if (raw == null) return;
      final list = jsonDecode(raw);
      if (list is List) {
        setState(() {
          for (final m in list) {
            if (m is Map &&
                (m['role'] == 'user' || m['role'] == 'assistant') &&
                m['content'] is String) {
              _msgs.add(_Msg(m['role'] as String, m['content'] as String));
            }
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final keep = _msgs.length > _maxKeep
          ? _msgs.sublist(_msgs.length - _maxKeep)
          : _msgs;
      await sp.setString(
          _lsKey, jsonEncode(keep.map((m) => m.toJson()).toList()));
    } catch (_) {}
  }

  // ---------- 每日综述 ----------
  Future<void> _loadSummary() async {
    setState(() => _summaryLoading = true);
    try {
      final res = await ApiClient.I.aiDailySummary();
      if (res is Map && res['text'] != null) {
        _summary = Map<String, dynamic>.from(res);
      } else {
        _summary = null;
      }
    } catch (_) {
      _summary = null;
    }
    if (mounted) setState(() => _summaryLoading = false);
  }

  // ---------- 对话 ----------
  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    setState(() {
      _msgs.add(_Msg('user', text));
      _msgs.add(_Msg('assistant'));
      _sending = true;
    });
    _scrollBottom();
    // 历史不含刚推入的两条, 最多 5 轮
    final history = _msgs
        .sublist(0, _msgs.length - 2)
        .reversed
        .take(10)
        .toList()
        .reversed
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();
    _cancel = CancelToken();
    try {
      await ApiClient.I.aiChatStream(
        message: text,
        history: history,
        onDelta: (d) {
          if (!mounted) return;
          setState(() => _msgs.last.content += d);
          _scrollBottom();
        },
        cancelToken: _cancel,
      );
      if (_msgs.last.content.isEmpty) {
        _msgs.last.content = '(AI 暂时没说话, 换个问法试试)';
      }
    } catch (e) {
      if (!(e is DioException && CancelToken.isCancel(e))) {
        final last = _msgs.last;
        last.content = last.content.isEmpty
            ? '(连接失败: ${e is ApiException ? e.message : '网络错误'})'
            : last.content;
      }
    } finally {
      if (mounted) setState(() => _sending = false);
      _cancel = null;
      _persist();
    }
  }

  void _stop() => _cancel?.cancel();

  void _clearAll() {
    if (_sending) return;
    setState(() => _msgs.clear());
    _persist();
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: _buildChat()),
        const SizedBox(width: 14),
        SizedBox(width: 320, child: _buildSummary()),
      ]),
    );
  }

  // ---------- 左: 对话 ----------
  Widget _buildChat() {
    return McCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        _panelHead(
          icon: Icons.smart_toy_outlined,
          title: '明策 AI 助手',
          sub: '数据实时注入 · AI 只做解读',
          trailing: IconButton(
            tooltip: '清空对话',
            icon: const Icon(Icons.delete_sweep_outlined,
                size: 16, color: Mc.muted),
            onPressed: _sending || _msgs.isEmpty ? null : _clearAll,
          ),
        ),
        Expanded(
          child: _msgs.isEmpty
              ? _emptyState()
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: _msgs.length,
                  itemBuilder: (_, i) => _bubble(_msgs[i]),
                ),
        ),
        _inputBar(),
      ]),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.smart_toy_outlined, size: 40, color: Mc.cobaltSoft),
          const SizedBox(height: 10),
          Text('问点什么吧', style: Mc.display(14)),
          const SizedBox(height: 4),
          Text('行情、指标、新闻都在它脑子里 (实时注入)',
              style: Mc.body(12, color: Mc.muted)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center,
              children: [
            for (final q in _quicks)
              InkWell(
                onTap: () => _send(q),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Mc.canvas,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Mc.hairline),
                  ),
                  child: Text(q, style: Mc.body(12, color: Mc.muted)),
                ),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _bubble(_Msg m) {
    final isUser = m.role == 'user';
    final thinking =
        !isUser && m.content.isEmpty && _sending && m == _msgs.last;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.42),
        decoration: BoxDecoration(
          color: isUser ? Mc.cobalt.withValues(alpha: 0.2) : Mc.canvas,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isUser ? 12 : 3),
            bottomRight: Radius.circular(isUser ? 3 : 12),
          ),
          border: Border.all(
              color: isUser ? Mc.cobalt.withValues(alpha: 0.4) : Mc.hairline),
        ),
        child: thinking
            ? Text('思考中…', style: Mc.mono(12, color: Mc.muted))
            : SelectableText.rich(_mdLite(m.content),
                style: Mc.body(14,
                    color: isUser ? Mc.ink : Mc.muted)),
      ),
    );
  }

  /// 极简 markdown: **加粗** 转高亮, 其余原样
  TextSpan _mdLite(String s) {
    final parts = s.split('**');
    final spans = <InlineSpan>[];
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      spans.add(TextSpan(
        text: parts[i],
        style: i.isOdd
            ? const TextStyle(fontWeight: FontWeight.w700, color: Mc.ink)
            : null,
      ));
    }
    return TextSpan(children: spans);
  }

  Widget _inputBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Mc.hairline))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              onSubmitted: (_) => _send(),
              style: Mc.body(13),
              decoration: InputDecoration(
                hintText: '问行情、问指标、问新闻…',
                hintStyle: Mc.body(13, color: Mc.muted.withValues(alpha: 0.5)),
                isDense: true,
                filled: true,
                fillColor: Mc.canvas,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Mc.hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Mc.hairline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      BorderSide(color: Mc.cobalt.withValues(alpha: 0.6)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (_sending)
            McButton('停止',
                kind: McBtnKind.danger,
                height: 38,
                icon: Icons.stop,
                onPressed: _stop)
          else
            McButton('发送', height: 38, icon: Icons.send, onPressed: _send),
        ]),
        const SizedBox(height: 6),
        Text('AI 解读仅供参考, 不构成投资建议',
            style: Mc.mono(11, color: Mc.muted.withValues(alpha: 0.6))),
      ]),
    );
  }

  // ---------- 右: 每日综述 ----------
  Widget _buildSummary() {
    return McCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _panelHead(
          icon: Icons.today_outlined,
          title: '今日市场综述',
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (_summary?['cached'] == true)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: McBadge('已缓存', color: Mc.muted),
              ),
            IconButton(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh, size: 15, color: Mc.muted),
              onPressed: _loadSummary,
            ),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _summaryLoading
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                        child: Text('AI 生成中, 稍候…',
                            style: Mc.mono(11, color: Mc.muted))))
                : _summary == null
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                            child: Text('综述暂不可用',
                                style: Mc.mono(11, color: Mc.muted))))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_summary!['date']?.toString() ?? '',
                              style: Mc.mono(11, color: Mc.muted)),
                          const SizedBox(height: 8),
                          SelectableText.rich(
                              _mdLite(_summary!['text']?.toString() ?? ''),
                              style: Mc.body(13, color: Mc.muted)),
                        ],
                      ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Mc.hairline))),
          child: Text('每天首次访问生成一次, 全日共享',
              style: Mc.mono(11, color: Mc.muted.withValues(alpha: 0.6))),
        ),
      ]),
    );
  }

  Widget _panelHead({
    required IconData icon,
    required String title,
    String? sub,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Mc.hairline))),
      child: Row(children: [
        Icon(icon, size: 16, color: Mc.cobaltSoft),
        const SizedBox(width: 8),
        Text(title, style: Mc.display(14)),
        if (sub != null) ...[
          const SizedBox(width: 10),
          Flexible(
            child: Text(sub,
                overflow: TextOverflow.ellipsis,
                style: Mc.mono(11, color: Mc.muted)),
          ),
        ],
        const Spacer(),
        ?trailing,
      ]),
    );
  }
}

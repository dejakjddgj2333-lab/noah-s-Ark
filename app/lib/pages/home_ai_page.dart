import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/ai_api.dart';
import '../services/api.dart';
import '../services/auth.dart';

/// AI 助手 (首页 tab) — 对话 (SSE 流式) + 今日综述折叠卡.
/// 对齐 web /ai 与 desktop AiPage; 对话按用户存本机 (最多 50 条).
class HomeAiPage extends StatefulWidget {
  const HomeAiPage({super.key});

  @override
  State<HomeAiPage> createState() => _HomeAiPageState();
}

class _Msg {
  _Msg(this.role, [this.content = '']);
  final String role; // user | assistant
  String content;
  Map<String, String> toJson() => {'role': role, 'content': content};
}

class _HomeAiPageState extends State<HomeAiPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _msgs = [];
  bool _sending = false;
  AiChatCancel? _cancel;

  Map<String, dynamic>? _summary; // {date, text, cached}
  bool _summaryLoading = false;
  bool _summaryOpen = false;

  static const _maxKeep = 50;
  String get _lsKey => 'ai_chat_${AuthStore.instance.userId ?? 0}';
  String get _token => AuthStore.instance.token ?? '';
  String get _lang => L10n.instance.code;

  List<String> get _quicks =>
      [tr('ai_q1'), tr('ai_q2'), tr('ai_q3'), tr('ai_q4')];

  @override
  void initState() {
    super.initState();
    if (AuthStore.instance.loggedIn) {
      _restore();
      _loadSummary();
    }
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
      if (list is List && mounted) {
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
      final res = await AiApi.dailySummary(_token, lang: _lang);
      _summary = res['text'] != null ? res : null;
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
    final cancel = AiChatCancel();
    _cancel = cancel;
    try {
      await AiApi.chatStream(
        token: _token,
        message: text,
        history: history,
        lang: _lang,
        cancel: cancel,
        onDelta: (d) {
          if (!mounted) return;
          setState(() => _msgs.last.content += d);
          _scrollBottom();
        },
      );
      if (_msgs.last.content.isEmpty && !cancel.cancelled) {
        _msgs.last.content = tr('ai_empty_reply');
      }
    } catch (e) {
      if (!cancel.cancelled) {
        final last = _msgs.last;
        if (last.content.isEmpty) {
          last.content =
              '(${tr('ai_conn_fail')}: ${e is ApiException ? e.message : 'network'})';
        }
      }
    } finally {
      if (mounted) setState(() => _sending = false);
      _cancel = null;
      _persist();
    }
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
    if (!AuthStore.instance.loggedIn) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_outline, size: 40, color: McColors.primarySoft),
          const SizedBox(height: 12),
          Text(tr('login_gate_title').replaceAll('{name}', tr('ai_title')),
              style: McText.sans(size: 14, color: McColors.onSurfaceVariant)),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: () => Navigator.pushNamed(context, '/login'),
            style: ElevatedButton.styleFrom(
              backgroundColor: McColors.primaryContainer,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: Text(tr('go_login'), style: McText.sans(size: 13)),
          ),
        ]),
      );
    }
    return Column(children: [
      _summaryCard(),
      Expanded(
        child: _msgs.isEmpty
            ? _emptyState()
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                itemCount: _msgs.length,
                itemBuilder: (_, i) => _bubble(_msgs[i]),
              ),
      ),
      _inputBar(),
    ]);
  }

  // ---------- 今日综述折叠卡 ----------
  Widget _summaryCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: McCard(
        padding: EdgeInsets.zero,
        onTap: () => setState(() => _summaryOpen = !_summaryOpen),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              const Icon(Icons.today_outlined,
                  size: 16, color: McColors.primarySoft),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr('ai_summary_title'),
                    style: McText.sans(
                        size: 13,
                        weight: FontWeight.w700,
                        color: McColors.onSurface)),
              ),
              if (_summaryLoading)
                Text(tr('ai_generating'),
                    style: McText.mono(
                        size: 10, color: McColors.onSurfaceVariant))
              else
                Icon(
                  _summaryOpen
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                  color: McColors.onSurfaceVariant,
                ),
            ]),
          ),
          if (_summaryOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: _summary == null
                  ? Text(tr('ai_summary_unavailable'),
                      style: McText.sans(
                          size: 12, color: McColors.onSurfaceVariant))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_summary!['date']?.toString() ?? '',
                            style: McText.mono(
                                size: 10, color: McColors.onSurfaceVariant)),
                        const SizedBox(height: 6),
                        Text.rich(
                          _mdLite(_summary!['text']?.toString() ?? ''),
                          style: McText.sans(
                              size: 12,
                              height: 1.6,
                              color: McColors.onSurfaceVariant),
                        ),
                      ],
                    ),
            ),
        ]),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.smart_toy_outlined,
              size: 40, color: McColors.primarySoft),
          const SizedBox(height: 10),
          Text(tr('ai_ask_something'),
              style: McText.display(size: 15, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(tr('ai_ask_hint'),
              textAlign: TextAlign.center,
              style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center,
              children: [
            for (final q in _quicks)
              GestureDetector(
                onTap: () => _send(q),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: McColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color:
                            McColors.outlineVariant.withValues(alpha: 0.6)),
                  ),
                  child: Text(q,
                      style: McText.sans(
                          size: 12, color: McColors.onSurfaceVariant)),
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
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isUser
              ? McColors.primaryContainer.withValues(alpha: 0.25)
              : McColors.surfaceContainerLow,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 14),
          ),
          border: Border.all(
              color: isUser
                  ? McColors.primaryContainer.withValues(alpha: 0.4)
                  : McColors.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: thinking
            ? Text(tr('ai_thinking'),
                style:
                    McText.mono(size: 12, color: McColors.onSurfaceVariant))
            : Text.rich(
                _mdLite(m.content),
                style: McText.sans(
                    size: 14,
                    height: 1.5,
                    color: isUser
                        ? McColors.onSurface
                        : McColors.onSurfaceVariant),
              ),
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
            ? const TextStyle(
                fontWeight: FontWeight.w700, color: McColors.onSurface)
            : null,
      ));
    }
    return TextSpan(children: spans);
  }

  Widget _inputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, 8 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: McColors.surface.withValues(alpha: 0.9),
        border: Border(
          top: BorderSide(
              color: McColors.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              onSubmitted: (_) => _send(),
              style: McText.sans(size: 14, color: McColors.onSurface),
              decoration: InputDecoration(
                hintText: tr('ai_input_hint'),
                hintStyle: McText.sans(
                    size: 13,
                    color: McColors.onSurfaceVariant.withValues(alpha: 0.6)),
                isDense: true,
                filled: true,
                fillColor: McColors.surfaceContainerLow,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                      color: McColors.outlineVariant.withValues(alpha: 0.6)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                      color: McColors.outlineVariant.withValues(alpha: 0.6)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                      color:
                          McColors.primaryContainer.withValues(alpha: 0.7)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 38,
            child: ElevatedButton.icon(
              onPressed: _sending ? () => _cancel?.cancel() : _send,
              icon: Icon(_sending ? Icons.stop : Icons.send, size: 15),
              label: Text(_sending ? tr('ai_stop') : tr('ai_send'),
                  style:
                      McText.sans(size: 12, weight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _sending
                    ? McColors.error.withValues(alpha: 0.8)
                    : McColors.primaryContainer,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Text(tr('ai_disclaimer'),
            style: McText.mono(
                size: 10,
                color: McColors.onSurfaceVariant.withValues(alpha: 0.6))),
      ]),
    );
  }
}

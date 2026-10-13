/// App 内协议页: 调后端 /api/legal/{terms|privacy} 取 HTML, 富文本渲染.
/// 不跳外部浏览器. 深色主题适配.
library;

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:http/http.dart' as http;

import '../core/l10n.dart';
import '../core/theme.dart';
import '../services/api.dart';

class LegalPage extends StatefulWidget {
  const LegalPage({super.key, required this.docKey});

  /// 'terms' 用户协议 / 'privacy' 隐私政策.
  final String docKey;

  static void open(BuildContext context, String docKey) {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => LegalPage(docKey: docKey)));
  }

  @override
  State<LegalPage> createState() => _LegalPageState();
}

class _LegalPageState extends State<LegalPage> {
  String? _html;
  bool _failed = false;

  String get _title =>
      widget.docKey == 'privacy' ? tr('login_privacy') : tr('login_terms');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final resp = await http
          .get(Uri.parse('${McApi.baseUrl}/api/legal/${widget.docKey}'));
      if (resp.statusCode == 200) {
        if (mounted) setState(() => _html = resp.body);
      } else {
        if (mounted) setState(() => _failed = true);
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: McColors.surface,
      appBar: AppBar(
        backgroundColor: McColors.surface,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: McColors.onSurface),
        title: Text(
          // 去掉书名号显示更干净
          _title.replaceAll('《', '').replaceAll('》', ''),
          style: McText.sans(size: 15, weight: FontWeight.w600),
        ),
      ),
      body: _html == null
          ? Center(
              child: _failed
                  ? Text(tr('login_err_network'),
                      style:
                          McText.sans(size: 13, color: McColors.onSurfaceVariant))
                  : const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              child: Html(
                data: _html,
                style: {
                  'body': Style(
                    margin: Margins.zero,
                    padding: HtmlPaddings.zero,
                    backgroundColor: McColors.surface,
                    color: McColors.onSurface,
                    fontSize: FontSize(14),
                    lineHeight: const LineHeight(1.7),
                  ),
                  'h1': Style(
                    fontSize: FontSize(20),
                    fontWeight: FontWeight.w700,
                    color: McColors.onSurface,
                    textAlign: TextAlign.center,
                  ),
                  'h2': Style(
                    fontSize: FontSize(16),
                    fontWeight: FontWeight.w600,
                    color: McColors.onSurface,
                    margin: Margins.only(top: 20, bottom: 6),
                  ),
                  'h3': Style(
                    fontSize: FontSize(14),
                    fontWeight: FontWeight.w600,
                    color: McColors.onSurface,
                  ),
                  'a': Style(color: McColors.primary),
                  'em': Style(color: McColors.onSurfaceVariant),
                },
              ),
            ),
    );
  }
}

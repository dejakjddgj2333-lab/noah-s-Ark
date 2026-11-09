/// 资讯正文/摘要 HTML → 纯文本 (对齐 web-terminal src/utils/htmlText.js).
/// 背景: apitube 采集的 content 是整段 HTML, 旧渲染当纯文本 + 全局删 `>` 字符,
/// 导致残缺标签整段露出. 这里宽容降级为可读文本: 丢图片/链接, 只留文字 (封面走 cover_url).
library;

final RegExp _dropBlockRe = RegExp(
  r'<(bi-shortcode|script|style)\b[\s\S]*?</\1>',
  caseSensitive: false,
);

final RegExp _blockRe = RegExp(
  r'</?(?:p|div|li|ul|ol|h[1-6]|blockquote|section|article|header|footer|table|thead|tbody|tr|td|th|figure|figcaption|hr|br)\b[^>]*>',
  caseSensitive: false,
);

final RegExp _tagRe = RegExp(r'</?[a-zA-Z][^>]*>?');

const Map<String, String> _namedEntities = {
  'nbsp': ' ',
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'copy': '©',
  'reg': '®',
  'trade': '™',
  'mdash': '—',
  'ndash': '–',
  'hellip': '…',
  'laquo': '«',
  'raquo': '»',
  'times': '×',
  'middot': '·',
};

String htmlToText(Object? html) {
  var s = html?.toString() ?? '';
  if (s.isEmpty || (!s.contains('<') && !s.contains('&'))) return s.trim();
  s = s.replaceAll(_dropBlockRe, '');
  s = s.replaceAll(_blockRe, '\n');
  s = s.replaceAll(_tagRe, '');
  // 数字实体 &#123; / &#x1F600;
  s = s.replaceAllMapped(RegExp(r'&#(x?[0-9a-fA-F]+);'), (m) {
    final code = m[1]!;
    final cp = code.toLowerCase().startsWith('x')
        ? int.tryParse(code.substring(1), radix: 16)
        : int.tryParse(code);
    if (cp == null || cp < 0 || cp > 0x10FFFF) return '';
    try {
      return String.fromCharCode(cp);
    } catch (_) {
      return '';
    }
  });
  // 命名实体
  s = s.replaceAllMapped(
    RegExp(r'&([a-zA-Z]+);'),
    (m) => _namedEntities[m[1]!.toLowerCase()] ?? '',
  );
  // 采集/翻译管道偶发编码损坏: 替换符与孤立代理项抹掉 (手动扫描, 避开正则 lookbehind)
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c >= 0xD800 && c <= 0xDBFF) {
      // 高代理项: 仅当后面跟着低代理项才保留 (合法字符对)
      if (i + 1 < s.length) {
        final d = s.codeUnitAt(i + 1);
        if (d >= 0xDC00 && d <= 0xDFFF) {
          buf.writeCharCode(c);
          buf.writeCharCode(d);
          i++;
        }
      }
    } else if (c >= 0xDC00 && c <= 0xDFFF) {
      // 孤立低代理项: 丢弃
    } else if (c != 0xFFFD) {
      buf.writeCharCode(c);
    }
  }
  return buf
      .toString()
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((l) => l.isNotEmpty)
      .join('\n\n');
}

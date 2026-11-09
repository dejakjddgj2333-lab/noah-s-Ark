// 资讯正文/摘要 HTML → 纯文本.
// 背景: apitube 采集的 content 是整段 HTML (含 <p>/<a>/<img>/自定义 bi-shortcode 与实体),
// 旧渲染把正文当纯文本 + 全局删 `>` 字符, 导致残缺标签整段露出. 这里宽容降级为可读文本:
// 丢图片/链接, 只留文字 (封面走 cover_url). 桌面端对齐实现见 desktop/lib/utils/html_text.dart.

// bi-shortcode / script / style 整块丢弃 (含占位文本 "摘要列表位置" 等)
const DROP_BLOCK_RE =
  /<(bi-shortcode|script|style)\b[\s\S]*?<\/\1>/gi
// 块级标签边界 → 换行
const BLOCK_RE =
  /<\/?(?:p|div|li|ul|ol|h[1-6]|blockquote|section|article|header|footer|table|thead|tbody|tr|td|th|figure|figcaption|hr|br)\b[^>]*>/gi
// 其余所有标签 (含截断的残缺尾标签)
const TAG_RE = /<\/?[a-zA-Z][^>]*>?/g

const NAMED_ENTITIES = {
  nbsp: ' ', amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", copy: '©',
  reg: '®', trade: '™', mdash: '—', ndash: '–', hellip: '…',
  laquo: '«', raquo: '»', times: '×', middot: '·',
}

export function htmlToText(html) {
  let s = (html ?? '').toString()
  if (!s || !/[<&]/.test(s)) return s.trim()
  s = s.replace(DROP_BLOCK_RE, '')
  s = s.replace(BLOCK_RE, '\n')
  s = s.replace(TAG_RE, '')
  s = s.replace(/&#(x?[0-9a-fA-F]+);/g, (m, code) => {
    const cp = code[0].toLowerCase() === 'x' ? parseInt(code.slice(1), 16) : parseInt(code, 10)
    if (!Number.isFinite(cp) || cp < 0 || cp > 0x10ffff) return ''
    try { return String.fromCodePoint(cp) } catch { return '' }
  })
  s = s.replace(/&([a-zA-Z]+);/g, (m, name) => NAMED_ENTITIES[name.toLowerCase()] ?? '')
  // 采集/翻译管道偶发编码损坏: 替换符与孤立代理项直接抹掉
  s = s.replace(new RegExp('\\uFFFD', 'g'), '')
  s = s.replace(/[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/g, '')
  return s
    .split('\n')
    .map((l) => l.replace(/\s+/g, ' ').trim())
    .filter(Boolean)
    .join('\n\n')
}

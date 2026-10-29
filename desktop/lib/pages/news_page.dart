import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/kit.dart';
import '../widgets/shell.dart';
import 'market_detail_page.dart';

/// 打开资讯原文外链(空值直接忽略)。
Future<void> _openSourceUrl(dynamic raw) async {
  final url = raw?.toString().trim() ?? '';
  if (url.isEmpty) return;
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// 从标题/摘要/正文提取高关联标的 (对齐 NewsDetail.vue relatedCoins)。
List<String> relatedCoinsOf(Map article) {
  final text =
      '${article['title'] ?? ''} ${article['summary'] ?? ''} ${article['content'] ?? ''}';
  final found = RegExp(r'\b(BTC|ETH|SOL|BNB|XRP|DOGE|ADA|SUI|OKB|LTC)\b',
          caseSensitive: false)
      .allMatches(text)
      .map((m) => m.group(0)!.toUpperCase());
  return found.toSet().take(3).toList();
}

/// 摘要情绪倾向标签 (对齐 NewsDetail.vue sentiText)。
String sentiTextOf(dynamic s) =>
    s == 'positive' ? '偏多' : s == 'negative' ? '偏空' : s != null ? '中性' : '--';

/// 全屏资讯文章页: 供顶栏铃铛/概览资讯流 ShellRouter.push 使用。
/// 内容复用 [_ArticlePanel] (正文 + 互动区 + 评论), 宽屏右侧挂情报三卡。
class NewsArticleOverlay extends StatelessWidget {
  const NewsArticleOverlay({super.key, required this.id});
  final int id;

  @override
  Widget build(BuildContext context) => _NewsArticleLoader(id: id);
}

/// 按 id 拉取资讯详情并渲染整页。
class _NewsArticleLoader extends StatefulWidget {
  const _NewsArticleLoader({required this.id});
  final int id;

  @override
  State<_NewsArticleLoader> createState() => _NewsArticleLoaderState();
}

class _NewsArticleLoaderState extends State<_NewsArticleLoader> {
  Map<String, dynamic>? _article;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.I.newsDetail(widget.id);
      if (!mounted) return;
      setState(() {
        _article = res is Map ? Map<String, dynamic>.from(res) : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _openArticle(int id) {
    if (id == widget.id) return;
    ShellRouter.I.push('资讯详情', 'NEWS', NewsArticleOverlay(id: id));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const McLoading(label: '加载详情中');
    if (_error != null) return McError('详情加载失败', onRetry: _load);
    final a = _article;
    if (a == null) return const McEmpty('资讯不存在');
    final catName =
        _NewsPageState._catName[a['category']] ?? a['category']?.toString();
    final catColor =
        _NewsPageState._catColor[a['category']] ?? Mc.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(children: [
        const SizedBox(height: 20),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth >= 1000;
            final panel = _ArticlePanel(
              key: ValueKey(a['id']),
              article: a,
              catName: catName,
              catColor: catColor,
              onOpenArticle: _openArticle,
              // 窄屏三卡并到面板底部, 宽屏挂右栏
              showSideCards: !wide,
            );
            if (!wide) return panel;
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: panel),
              const SizedBox(width: 20),
              SizedBox(
                width: 320,
                child: ListView(children: [
                  const _SentimentCard(),
                  const SizedBox(height: 16),
                  _RelatedCard(article: a, onOpen: _openArticle),
                  const SizedBox(height: 16),
                  _AssetRadarCard(article: a),
                ]),
              ),
            ]);
          }),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }
}

/// 「查看原文」链接文字(Cobalt Soft + open_in_new 小图标)。
class _SourceLink extends StatelessWidget {
  const _SourceLink({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openSourceUrl(url),
      borderRadius: BorderRadius.circular(6),
      hoverColor: Mc.cardHigh.withValues(alpha: 0.6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('查看原文', style: Mc.body(12, w: FontWeight.w500, color: Mc.cobaltSoft)),
          const SizedBox(width: 4),
          const Icon(Icons.open_in_new, size: 13, color: Mc.cobaltSoft),
        ]),
      ),
    );
  }
}

/// 资讯页: 宽屏为 [列表+详情 7 | 右栏(热榜+宏观日历) 5], 窄屏回退为主从双栏。
class NewsPage extends StatefulWidget {
  const NewsPage({super.key});

  @override
  State<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> {
  static const _cats = [
    (key: '', name: '全部', en: 'ALL'),
    (key: 'flash', name: '快讯', en: 'FLASH'),
    (key: 'news', name: '新闻', en: 'NEWS'),
    (key: 'research', name: '深度', en: 'INSIGHTS'),
    (key: 'notice', name: '公告', en: 'NOTICE'),
  ];
  static const _catName = {
    'flash': '快讯',
    'news': '新闻',
    'research': '深度',
    'notice': '公告',
  };
  static const _catColor = {
    'flash': Mc.cobalt,
    'news': Mc.bull,
    'research': Mc.amber,
    'notice': Mc.bear,
  };
  static const _pageSize = 20;

  String _cat = '';
  int _page = 1;
  int _total = 0;
  List<dynamic> _items = [];
  bool _loading = true;
  String? _error;

  int? _selectedId;
  Map<String, dynamic>? _article;
  bool _detailLoading = false;
  String? _detailError;

  int get _lastPage => (_total / _pageSize).ceil().clamp(1, 1 << 31);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.I.newsList({
        if (_cat.isNotEmpty) 'category': _cat,
        'page': _page,
        'page_size': _pageSize,
      });
      if (!mounted) return;
      final items = (res is Map ? res['items'] : null);
      setState(() {
        _items = items is List ? items : [];
        _total = Fmt.toNum(res is Map ? res['total'] : null)?.toInt() ?? 0;
        _loading = false;
      });
      // 自动选中首条, 或当前选中项已不在列表时改选首条
      if (_items.isNotEmpty &&
          !_items.any((e) => e is Map && e['id'] == _selectedId)) {
        _select(_items.first as Map);
      } else if (_items.isEmpty) {
        _selectedId = null;
        _article = null;
        _detailError = null;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _select(Map item) async {
    final id = Fmt.toNum(item['id'])?.toInt();
    if (id == null) return;
    setState(() {
      _selectedId = id;
      _article = null;
      _detailError = null;
      _detailLoading = true;
    });
    try {
      final res = await ApiClient.I.newsDetail(id);
      if (!mounted || _selectedId != id) return;
      setState(() {
        _article = res is Map ? Map<String, dynamic>.from(res) : null;
        _detailLoading = false;
      });
    } catch (e) {
      if (!mounted || _selectedId != id) return;
      setState(() {
        _detailLoading = false;
        _detailError = e.toString();
      });
    }
  }

  void _switchCat(String c) {
    if (c == _cat) return;
    _cat = c;
    _page = 1;
    _selectedId = null;
    _article = null;
    _load();
  }

  void _goPage(int p) {
    if (p < 1 || p > _lastPage || p == _page) return;
    _page = p;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 20),
        McSection('即时资讯',
            tag: 'NEWS WIRE',
            trailing: Row(children: [
              Text('共 $_total 条', style: Mc.mono(11, color: Mc.muted)),
              const SizedBox(width: 12),
              McButton('刷新',
                  kind: McBtnKind.ghost,
                  height: 32,
                  icon: Icons.refresh,
                  busy: _loading,
                  onPressed: _load),
            ])),
        const SizedBox(height: 14),
        _CatTabs(
            cats: _cats, current: _cat, total: _total, onTap: _switchCat),
        const SizedBox(height: 14),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            // 主从区: 左列表 + 右详情面板 (原有逻辑不变); 宽屏带右栏时列表收窄
            final wide = c.maxWidth >= 1020;
            final master = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: wide ? 320 : 380, child: _buildList()),
                  const SizedBox(width: 24),
                  Expanded(child: _buildDetail()),
                ]);
            // 窄屏回退: 不显示右栏 (默认窗口 1440 下内容区约 1150)
            if (c.maxWidth < 1020) return master;
            // 宽屏: [主从 自适应 | 右栏固定 340]
            // 注: 不用 McRow(IntrinsicHeight), 子树含 ListView 无法求固有高度。
            return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: master),
                  const SizedBox(width: 20),
                  const SizedBox(width: 340, child: _NewsSidebar()),
                ]);
          }),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _buildList() {
    if (_loading && _items.isEmpty) return const McLoading(label: '加载资讯中');
    if (_error != null && _items.isEmpty) {
      return McError('资讯加载失败', onRetry: _load);
    }
    if (_items.isEmpty) return const McEmpty('暂无资讯');
    return Column(children: [
      Expanded(
        child: ListView.separated(
          itemCount: _items.length,
          separatorBuilder: (_, _) =>
              const Divider(height: 12, color: Colors.transparent),
          itemBuilder: (_, i) {
            final n = _items[i] as Map;
            final id = Fmt.toNum(n['id'])?.toInt();
            return _NewsCard(
              item: n,
              selected: id == _selectedId,
              catName: _catName[n['category']] ?? n['category']?.toString(),
              catColor: _catColor[n['category']] ?? Mc.muted,
              onTap: () => _select(n),
            );
          },
        ),
      ),
      const SizedBox(height: 10),
      Container(
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Mc.hairline, width: 1))),
        padding: const EdgeInsets.only(top: 10),
        child: Row(children: [
          Expanded(
            child: Text(
              _total == 0
                  ? '0-0 / 0'
                  : '${(_page - 1) * _pageSize + 1}-${(_page * _pageSize).clamp(0, _total)} / $_total',
              style: Mc.mono(11, color: Mc.muted),
            ),
          ),
          _PageBtn(
              icon: Icons.chevron_left,
              enabled: _page > 1,
              onTap: () => _goPage(_page - 1)),
          const SizedBox(width: 6),
          Text('$_page / $_lastPage', style: Mc.mono(11)),
          const SizedBox(width: 6),
          _PageBtn(
              icon: Icons.chevron_right,
              enabled: _page < _lastPage,
              onTap: () => _goPage(_page + 1)),
        ]),
      ),
    ]);
  }

  Widget _buildDetail() {
    if (_selectedId == null) return const McEmpty('选择左侧资讯查看详情');
    if (_detailLoading) return const McLoading(label: '加载详情中');
    if (_detailError != null) {
      return McError('详情加载失败', onRetry: () {
        final item = _items.whereType<Map>().firstWhere(
            (e) => Fmt.toNum(e['id'])?.toInt() == _selectedId,
            orElse: () => {'id': _selectedId});
        _select(item);
      });
    }
    final a = _article;
    if (a == null) return const McEmpty('资讯不存在');
    return _ArticlePanel(
      key: ValueKey(a['id']),
      article: a,
      catName: _catName[a['category']] ?? a['category']?.toString(),
      catColor: _catColor[a['category']] ?? Mc.muted,
      onOpenArticle: (rid) => _select({'id': rid}),
    );
  }
}

/// 分类下划线 tab 栏。
class _CatTabs extends StatelessWidget {
  const _CatTabs(
      {required this.cats,
      required this.current,
      required this.total,
      required this.onTap});
  final List<({String key, String name, String en})> cats;
  final String current;
  final int total;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          border:
              Border(bottom: BorderSide(color: Mc.hairline, width: 1))),
      child: Row(
        children: [
          for (final c in cats)
            GestureDetector(
              onTap: () => onTap(c.key),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 2,
                      color:
                          current == c.key ? Mc.cobalt : Colors.transparent,
                    ),
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(c.name,
                      style: Mc.body(13,
                          w: current == c.key
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color:
                              current == c.key ? Mc.ink : Mc.muted)),
                  const SizedBox(width: 6),
                  Text(
                    current == c.key && c.key.isEmpty ? '$total' : c.en,
                    style: Mc.tag(
                        color: current == c.key
                            ? Mc.cobaltSoft
                            : Mc.muted.withValues(alpha: 0.6)),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

/// 左侧资讯卡片: 悬停显示收藏按钮, 底部展示收藏数 (对齐 News.vue:219-226,238)。
class _NewsCard extends StatefulWidget {
  const _NewsCard(
      {required this.item,
      required this.selected,
      required this.catName,
      required this.catColor,
      required this.onTap});
  final Map item;
  final bool selected;
  final String? catName;
  final Color catColor;
  final VoidCallback onTap;

  @override
  State<_NewsCard> createState() => _NewsCardState();
}

class _NewsCardState extends State<_NewsCard> {
  bool _hover = false;
  bool _favBusy = false;
  int? _favCount; // 本地覆盖值 (收藏成功后 +1)

  /// 行内快捷收藏 (对齐 News.vue favRow: 成功后收藏数 +1, 不做取消)。
  Future<void> _fav() async {
    final id = Fmt.toNum(widget.item['id'])?.toInt();
    if (id == null || _favBusy) return;
    _favBusy = true;
    try {
      await ApiClient.I.interact('favorite', 'news', id);
      if (!mounted) return;
      setState(() {
        _favCount =
            (_favCount ?? Fmt.toNum(widget.item['favorite_count'])?.toInt() ?? 0) + 1;
      });
    } catch (_) {
      // 401 由全局处理, 其余静默
    } finally {
      _favBusy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final title = item['title']?.toString() ?? '';
    final summary = item['summary']?.toString() ?? '';
    final source = item['source']?.toString();
    final sourceUrl = item['source_url']?.toString().trim() ?? '';
    final favCount =
        _favCount ?? Fmt.toNum(item['favorite_count'])?.toInt() ?? 0;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: widget.selected ? Mc.cardHigh : Mc.card,
        borderRadius: BorderRadius.circular(Mc.cardRadius),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(Mc.cardRadius),
          hoverColor: Mc.cardHigh.withValues(alpha: 0.6),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Mc.cardRadius),
              border: Border.all(
                  color: widget.selected ? Mc.cobalt : Mc.hairline, width: 1),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    if (widget.catName != null) ...[
                      McBadge(widget.catName!, color: widget.catColor),
                      const SizedBox(width: 8),
                    ],
                    // 悬停快捷操作: 收藏 (对齐 News.vue hover actions)
                    if (_hover) ...[
                      InkWell(
                        onTap: _fav,
                        borderRadius: BorderRadius.circular(4),
                        hoverColor: Mc.cardHigh,
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(Icons.bookmark_border,
                              size: 14, color: Mc.cobaltSoft),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        Fmt.ago(item['publish_at']),
                        textAlign: TextAlign.right,
                        style: Mc.mono(10, color: Mc.muted),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Mc.display(14)),
                  if (summary.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Mc.body(12, color: Mc.muted)),
                  ],
                  const SizedBox(height: 10),
                  Container(
                    decoration: const BoxDecoration(
                        border: Border(
                            top: BorderSide(color: Mc.hairline, width: 0.5))),
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(children: [
                      Text(source ?? '快讯', style: Mc.body(11, color: Mc.ink)),
                      const Spacer(),
                      if (Fmt.toNum(item['like_count']) != null &&
                          Fmt.toNum(item['like_count'])! > 0)
                        Text('赞 ${item['like_count']}',
                            style: Mc.mono(10, color: Mc.muted)),
                      if (Fmt.toNum(item['comment_count']) != null &&
                          Fmt.toNum(item['comment_count'])! > 0) ...[
                        const SizedBox(width: 10),
                        Text('评论 ${item['comment_count']}',
                            style: Mc.mono(10, color: Mc.muted)),
                      ],
                      if (favCount > 0) ...[
                        const SizedBox(width: 10),
                        Text('收藏 $favCount',
                            style: Mc.mono(10, color: Mc.cobaltSoft)),
                      ],
                      if (sourceUrl.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        InkWell(
                          onTap: () => _openSourceUrl(sourceUrl),
                          borderRadius: BorderRadius.circular(4),
                          hoverColor: Mc.cardHigh,
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(Icons.open_in_new,
                                size: 13, color: Mc.cobaltSoft),
                          ),
                        ),
                      ],
                    ]),
                  ),
                ]),
          ),
        ),
      ),
    );
  }
}

/// 分页小按钮。
class _PageBtn extends StatelessWidget {
  const _PageBtn(
      {required this.icon, required this.enabled, required this.onTap});
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Mc.surface,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Mc.hairline),
          ),
          child: Icon(icon,
              size: 16,
              color: enabled ? Mc.ink : Mc.muted.withValues(alpha: 0.4)),
        ),
      ),
    );
  }
}

/// 右侧详情面板: 正文 + 点赞/收藏互动栏 + 评论区 (对齐 NewsDetail.vue)。
class _ArticlePanel extends StatefulWidget {
  const _ArticlePanel(
      {super.key,
      required this.article,
      required this.catName,
      required this.catColor,
      this.onOpenArticle,
      this.showSideCards = true});
  final Map<String, dynamic> article;
  final String? catName;
  final Color catColor;

  /// 点击相关阅读跳转 (内嵌面板=切换选中, 全屏页=push 新 overlay)。
  final ValueChanged<int>? onOpenArticle;

  /// 是否在面板底部挂情报三卡 (情绪/相关阅读/资产雷达)。
  final bool showSideCards;

  @override
  State<_ArticlePanel> createState() => _ArticlePanelState();
}

class _ArticlePanelState extends State<_ArticlePanel> {
  final _commentCtrl = TextEditingController();
  bool _liked = false;
  bool _faved = false;
  bool _sending = false;
  int _likeCount = 0;
  int _favCount = 0;
  List<dynamic> _comments = [];
  String? _commentsErr;
  String? _commentMsg;

  int? get _id => Fmt.toNum(widget.article['id'])?.toInt();

  static bool _truthy(dynamic v) => v == true || v == 1 || v == '1';

  @override
  void initState() {
    super.initState();
    _reset();
    _loadInteraction();
  }

  @override
  void didUpdateWidget(covariant _ArticlePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (Fmt.toNum(oldWidget.article['id'])?.toInt() != _id) {
      _reset();
      _loadInteraction();
    }
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  void _reset() {
    _liked = false;
    _faved = false;
    _sending = false;
    _likeCount = Fmt.toNum(widget.article['like_count'])?.toInt() ?? 0;
    _favCount = Fmt.toNum(widget.article['favorite_count'])?.toInt() ?? 0;
    _comments = [];
    _commentsErr = null;
    _commentMsg = null;
    _commentCtrl.clear();
  }

  /// 进入详情时回填点赞/收藏状态, 并拉取评论列表。
  Future<void> _loadInteraction() async {
    final id = _id;
    if (id == null) return;
    try {
      final st = await ApiClient.I.interactionState('news', [id]);
      if (!mounted || _id != id) return;
      dynamic entry;
      if (st is List) {
        for (final x in st) {
          if (x is Map && '${x['target_id'] ?? x['id']}' == '$id') {
            entry = x;
            break;
          }
        }
      } else if (st is Map) {
        final items = st['items'];
        entry = st[id] ??
            st['$id'] ??
            (items is Map ? (items[id] ?? items['$id']) : null);
      }
      if (entry is Map) {
        setState(() {
          _liked = _truthy(entry['liked'] ?? entry['is_liked']);
          _faved = _truthy(
              entry['favorited'] ?? entry['faved'] ?? entry['is_favorite']);
        });
      }
    } catch (_) {
      // 状态拉取失败静默
    }
    try {
      final res = await ApiClient.I.comments('news', id);
      if (!mounted || _id != id) return;
      final list = res is Map
          ? (res['items'] ?? res['data'])
          : (res is List ? res : null);
      setState(() {
        _comments = list is List ? list : [];
        _commentsErr = null;
      });
    } catch (e) {
      if (!mounted || _id != id) return;
      setState(() =>
          _commentsErr = e is ApiException ? e.message : '评论加载失败');
    }
  }

  Future<void> _toggleLike() async {
    final id = _id;
    if (id == null) return;
    try {
      await ApiClient.I.interact('like', 'news', id);
      if (!mounted || _id != id) return;
      setState(() {
        _liked = !_liked;
        _likeCount += _liked ? 1 : -1;
      });
    } catch (_) {
      // 401 由全局处理, 其余静默
    }
  }

  Future<void> _toggleFav() async {
    final id = _id;
    if (id == null) return;
    try {
      await ApiClient.I.interact('favorite', 'news', id);
      if (!mounted || _id != id) return;
      setState(() {
        _faved = !_faved;
        _favCount += _faved ? 1 : -1;
      });
    } catch (_) {
      // 401 由全局处理, 其余静默
    }
  }

  Future<void> _submitComment() async {
    final id = _id;
    final content = _commentCtrl.text.trim();
    if (id == null || content.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _commentMsg = null;
    });
    try {
      final c = await ApiClient.I.addComment(
          {'target_type': 'news', 'target_id': id, 'content': content});
      if (!mounted || _id != id) return;
      final item = (c is Map && c['id'] != null)
          ? c
          : {
              'id': 'local-${DateTime.now().millisecondsSinceEpoch}',
              'content': content,
              'nickname': '我',
              'created_at': DateTime.now().millisecondsSinceEpoch,
            };
      setState(() {
        _comments = [item, ..._comments];
        _commentCtrl.clear();
        _sending = false;
      });
    } catch (e) {
      if (!mounted || _id != id) return;
      setState(() {
        _sending = false;
        _commentMsg = e is ApiException ? e.message : '评论提交失败';
      });
    }
  }

  /// 复制链接 (对齐 NewsDetail.vue copyCitation: 标题 + web 详情链接)。
  Future<void> _copyLink() async {
    final title = widget.article['title']?.toString() ?? '';
    await Clipboard.setData(
        ClipboardData(text: '$title\nhttps://mingcevip.com/news/$_id'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('链接已复制'),
      duration: Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final article = widget.article;
    final content = article['content']?.toString() ?? '';
    final paragraphs = content
        .split(RegExp(r'\n{2,}'))
        .map((p) => p.replaceAll(RegExp(r'[#*>`]'), '').trim())
        .where((p) => p.isNotEmpty)
        .toList();
    final summary = article['summary']?.toString() ?? '';
    final sourceUrl = article['source_url']?.toString().trim() ?? '';
    final readMin = (content.length / 400).ceil().clamp(1, 1 << 31);
    final t = Fmt.parseServerTime(article['publish_at']);
    final coins = relatedCoinsOf(article);

    return McCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Mc.cardRadius),
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            Row(children: [
              if (widget.catName != null) ...[
                McBadge(widget.catName!, color: widget.catColor),
                const SizedBox(width: 10),
              ],
              Text(article['source']?.toString() ?? 'MINGCE',
                  style: Mc.body(12, w: FontWeight.w600)),
              const Spacer(),
              // 快捷操作: 复制链接 (对齐 NewsDetail.vue:233-235)
              InkWell(
                onTap: _copyLink,
                borderRadius: BorderRadius.circular(6),
                hoverColor: Mc.cardHigh.withValues(alpha: 0.6),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.share_outlined,
                      size: 15, color: Mc.muted),
                ),
              ),
              const SizedBox(width: 4),
              if (sourceUrl.isNotEmpty) ...[
                _SourceLink(url: sourceUrl),
                const SizedBox(width: 10),
              ],
              if (t != null)
                Text('${Fmt.mdHm(article['publish_at'])} · ${Fmt.ago(article['publish_at'])}',
                    style: Mc.mono(11, color: Mc.muted)),
            ]),
            const SizedBox(height: 14),
            Text(article['title']?.toString() ?? '',
                style: Mc.display(20)),
            const SizedBox(height: 12),
            Row(children: [
              const McTag('EST. READ'),
              const SizedBox(width: 8),
              Text('$readMin MIN · ${content.length} 字',
                  style: Mc.mono(11, color: Mc.muted)),
            ]),
            // 高关联标的 chips (对齐 NewsDetail.vue:261-267)
            if (coins.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(children: [
                const McTag('LINKED ASSETS'),
                const SizedBox(width: 8),
                for (final c in coins) ...[
                  McBadge(c, color: Mc.cobaltSoft),
                  const SizedBox(width: 6),
                ],
              ]),
            ],
            const SizedBox(height: 16),
            const Divider(height: 1, color: Mc.hairline),
            const SizedBox(height: 16),
            if (summary.isNotEmpty) ...[
              Container(
                decoration: const BoxDecoration(
                  color: Mc.cardHigh,
                  border: Border(
                      left: BorderSide(color: Mc.cobalt, width: 3)),
                  borderRadius: BorderRadius.only(
                      topRight: Radius.circular(8),
                      bottomRight: Radius.circular(8)),
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const McTag('SUMMARY', color: Mc.cobaltSoft),
                      const SizedBox(height: 6),
                      Text(summary, style: Mc.body(13)),
                      const SizedBox(height: 6),
                      // 摘要情绪倾向 (对齐 NewsDetail.vue:281)
                      Row(children: [
                        Text('— ${article['source'] ?? 'MINGCE'}',
                            style: Mc.body(11,
                                w: FontWeight.w600, color: Mc.cobaltSoft)),
                        const SizedBox(width: 10),
                        Text('情绪倾向: ${sentiTextOf(article['sentiment'])}',
                            style: Mc.body(11, color: Mc.muted)),
                      ]),
                    ]),
              ),
              const SizedBox(height: 16),
            ],
            for (final p in paragraphs) ...[
              Text(p, style: Mc.body(14, color: Mc.ink.withValues(alpha: 0.92))),
              const SizedBox(height: 14),
            ],
            if (paragraphs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: McEmpty('暂无正文'),
              ),
            const SizedBox(height: 6),
            const Divider(height: 1, color: Mc.hairline),
            const SizedBox(height: 12),
            // ---------- 标签 + 互动栏 (赞同 / 收藏) ----------
            Row(children: [
              if (widget.catName != null) ...[
                McBadge('#${widget.catName}', color: Mc.muted),
                const SizedBox(width: 8),
              ],
              if (article['source'] != null)
                McBadge('#${article['source']}', color: Mc.muted),
              const Spacer(),
              _InteractBtn(
                icon: _liked ? Icons.thumb_up : Icons.thumb_up_outlined,
                label: '赞同',
                count: _likeCount,
                active: _liked,
                color: Mc.bull,
                onTap: _toggleLike,
              ),
              const SizedBox(width: 8),
              _InteractBtn(
                icon: _faved ? Icons.bookmark : Icons.bookmark_border,
                label: _faved ? '已收藏' : '收藏',
                count: _favCount,
                active: _faved,
                color: Mc.cobaltSoft,
                onTap: _toggleFav,
              ),
            ]),
            const SizedBox(height: 16),
            const Divider(height: 1, color: Mc.hairline),
            const SizedBox(height: 14),
            // ---------- 评论区 ----------
            Row(children: [
              const Icon(Icons.forum_outlined, size: 16, color: Mc.cobaltSoft),
              const SizedBox(width: 8),
              Text('评论', style: Mc.display(14)),
              const SizedBox(width: 8),
              const McTag('COMMENTS'),
              const SizedBox(width: 6),
              Text('(${_comments.length})',
                  style: Mc.mono(10, color: Mc.muted)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: McInput(
                  controller: _commentCtrl,
                  hint: '写下你的看法…',
                  height: 36,
                  onSubmitted: (_) => _submitComment(),
                ),
              ),
              const SizedBox(width: 8),
              McButton('发布',
                  height: 36, busy: _sending, onPressed: _submitComment),
            ]),
            const SizedBox(height: 6),
            if (_commentMsg != null)
              Text(_commentMsg!, style: Mc.body(12, color: Mc.bear)),
            const SizedBox(height: 8),
            if (_commentsErr != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: Text(_commentsErr!,
                      style: Mc.mono(11, color: Mc.bear)),
                ),
              )
            else if (_comments.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Text('暂无评论, 来抢沙发',
                      style: Mc.mono(11, color: Mc.muted)),
                ),
              )
            else
              for (var i = 0; i < _comments.length; i++)
                _CommentTile(comment: _comments[i], first: i == 0),
            // ---------- 情报三卡: 情绪 / 相关阅读 / 资产雷达 ----------
            if (widget.showSideCards) ...[
              const SizedBox(height: 16),
              const Divider(height: 1, color: Mc.hairline),
              const SizedBox(height: 16),
              _DetailSideCards(
                  article: article, onOpenArticle: widget.onOpenArticle),
            ],
          ],
        ),
      ),
    );
  }
}

/// 互动按钮 (赞同/收藏): 激活态 12% 底色 + 语义色边框与文字。
class _InteractBtn extends StatelessWidget {
  const _InteractBtn({
    required this.icon,
    required this.label,
    required this.count,
    required this.active,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final int count;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? color : Mc.muted;
    return Material(
      color: active ? color.withValues(alpha: 0.15) : Mc.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: Mc.cardHigh,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: active ? color.withValues(alpha: 0.4) : Mc.hairline),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 6),
            Text('$label ($count)',
                style: Mc.body(12, w: FontWeight.w600, color: fg)),
          ]),
        ),
      ),
    );
  }
}

/// 单条评论: 首字母头像 + 昵称 + 相对时间 + 内容。
class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, required this.first});
  final dynamic comment;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final c = comment is Map ? comment as Map : const {};
    final name = (c['nickname'] ?? c['username'] ?? '用户').toString();
    final initial = name.isEmpty ? 'U' : name.substring(0, 1).toUpperCase();
    return Container(
      decoration: BoxDecoration(
        border: first
            ? null
            : const Border(top: BorderSide(color: Mc.hairline, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Mc.cardHigh,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Mc.hairline),
          ),
          child: Text(initial,
              style: Mc.mono(11, w: FontWeight.w700, color: Mc.cobaltSoft)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(name,
                    overflow: TextOverflow.ellipsis,
                    style: Mc.body(12, w: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              Text(Fmt.ago(c['created_at']),
                  style: Mc.mono(10, color: Mc.muted)),
            ]),
            const SizedBox(height: 2),
            Text(c['content']?.toString() ?? '',
                style: Mc.body(13, color: Mc.ink.withValues(alpha: 0.92))),
          ]),
        ),
      ]),
    );
  }
}

/// 详情情报三卡: 宽屏 McRow 等高并排, 窄屏纵向堆叠。
/// (LayoutBuilder 在 McRow 之外, 符合等高卡约束。)
class _DetailSideCards extends StatelessWidget {
  const _DetailSideCards({required this.article, this.onOpenArticle});
  final Map<String, dynamic> article;
  final ValueChanged<int>? onOpenArticle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cards = <Widget>[
        const _SentimentCard(),
        _RelatedCard(article: article, onOpen: onOpenArticle),
        _AssetRadarCard(article: article),
      ];
      if (c.maxWidth >= 760) {
        return McRow(spans: const [4, 4, 4], children: cards);
      }
      return Column(children: [
        cards[0],
        const SizedBox(height: 16),
        cards[1],
        const SizedBox(height: 16),
        cards[2],
      ]);
    });
  }
}

/// 卡 1: 市场情绪 gauge 卡 (对齐 NewsDetail.vue:387-410)。
class _SentimentCard extends StatefulWidget {
  const _SentimentCard();

  @override
  State<_SentimentCard> createState() => _SentimentCardState();
}

class _SentimentCardState extends State<_SentimentCard> {
  num? _value;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiClient.I.sentiment();
      if (!mounted) return;
      setState(() {
        _value = Fmt.toNum(res is Map ? res['fear_greed'] : null);
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  /// 情绪文案 (对齐 NewsDetail.vue sentLabel)。
  String get _label {
    final v = _value;
    if (v == null) return '--';
    if (v >= 75) return 'EXTREME GREED / 极度贪婪';
    if (v >= 50) return 'GREED / 贪婪';
    if (v >= 25) return 'FEAR / 恐慌';
    return 'EXTREME FEAR / 极度恐慌';
  }

  Color get _color {
    final v = _value;
    if (v == null) return Mc.muted;
    if (v >= 50) return Mc.bull;
    if (v >= 25) return Mc.amber;
    return Mc.bear;
  }

  @override
  Widget build(BuildContext context) {
    return _SideCard(
      icon: Icons.speed,
      title: '市场情绪指标',
      tag: 'SENTIMENT',
      trailing: const McBadge('LIVE', color: Mc.bull),
      child: Column(children: [
        SizedBox(
          height: 110,
          width: 200,
          child: CustomPaint(
              painter: _GaugePainter((_value ?? 0).toDouble())),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(_value?.toStringAsFixed(0) ?? '--',
              style: Mc.mono(26, w: FontWeight.w700, color: _color)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(_label,
                overflow: TextOverflow.ellipsis,
                style: Mc.body(12, w: FontWeight.w600, color: _color)),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Text('0 极度恐慌', style: Mc.mono(9, color: Mc.muted)),
          const Spacer(),
          Text('50 中性', style: Mc.mono(9, color: Mc.muted)),
          const Spacer(),
          Text('100 极度贪婪', style: Mc.mono(9, color: Mc.muted)),
        ]),
        if (!_loaded)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('加载中…', style: Mc.mono(10, color: Mc.muted)),
          ),
      ]),
    );
  }
}

/// 恐惧贪婪仪表盘: 上半圆 ∩ (左 0=极度恐慌 → 顶 50 → 右 100=极度贪婪),
/// 四段语义色弧 + 指针。canvas 角: 0°=右, 90°=下, 180°=左, 270°=上。
class _GaugePainter extends CustomPainter {
  const _GaugePainter(this.value);
  final double value; // 0..100

  static const _segments = [
    (0.00, 0.25, Mc.bear),
    (0.25, 0.50, Mc.amber),
    (0.50, 0.75, Mc.cobalt),
    (0.75, 1.00, Mc.bull),
  ];

  static double _rad(double deg) => deg * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.94);
    final r = math.min(size.width / 2 - 8, size.height * 0.88);
    final rect = Rect.fromCircle(center: center, radius: r);
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    for (final (f1, f2, color) in _segments) {
      arcPaint.color = color;
      // 180°(左) 经 270°(顶) 到 360°(右), 正值 sweep 顺时针过顶部
      canvas.drawArc(rect, _rad(180 + 180 * f1), _rad(180 * (f2 - f1)),
          false, arcPaint);
    }
    final a = _rad(180 + 180 * (value.clamp(0, 100) / 100));
    final tip = Offset(center.dx + r * 0.62 * math.cos(a),
        center.dy + r * 0.62 * math.sin(a));
    canvas.drawLine(
        center,
        tip,
        Paint()
          ..color = Mc.ink
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(center, 4, Paint()..color = Mc.ink);
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value;
}

/// 卡 2: 相关阅读 RELATED BRIEFINGS (对齐 NewsDetail.vue:412-438)。
class _RelatedCard extends StatefulWidget {
  const _RelatedCard({required this.article, this.onOpen});
  final Map<String, dynamic> article;
  final ValueChanged<int>? onOpen;

  @override
  State<_RelatedCard> createState() => _RelatedCardState();
}

class _RelatedCardState extends State<_RelatedCard> {
  List<dynamic> _items = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = Fmt.toNum(widget.article['id'])?.toInt();
    final cat = widget.article['category']?.toString();
    try {
      final res = await ApiClient.I.newsList({
        if (cat != null && cat.isNotEmpty) 'category': cat,
        'page_size': 5,
      });
      if (!mounted) return;
      final items = res is Map ? res['items'] : null;
      final list = (items is List ? items : const [])
          .whereType<Map>()
          .where((n) => Fmt.toNum(n['id'])?.toInt() != id)
          .take(4)
          .toList();
      setState(() {
        _items = list;
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SideCard(
      icon: Icons.feed_outlined,
      title: '相关阅读',
      tag: 'RELATED BRIEFINGS',
      child: _items.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text(_loaded ? '暂无相关' : '加载中…',
                    style: Mc.mono(11, color: Mc.muted)),
              ),
            )
          : Column(children: [
              for (var i = 0; i < _items.length; i++)
                _relatedRow(_items[i], first: i == 0),
            ]),
    );
  }

  Widget _relatedRow(Map n, {required bool first}) {
    final id = Fmt.toNum(n['id'])?.toInt();
    final catLabel = _NewsPageState._catName[n['category']] ??
        n['category']?.toString();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap:
            id == null ? null : () => widget.onOpen?.call(id),
        borderRadius: BorderRadius.circular(6),
        hoverColor: Mc.cardHigh,
        child: Container(
          decoration: BoxDecoration(
            border: first
                ? null
                : const Border(
                    top: BorderSide(color: Mc.hairline, width: 0.5)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 9),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (catLabel != null) ...[
                McBadge('#$catLabel', color: Mc.muted),
                const SizedBox(width: 8),
              ],
              Text(Fmt.ago(n['publish_at']),
                  style: Mc.mono(10, color: Mc.muted)),
            ]),
            const SizedBox(height: 4),
            Text(n['title']?.toString() ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Mc.body(12, w: FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}

/// 卡 3: 关联资产异动雷达 (对齐 NewsDetail.vue:440-485):
/// 正文提取高关联标的 → tickers 过滤现货 → 点击跳 MarketDetailPage。
class _AssetRadarCard extends StatefulWidget {
  const _AssetRadarCard({required this.article});
  final Map<String, dynamic> article;

  @override
  State<_AssetRadarCard> createState() => _AssetRadarCardState();
}

class _AssetRadarCardState extends State<_AssetRadarCard> {
  List<Map<String, dynamic>> _rows = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  num _pctOf(Map<String, dynamic> t) {
    final open = Fmt.toNum(t['open24h']) ?? 0;
    if (open == 0) return 0;
    return ((Fmt.toNum(t['last']) ?? 0) - open) / open * 100;
  }

  Future<void> _load() async {
    final coins = relatedCoinsOf(widget.article);
    if (coins.isEmpty) {
      setState(() => _loaded = true);
      return;
    }
    try {
      final res = await ApiClient.I.tickers();
      final list = (res is Map ? res['data'] : null) as List? ?? const [];
      final byId = {
        for (final e in list.whereType<Map>())
          e['instId']?.toString() ?? '': Map<String, dynamic>.from(e),
      };
      if (!mounted) return;
      setState(() {
        _rows = [
          for (final c in coins)
            if (byId['$c-USDT'] != null) byId['$c-USDT']!,
        ];
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalVol = _rows.fold<num>(
        0, (s, t) => s + (Fmt.toNum(t['volCcy24h']) ?? 0));
    return _SideCard(
      icon: Icons.radar,
      title: '关联资产异动',
      tag: 'ASSET RADAR',
      trailing: Text('REAL-TIME', style: Mc.tag()),
      child: Column(children: [
        if (_rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: Text(_loaded ? '暂无关联标的' : '加载中…',
                  style: Mc.mono(11, color: Mc.muted)),
            ),
          )
        else
          for (final t in _rows) _assetRow(t),
        if (_rows.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [
            Container(
              width: 6,
              height: 6,
              decoration:
                  const BoxDecoration(color: Mc.bull, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text('FEED ACTIVE', style: Mc.tag()),
            const Spacer(),
            Text('24H VOL ${Fmt.compact(totalVol, prefix: '\$')}',
                style: Mc.mono(10, color: Mc.muted)),
          ]),
        ],
      ]),
    );
  }

  Widget _assetRow(Map<String, dynamic> t) {
    final inst = t['instId']?.toString() ?? '';
    final coin = inst.split('-').first;
    final pct = _pctOf(t);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Mc.surface,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: inst.isEmpty
              ? null
              : () => ShellRouter.I
                  .push('行情详情', 'MARKET', MarketDetailPage(instId: inst)),
          borderRadius: BorderRadius.circular(8),
          hoverColor: Mc.cardHigh,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Mc.hairline.withValues(alpha: 0.7)),
            ),
            child: Row(children: [
              McBadge(coin, color: Mc.cobaltSoft),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${inst.replaceAll('-', '/')} 现货',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Mc.body(12, w: FontWeight.w600)),
                      Text(Fmt.num_(t['last']),
                          style: Mc.mono(11, color: Mc.muted)),
                    ]),
              ),
              const SizedBox(width: 8),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                    pct >= 0
                        ? Icons.arrow_drop_up
                        : Icons.arrow_drop_down,
                    size: 16,
                    color: Mc.upDown(pct)),
                Text(Fmt.pct(pct),
                    style: Mc.mono(12,
                        w: FontWeight.w700, color: Mc.upDown(pct))),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 右栏: 24H 热榜 + 宏观日历 (可滚动)。
class _NewsSidebar extends StatelessWidget {
  const _NewsSidebar();

  @override
  Widget build(BuildContext context) {
    return ListView(children: const [
      _HotBoard(),
      SizedBox(height: 16),
      _MacroCalendar(),
    ]);
  }
}

/// 右栏卡片骨架: 头部(icon + 标题 + tag + trailing) + body。
class _SideCard extends StatelessWidget {
  const _SideCard(
      {required this.icon,
      required this.title,
      required this.tag,
      this.trailing,
      required this.child});
  final IconData icon;
  final String title;
  final String tag;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return McCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: Mc.hairline, width: 1))),
            child: Row(children: [
              Icon(icon, size: 16, color: Mc.cobaltSoft),
              const SizedBox(width: 8),
              Text(title, style: Mc.display(13)),
              const SizedBox(width: 8),
              McTag(tag, color: Mc.cobaltSoft),
              const Spacer(),
              ?trailing,
            ]),
          ),
          Padding(padding: const EdgeInsets.all(12), child: child),
        ],
      ),
    );
  }
}

/// 24H 热榜: 现货 -USDT 按涨跌幅 TOP5, 60s 自动刷新 (对齐 News.vue loadHot)。
class _HotBoard extends StatefulWidget {
  const _HotBoard();

  @override
  State<_HotBoard> createState() => _HotBoardState();
}

class _HotBoardState extends State<_HotBoard> {
  List<Map<String, dynamic>> _hot = [];
  bool _loaded = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  num _pct(Map<String, dynamic> t) {
    final open = Fmt.toNum(t['open24h']) ?? 0;
    if (open == 0) return 0;
    return ((Fmt.toNum(t['last']) ?? 0) - open) / open * 100;
  }

  Future<void> _load() async {
    try {
      final res = await ApiClient.I.tickers();
      final list = (res is Map ? res['data'] : null) as List? ?? const [];
      final rows = list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((t) =>
              (t['instId'] as String? ?? '').endsWith('-USDT') &&
              (Fmt.toNum(t['open24h']) ?? 0) > 0)
          .toList()
        ..sort((a, b) => _pct(b).compareTo(_pct(a)));
      if (!mounted) return;
      setState(() {
        _hot = rows.take(5).toList();
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hot = [];
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SideCard(
      icon: Icons.local_fire_department_outlined,
      title: '24H 热榜',
      tag: 'TOP GAINERS',
      trailing: Text('60S AUTO', style: Mc.tag()),
      child: _hot.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(_loaded ? '暂无数据' : '加载中…',
                    style: Mc.mono(11, color: Mc.muted)),
              ),
            )
          : Column(children: [
              for (var i = 0; i < _hot.length; i++) _hotRow(i, _hot[i]),
            ]),
    );
  }

  Widget _hotRow(int i, Map<String, dynamic> t) {
    final id = t['instId']?.toString() ?? '';
    final coin = id.split('-').first;
    final pct = _pct(t);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: id.isEmpty
            ? null
            : () => ShellRouter.I
                .push('行情详情', 'MARKET', MarketDetailPage(instId: id)),
        borderRadius: BorderRadius.circular(8),
        hoverColor: Mc.cardHigh,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
          child: Row(children: [
            SizedBox(
              width: 22,
              child: Text('${i + 1}'.padLeft(2, '0'),
                  style:
                      Mc.mono(13, w: FontWeight.w700, color: Mc.cobaltSoft)),
            ),
            McBadge(coin, color: Mc.cobaltSoft),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$id 现货',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Mc.body(12, w: FontWeight.w600)),
                    Text('24H额 ${Fmt.compact(t['volCcy24h'])}',
                        style: Mc.mono(10, color: Mc.muted)),
                  ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(Fmt.pct(pct),
                  style: Mc.mono(12,
                      w: FontWeight.w700, color: Mc.upDown(pct))),
              Text(Fmt.num_(t['last']),
                  style: Mc.mono(10, color: Mc.muted)),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// 宏观日历: 当月网格(周一开头, 今天高亮) + 今日事件列表 (对齐 News.vue)。
class _MacroCalendar extends StatefulWidget {
  const _MacroCalendar();

  @override
  State<_MacroCalendar> createState() => _MacroCalendarState();
}

class _MacroCalendarState extends State<_MacroCalendar> {
  static const _months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];
  static const _week = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

  List<dynamic> _events = [];
  bool _loaded = false;
  bool _loadingDay = false;

  /// 选中日期 (默认今天); 点击日历格子切换并重载当日事件。
  late DateTime _selected = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool get _isToday {
    final now = DateTime.now();
    return _selected.year == now.year &&
        _selected.month == now.month &&
        _selected.day == now.day;
  }

  Future<void> _load() async {
    try {
      final res = await ApiClient.I.macroCalendar(date: _fmtDate(_selected));
      if (!mounted) return;
      final items = res is Map ? res['items'] : null;
      setState(() {
        _events = items is List ? items : [];
        _loaded = true;
        _loadingDay = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _events = [];
        _loaded = true;
        _loadingDay = false;
      });
    }
  }

  void _selectDay(int day) {
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, day);
    if (d == _selected) return;
    setState(() {
      _selected = d;
      _loadingDay = true;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthLabel = '${_months[now.month - 1]} ${now.year}';
    return _SideCard(
      icon: Icons.calendar_month_outlined,
      title: '宏观日历',
      tag: 'EVENT CALENDAR',
      trailing:
          Text(monthLabel, style: Mc.mono(11, w: FontWeight.w700)),
      child: Column(children: [
        // 星期头 (周一开头)
        Row(children: [
          for (final w in _week)
            Expanded(
              child: Center(
                child: Text(w, style: Mc.mono(10, color: Mc.muted)),
              ),
            ),
        ]),
        const SizedBox(height: 4),
        ..._calRows(now),
        const SizedBox(height: 10),
        Container(
          decoration: const BoxDecoration(
              border:
                  Border(top: BorderSide(color: Mc.hairline, width: 1))),
          padding: const EdgeInsets.only(top: 10),
          child: Column(children: [
            Row(children: [
              Text(
                  _isToday
                      ? '今日关键事件'
                      : '${_selected.month.toString().padLeft(2, '0')}-${_selected.day.toString().padLeft(2, '0')} 关键事件',
                  style: Mc.mono(11, color: Mc.muted)),
              const Spacer(),
              Text('${_events.length} 项',
                  style:
                      Mc.mono(11, w: FontWeight.w700, color: Mc.cobaltSoft)),
            ]),
            const SizedBox(height: 8),
            if (_events.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: Text(
                      _loadingDay || !_loaded ? '加载中…' : '当日暂无宏观事件',
                      style: Mc.mono(11, color: Mc.muted)),
                ),
              )
            else
              for (final e in _events) _eventRow(e),
          ]),
        ),
      ]),
    );
  }

  /// 当月日历网格行 (周一=首列, 今天高亮, 前后月暗淡, 周末弱化)。
  List<Widget> _calRows(DateTime now) {
    final firstWd = (DateTime(now.year, now.month, 1).weekday - 1) % 7;
    final days = DateTime(now.year, now.month + 1, 0).day;
    final prevDays = DateTime(now.year, now.month, 0).day;
    final cells = <({int d, bool dim, bool today, bool weekend})>[];
    for (var i = firstWd - 1; i >= 0; i--) {
      cells.add((d: prevDays - i, dim: true, today: false, weekend: false));
    }
    for (var d = 1; d <= days; d++) {
      final wd = (firstWd + d - 1) % 7;
      cells.add(
          (d: d, dim: false, today: d == now.day, weekend: wd >= 5));
    }
    var n = 1;
    while (cells.length % 7 != 0) {
      cells.add((d: n++, dim: true, today: false, weekend: false));
    }
    return [
      for (var r = 0; r < cells.length; r += 7)
        Row(children: [
          for (var i = r; i < r + 7; i++) _calCell(cells[i]),
        ]),
    ];
  }

  Widget _calCell(({int d, bool dim, bool today, bool weekend}) c) {
    final label = '${c.d}'.padLeft(2, '0');
    final selected = !c.dim && c.d == _selected.day;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: c.dim ? null : () => _selectDay(c.d),
        child: Container(
          height: 28,
          margin: const EdgeInsets.all(1),
          alignment: Alignment.center,
          decoration: c.today
              ? BoxDecoration(
                  color: Mc.cobalt, borderRadius: BorderRadius.circular(6))
              : selected
                  ? BoxDecoration(
                      color: Mc.cobalt.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: Mc.cobalt.withValues(alpha: 0.6)))
                  : null,
          child: Text(
            label,
            style: Mc.mono(11,
                w: c.today || selected ? FontWeight.w700 : FontWeight.w500,
                color: c.today
                    ? Colors.white
                    : c.dim
                        ? Mc.muted.withValues(alpha: 0.3)
                        : selected
                            ? Mc.cobaltSoft
                            : c.weekend
                                ? Mc.muted.withValues(alpha: 0.8)
                                : Mc.ink),
          ),
        ),
      ),
    );
  }

  /// 事件行: 重要性圆点 (>=3 红 / 2 琥珀 / 其他钴蓝) + 名称 + 预期 + 时间。
  Widget _eventRow(dynamic raw) {
    final e = raw is Map ? raw : const {};
    final imp = Fmt.toNum(e['importance'])?.toInt() ?? 0;
    final dotColor = imp >= 3 ? Mc.bear : imp == 2 ? Mc.amber : Mc.cobalt;
    final forecast = e['forecast'];
    var sub = (e['country'] ?? e['currency'] ?? '').toString();
    if (forecast != null) sub += ' · 预期 $forecast${e['unit'] ?? ''}';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Mc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Mc.hairline.withValues(alpha: 0.7)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: 5),
          decoration:
              BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e['name']?.toString() ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Mc.body(12, w: FontWeight.w600)),
            if (sub.isNotEmpty)
              Text(sub, style: Mc.mono(10, color: Mc.muted)),
          ]),
        ),
        const SizedBox(width: 8),
        Text(e['event_at']?.toString() ?? '',
            style: Mc.mono(11,
                w: FontWeight.w700,
                color: imp >= 3 ? Mc.amber : Mc.ink)),
      ]),
    );
  }
}

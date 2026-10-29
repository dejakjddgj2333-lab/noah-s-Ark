import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/kit.dart';
import '../widgets/shell.dart';
import 'market_detail_page.dart';

/// 全局搜索结果覆盖页: 左币种 (tickers 本地过滤) + 右资讯 (keyword 查询,
/// 主从布局, 点击行右侧加载全文)。由顶栏搜索框经 ShellRouter 推入。
class SearchResultsPage extends StatefulWidget {
  const SearchResultsPage({super.key, required this.query});

  final String query;

  @override
  State<SearchResultsPage> createState() => _SearchResultsPageState();
}

class _SearchResultsPageState extends State<SearchResultsPage> {
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

  // 币种
  List<Map> _coins = [];
  bool _coinsLoading = true;
  String? _coinsError;

  // 资讯列表
  List<dynamic> _news = [];
  bool _newsLoading = true;
  String? _newsError;

  // 资讯详情
  int? _selectedId;
  Map<String, dynamic>? _article;
  bool _detailLoading = false;
  String? _detailError;

  @override
  void initState() {
    super.initState();
    _loadCoins();
    _loadNews();
  }

  /// 拉全量现货 ticker, 本地按 instId 包含关键词 (大写) 过滤。
  Future<void> _loadCoins() async {
    setState(() {
      _coinsLoading = true;
      _coinsError = null;
    });
    try {
      final res = await ApiClient.I.tickers();
      final list = (res is Map ? res['data'] : null) as List? ?? const [];
      final kw = widget.query.toUpperCase();
      final matched = list
          .whereType<Map>()
          .where(
              (t) => (t['instId'] as String? ?? '').toUpperCase().contains(kw))
          .toList();
      if (!mounted) return;
      setState(() {
        _coins = matched;
        _coinsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _coinsLoading = false;
        _coinsError = e.toString();
      });
    }
  }

  Future<void> _loadNews() async {
    setState(() {
      _newsLoading = true;
      _newsError = null;
    });
    try {
      final res = await ApiClient.I
          .newsList({'keyword': widget.query, 'page': 1, 'page_size': 20});
      if (!mounted) return;
      final items = res is Map ? res['items'] : null;
      setState(() {
        _news = items is List ? items : [];
        _newsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _newsLoading = false;
        _newsError = e.toString();
      });
    }
  }

  Future<void> _selectNews(Map item) async {
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 20),
        McSection('“${widget.query}” 的搜索结果',
            tag: 'SEARCH',
            trailing: Text(
              '币种 ${_coinsLoading ? '-' : _coins.length} · 资讯 ${_newsLoading ? '-' : _news.length}',
              style: Mc.mono(11, color: Mc.muted),
            )),
        const SizedBox(height: 14),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 340, child: _buildCoins()),
            const SizedBox(width: 24),
            Expanded(child: _buildNewsArea()),
          ]),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }

  // ---------- 币种区 ----------
  Widget _buildCoins() {
    Widget body;
    if (_coinsLoading) {
      body = const McLoading(label: '搜索币种中');
    } else if (_coinsError != null) {
      body = McError('币种搜索失败', onRetry: _loadCoins);
    } else if (_coins.isEmpty) {
      body = const McEmpty('无匹配币种');
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: _coins.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: Mc.hairline),
        itemBuilder: (_, i) => _CoinRow(
          ticker: _coins[i],
          onTap: () {
            final id = _coins[i]['instId'] as String? ?? '';
            if (id.isEmpty) return;
            ShellRouter.I.push(
                '行情详情', 'MARKET', MarketDetailPage(instId: id));
          },
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const McTag('MARKETS', color: Mc.cobaltSoft),
      const SizedBox(height: 8),
      Expanded(
        child: McCard(
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Mc.cardRadius),
            child: body,
          ),
        ),
      ),
    ]);
  }

  // ---------- 资讯区 (列表 + 详情) ----------
  Widget _buildNewsArea() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const McTag('NEWS', color: Mc.cobaltSoft),
      const SizedBox(height: 8),
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 340, child: _buildNewsList()),
          const SizedBox(width: 16),
          Expanded(child: _buildNewsDetail()),
        ]),
      ),
    ]);
  }

  Widget _buildNewsList() {
    Widget body;
    if (_newsLoading) {
      body = const McLoading(label: '搜索资讯中');
    } else if (_newsError != null) {
      body = McError('资讯搜索失败', onRetry: _loadNews);
    } else if (_news.isEmpty) {
      body = const McEmpty('无相关资讯');
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: _news.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: Mc.hairline),
        itemBuilder: (_, i) {
          final n = _news[i] as Map;
          final id = Fmt.toNum(n['id'])?.toInt();
          return _NewsRow(
            item: n,
            selected: id != null && id == _selectedId,
            catName: _catName[n['category']],
            catColor: _catColor[n['category']] ?? Mc.muted,
            onTap: () => _selectNews(n),
          );
        },
      );
    }
    return McCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Mc.cardRadius),
        child: body,
      ),
    );
  }

  Widget _buildNewsDetail() {
    if (_selectedId == null) return const McEmpty('选择左侧资讯查看详情');
    if (_detailLoading) return const McLoading(label: '加载详情中');
    if (_detailError != null) {
      return McError('详情加载失败', onRetry: () {
        final item = _news.whereType<Map>().firstWhere(
            (e) => Fmt.toNum(e['id'])?.toInt() == _selectedId,
            orElse: () => {'id': _selectedId});
        _selectNews(item);
      });
    }
    final a = _article;
    if (a == null) return const McEmpty('资讯不存在');
    return _ArticlePanel(
      article: a,
      catName: _catName[a['category']],
      catColor: _catColor[a['category']] ?? Mc.muted,
    );
  }
}

/// 币种结果行: 币种名 + 最新价 + 24h 涨跌幅 (着色)。
class _CoinRow extends StatelessWidget {
  const _CoinRow({required this.ticker, required this.onTap});
  final Map ticker;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final instId = ticker['instId'] as String? ?? '';
    final coin = instId.split('-').first;
    final last = Fmt.toNum(ticker['last']);
    final open = Fmt.toNum(ticker['open24h']);
    final pct = (last != null && open != null && open > 0)
        ? (last - open) / open * 100
        : null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: Mc.cardHigh.withValues(alpha: 0.6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(coin, style: Mc.display(14)),
                    const SizedBox(height: 2),
                    Text(instId, style: Mc.mono(10, color: Mc.muted)),
                  ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(Fmt.num_(ticker['last']), style: Mc.mono(13)),
              const SizedBox(height: 2),
              Text(pct == null ? '--' : Fmt.pct(pct),
                  style: Mc.mono(11, color: Mc.upDown(pct))),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// 资讯结果行: 分类徽标 + 标题 + 相对时间。
class _NewsRow extends StatelessWidget {
  const _NewsRow(
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
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Mc.cardHigh : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: Mc.cardHigh.withValues(alpha: 0.6),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                  color: selected ? Mc.cobalt : Colors.transparent, width: 2),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (catName != null) ...[
                McBadge(catName!, color: catColor),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(Fmt.ago(item['publish_at']),
                    textAlign: TextAlign.right,
                    style: Mc.mono(10, color: Mc.muted)),
              ),
            ]),
            const SizedBox(height: 6),
            Text(item['title']?.toString() ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Mc.body(13,
                    w: selected ? FontWeight.w600 : FontWeight.w400)),
          ]),
        ),
      ),
    );
  }
}

/// 右侧资讯详情面板 (简化版: 标题 / 来源时间 / 摘要 / 正文段落)。
class _ArticlePanel extends StatelessWidget {
  const _ArticlePanel(
      {required this.article, required this.catName, required this.catColor});
  final Map<String, dynamic> article;
  final String? catName;
  final Color catColor;

  @override
  Widget build(BuildContext context) {
    final content = article['content']?.toString() ?? '';
    final paragraphs = content
        .split(RegExp(r'\n{2,}'))
        .map((p) => p.replaceAll(RegExp(r'[#*>`]'), '').trim())
        .where((p) => p.isNotEmpty)
        .toList();
    final summary = article['summary']?.toString() ?? '';

    return McCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Mc.cardRadius),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(children: [
              if (catName != null) ...[
                McBadge(catName!, color: catColor),
                const SizedBox(width: 10),
              ],
              Text(article['source']?.toString() ?? 'MINGCE',
                  style: Mc.body(12, w: FontWeight.w600)),
              const Spacer(),
              Text(
                  '${Fmt.mdHm(article['publish_at'])} · ${Fmt.ago(article['publish_at'])}',
                  style: Mc.mono(11, color: Mc.muted)),
            ]),
            const SizedBox(height: 12),
            Text(article['title']?.toString() ?? '', style: Mc.display(18)),
            const SizedBox(height: 14),
            const Divider(height: 1, color: Mc.hairline),
            const SizedBox(height: 14),
            if (summary.isNotEmpty) ...[
              Container(
                decoration: const BoxDecoration(
                  color: Mc.cardHigh,
                  border:
                      Border(left: BorderSide(color: Mc.cobalt, width: 3)),
                  borderRadius: BorderRadius.only(
                      topRight: Radius.circular(8),
                      bottomRight: Radius.circular(8)),
                ),
                padding: const EdgeInsets.all(12),
                child: Text(summary, style: Mc.body(13)),
              ),
              const SizedBox(height: 14),
            ],
            for (final p in paragraphs) ...[
              Text(p,
                  style:
                      Mc.body(14, color: Mc.ink.withValues(alpha: 0.92))),
              const SizedBox(height: 12),
            ],
            if (paragraphs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: McEmpty('暂无正文'),
              ),
          ],
        ),
      ),
    );
  }
}

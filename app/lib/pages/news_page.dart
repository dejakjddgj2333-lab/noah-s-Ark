import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/api.dart';
import '../services/data.dart';
import 'macro_calendar_page.dart';
import 'news_detail_page.dart';

/// 资讯 (News / Signals Intel) — full bottom-nav tab, content body only.
/// Gold terminal theme variant (faithful to news.html palette).
class NewsPage extends StatefulWidget {
  const NewsPage({super.key});

  // Blue theme tokens (aligned with other pages)
  static const _gold = McColors.primaryContainer; // #2e5cff
  static const _goldBright = McColors.primarySoft; // #82a4ff
  static const _green = Color(0xFF00F090); // secondary-container
  static const _greenText = Color(0xFF58FFA5); // secondary-fixed
  static const _cyan = Color(0xFF00D8F6); // tertiary
  static const _error = Color(0xFFFFB4AB);
  static const _onSurfaceVariant = McColors.onSurfaceVariant;

  @override
  State<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> {
  List<NewsItem> _flash = const [];
  bool _loading = true;
  bool _error = false;

  // 分类过滤 + 分页
  String _category = 'flash';
  String? _keyword; // 行业政策 keyword 过滤模式 (非空时忽略 category)
  int _page = 1;
  bool _loadingMore = false;
  bool _endReached = false;
  static const int _pageSize = 20;
  final ScrollController _scroll = ScrollController();

  // 行业政策关键词 (后端 keyword 支持逗号分隔 OR)
  static const String _policyKeyword = '监管,政策,SEC,法案,央行,合规';

  // 分类 tab: 标签 → 后端 category (资讯/快讯/公告)
  static const List<(String, String)> _categories = [
    ('资讯', 'news'),
    ('快讯', 'flash'),
    ('公告', 'notice'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    await _loadTimeline(reset: true);
  }

  // 时间线列表 (当前分类). reset=true 从第一页重新拉.
  Future<void> _loadTimeline({bool reset = false}) async {
    if (reset) {
      _page = 1;
      _endReached = false;
    }
    try {
      final items = await McData.news(
        category: _keyword == null ? _category : null,
        keyword: _keyword,
        page: _page,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _flash = items;
        } else {
          _flash = [..._flash, ...items];
        }
        _endReached = items.length < _pageSize;
        _loading = false;
        _error = false;
        _loadingMore = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (_flash.isEmpty) _error = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (_flash.isEmpty) _error = true;
      });
    }
  }

  void _selectCategory(String category) {
    if ((category == _category && _keyword == null) || _loadingMore) return;
    setState(() {
      _category = category;
      _keyword = null; // 退出 keyword 过滤模式
      _loading = true;
      _error = false;
      _flash = const [];
    });
    _loadTimeline(reset: true);
  }

  // 行业政策 tab: keyword 过滤模式
  void _applyPolicyFilter() {
    if (_keyword != null || _loadingMore) return;
    setState(() {
      _keyword = _policyKeyword;
      _loading = true;
      _error = false;
      _flash = const [];
    });
    _scrollToTop();
    _loadTimeline(reset: true);
  }

  void _scrollToTop() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  void _openCalendar() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MacroCalendarPage()),
    );
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _endReached) return;
    setState(() => _loadingMore = true);
    _page++;
    await _loadTimeline();
  }

  // ---- data mapping helpers ----

  void _openDetail(int id) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NewsDetailPage(id: id)),
    );
  }

  String _fmtTime(DateTime utc) {
    final local = utc.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _fmtCount(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}W';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  /// Sentiment → bull percentage. positive 75-90 / negative 15-30 / neutral 50.
  int _bullPct(NewsItem item) {
    switch (item.sentiment) {
      case 'positive':
        return 75 + (item.id % 16); // 75-90
      case 'negative':
        return 15 + (item.id % 16); // 15-30
      default:
        return 50;
    }
  }

  /// Category → Chinese tag label.
  String _categoryLabel(String category) {
    switch (category) {
      case 'flash':
        return '快讯';
      case 'notice':
        return '公告';
      default:
        return '资讯';
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      color: NewsPage._gold,
      child: _loading && _flash.isEmpty
          ? _firstLoading()
          : ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 32),
              children: [
                _breakingTicker(),
                const SizedBox(height: 20),
                _subNavTabs(),
                const SizedBox(height: 12),
                _feedFilterRow(),
                const SizedBox(height: 12),
                _categoryChips(),
                const SizedBox(height: 16),
                _timeline(),
                const SizedBox(height: 16),
                _loadMoreButton(),
                const SizedBox(height: 20),
                _editorialBar(),
              ],
            ),
    );
  }

  // 分类过滤 chips: 资讯/快讯/公告 (+政策 keyword 模式)
  Widget _categoryChips() {
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        children: [
          for (final (label, cat) in _categories)
            _categoryChip(label, cat,
                active: _keyword == null && _category == cat),
          _policyChip(),
        ],
      ),
    );
  }

  // 行业政策 keyword 过滤 chip (active 时带小指示点)
  Widget _policyChip() {
    final active = _keyword != null;
    return GestureDetector(
      onTap: _applyPolicyFilter,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? NewsPage._cyan : McColors.surfaceContainer,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? NewsPage._cyan
                : McColors.outlineVariant.withValues(alpha: 0.6),
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                      color: NewsPage._cyan.withValues(alpha: 0.4),
                      blurRadius: 12)
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (active) ...[
              Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFFFFF),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              '政策',
              style: McText.mono(
                size: 12,
                weight: active ? FontWeight.w700 : FontWeight.w600,
                color: active
                    ? const Color(0xFFFFFFFF)
                    : NewsPage._onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryChip(String label, String category, {bool active = false}) {
    return GestureDetector(
      onTap: () => _selectCategory(category),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? NewsPage._gold : McColors.surfaceContainer,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? NewsPage._gold
                : McColors.outlineVariant.withValues(alpha: 0.6),
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                      color: NewsPage._gold.withValues(alpha: 0.4),
                      blurRadius: 12)
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: McText.mono(
            size: 12,
            weight: active ? FontWeight.w700 : FontWeight.w600,
            color:
                active ? const Color(0xFFFFFFFF) : NewsPage._onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  // 加载更多 / 没有更多了
  Widget _loadMoreButton() {
    if (_flash.isEmpty) return const SizedBox.shrink();
    if (_endReached) {
      return Center(
        child: Text(
          '没有更多了',
          style: McText.mono(size: 12, color: NewsPage._onSurfaceVariant),
        ),
      );
    }
    return Center(
      child: GestureDetector(
        onTap: _loadingMore ? null : _loadMore,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
          decoration: BoxDecoration(
            color: McColors.surfaceContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: McColors.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: _loadingMore
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: NewsPage._goldBright),
                )
              : Text(
                  '加载更多',
                  style: McText.mono(
                      size: 12,
                      weight: FontWeight.w600,
                      color: NewsPage._goldBright),
                ),
        ),
      ),
    );
  }

  Widget _firstLoading() {
    return ListView(
      // keep scrollable so RefreshIndicator works during first load
      children: const [
        SizedBox(height: 240),
        Center(child: CircularProgressIndicator()),
      ],
    );
  }

  /// Compact placeholder shown when a section has no data or failed to load.
  Widget _emptyPlaceholder() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            _error ? '加载失败' : '暂无数据',
            style: McText.mono(size: 12, color: NewsPage._onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _load,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: NewsPage._gold,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _error ? '重试' : '刷新',
                style: McText.mono(
                    size: 12,
                    weight: FontWeight.w700,
                    color: const Color(0xFFFFFFFF)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Breaking news ticker
  Widget _breakingTicker() {
    final headline = _flash.isNotEmpty
        ? _flash.first.title
        : 'SEC 主席关于数字资产监管框架发表最新利好言论';
    final since = _flash.isNotEmpty ? _relativeTime(_flash.first.publishAt) : '10分钟前';
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12)],
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: NewsPage._gold,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(color: NewsPage._gold.withValues(alpha: 0.5), blurRadius: 14)
              ],
            ),
            child: const Icon(Icons.bolt, size: 16, color: Color(0xFFFFFFFF)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '突发头条',
                      style: McText.mono(
                          size: 12,
                          weight: FontWeight.w700,
                          color: NewsPage._gold,
                          letterSpacing: 1),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      since,
                      style: McText.mono(size: 12, color: NewsPage._onSurfaceVariant),
                    ),
                  ],
                ),
                Text(
                  headline,
                  style: McText.mono(
                      size: 12,
                      weight: FontWeight.w500,
                      color: McColors.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: McColors.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.chevron_right,
                size: 18, color: NewsPage._onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  String _relativeTime(DateTime utc) {
    final diff = DateTime.now().difference(utc.toLocal());
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
  }

  // Terminal sub-navigation tabs
  Widget _subNavTabs() {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _tab(Icons.rss_feed, '7×24 快讯',
              active: _keyword == null && _category == 'flash',
              ping: true,
              onTap: () => _selectCategory('flash')),
          _tab(Icons.calendar_today, '宏观日历', onTap: _openCalendar),
          _tab(Icons.gavel, '行业政策',
              active: _keyword != null, onTap: _applyPolicyFilter),
        ],
      ),
    );
  }

  Widget _tab(IconData icon, String label,
      {bool active = false, bool ping = false, VoidCallback? onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: active ? NewsPage._gold : McColors.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        boxShadow: active
            ? [BoxShadow(color: NewsPage._gold.withValues(alpha: 0.45), blurRadius: 16)]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 15,
              color: active ? const Color(0xFFFFFFFF) : NewsPage._onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: McText.mono(
              size: 12,
              weight: active ? FontWeight.w700 : FontWeight.w600,
              color: active ? const Color(0xFFFFFFFF) : NewsPage._onSurfaceVariant,
            ),
          ),
          if (ping) ...[
            const SizedBox(width: 6),
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFFFFFFFF),
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }

  // Realtime feed filter + audio read switch
  Widget _feedFilterRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Row(
              children: [
                Text(
                  'REALTIME FEED',
                  style: McText.mono(
                      size: 12,
                      weight: FontWeight.w700,
                      color: NewsPage._gold,
                      letterSpacing: 2),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '/ 自动流送中',
                    style: McText.mono(size: 12, color: NewsPage._onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              _miniAction(Icons.volume_up, '语音速报'),
              Container(
                width: 1,
                height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: McColors.surfaceContainerHighest,
              ),
              _miniAction(Icons.tune, '筛选'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniAction(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: NewsPage._onSurfaceVariant),
        const SizedBox(width: 4),
        Text(label, style: McText.mono(size: 12, color: NewsPage._onSurfaceVariant)),
      ],
    );
  }

  // 7×24 flash news timeline (dashed connector behind nodes)
  Widget _timeline() {
    if (_flash.isEmpty) {
      return _emptyPlaceholder();
    }
    return Stack(
      children: [
        // vertical dashed track (HTML: absolute left-[15px] top-4 bottom-4)
        const Positioned(
          left: 15,
          top: 20,
          bottom: 20,
          width: 1,
          child: _DashedLine(color: McColors.surfaceContainerHighest),
        ),
        Column(
          children: [
            for (var i = 0; i < _flash.length; i++) _buildTimelineItem(i, _flash[i]),
          ],
        ),
      ],
    );
  }

  Widget _buildTimelineItem(int index, NewsItem item) {
    // cycle node accent colours across items
    const accents = [
      (NewsPage._gold, NewsPage._goldBright),
      (NewsPage._cyan, NewsPage._cyan),
      (NewsPage._greenText, NewsPage._greenText),
    ];
    final (node, glow) = accents[index % accents.length];

    final bullPct = _bullPct(item);
    final views = _fmtCount(item.likeCount + item.commentCount);

    final tags = <_Tag>[
      if (item.sentiment != null)
        const _Tag('重要', bg: Color(0xFF93000A), fg: Color(0xFFFFDAD6)),
      if (item.source.isNotEmpty)
        _Tag(item.source,
            bg: McColors.surfaceContainerHigh, fg: NewsPage._onSurfaceVariant)
      else
        _Tag(_categoryLabel(item.category),
            bg: McColors.surfaceContainerHigh, fg: NewsPage._gold),
    ];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openDetail(item.id),
      child: _timelineItem(
        nodeColor: node,
        nodeGlow: glow,
        time: _fmtTime(item.publishAt),
        timeColor: node,
        tags: tags,
        title: item.title,
        body: item.summary.isNotEmpty ? item.summary : item.content,
        bullPct: bullPct,
        bullCount: _fmtCount(item.likeCount),
        bearCount: _fmtCount(item.commentCount),
        views: views,
        actionLabel: '查看详情',
        actionIcon: Icons.arrow_outward,
        actionColor: node,
        isLast: index == _flash.length - 1,
      ),
    );
  }

  Widget _timelineItem({
    required Color nodeColor,
    required Color nodeGlow,
    required String time,
    required Color timeColor,
    required List<_Tag> tags,
    required String title,
    required String body,
    required int bullPct,
    required String bullCount,
    required String bearCount,
    required String views,
    required String actionLabel,
    required IconData actionIcon,
    required Color actionColor,
    bool isLast = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // glow node (dashed connector drawn behind by _timeline Stack)
        Container(
          width: 32,
          height: 32,
          margin: const EdgeInsets.only(top: 4),
          decoration: const BoxDecoration(
            color: McColors.surfaceContainerLow,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: McGlowDot(color: nodeColor, size: 12),
        ),
        const SizedBox(width: 12),
        // feed card + bottom gap
        Expanded(
          child: Column(
            children: [
              Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: McColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 8)
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // header info
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            time,
                            style: McText.mono(
                                size: 13,
                                weight: FontWeight.w700,
                                color: timeColor),
                          ),
                          for (final t in tags)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: t.bg,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                t.text,
                                style: McText.mono(
                                    size: 12,
                                    weight: FontWeight.w700,
                                    color: t.fg,
                                    letterSpacing: 1),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      'TODAY',
                      style: McText.mono(size: 12, color: NewsPage._onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // content
                Text(
                  title,
                  style: McText.display(
                      size: 16, weight: FontWeight.w700, height: 1.35),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: McText.mono(
                      size: 12, color: NewsPage._onSurfaceVariant, height: 1.5),
                ),
                const SizedBox(height: 12),
                // sentiment bar
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color:
                        McColors.surfaceContainerLowest.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.trending_up,
                                  size: 14, color: NewsPage._greenText),
                              const SizedBox(width: 4),
                              Text(
                                '利好 $bullPct%',
                                style: McText.mono(
                                    size: 12,
                                    weight: FontWeight.w700,
                                    color: NewsPage._greenText),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '($bullCount)',
                                style: McText.mono(
                                    size: 12, color: NewsPage._onSurfaceVariant),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Text(
                                '($bearCount)',
                                style: McText.mono(
                                    size: 12, color: NewsPage._onSurfaceVariant),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '利空 ${100 - bullPct}%',
                                style: McText.mono(
                                    size: 12,
                                    weight: FontWeight.w700,
                                    color: NewsPage._error),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.trending_down,
                                  size: 14, color: NewsPage._error),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: SizedBox(
                          height: 6,
                          child: Row(
                            children: [
                              Expanded(
                                  flex: bullPct,
                                  child: Container(color: NewsPage._green)),
                              Expanded(
                                  flex: 100 - bullPct,
                                  child: Container(color: NewsPage._error)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // action micro-row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.visibility,
                            size: 12, color: NewsPage._onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(views,
                            style: McText.mono(
                                size: 12, color: NewsPage._onSurfaceVariant)),
                        const SizedBox(width: 10),
                        const Icon(Icons.share,
                            size: 12, color: NewsPage._onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text('分享海报',
                            style: McText.mono(
                                size: 12, color: NewsPage._onSurfaceVariant)),
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          actionLabel,
                          style: McText.mono(
                              size: 12,
                              weight: FontWeight.w600,
                              color: actionColor),
                        ),
                        Icon(actionIcon, size: 12, color: actionColor),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
                if (!isLast) const SizedBox(height: 20),
              ],
            ),
          ),
        ],
    );
  }

  // Editorial insight bar
  Widget _editorialBar() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                const Icon(Icons.lightbulb, size: 20, color: NewsPage._cyan),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '加入明策量化社群，第一时间获取非农数据与巨鲸转账即时预警',
                    style: McText.mono(size: 12, color: NewsPage._onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: NewsPage._gold,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(color: NewsPage._gold.withValues(alpha: 0.3), blurRadius: 10)
              ],
            ),
            child: Text(
              '立即订阅',
              style: McText.mono(
                  size: 12,
                  weight: FontWeight.w700,
                  color: const Color(0xFFFFFFFF)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag {
  const _Tag(this.text, {required this.bg, required this.fg});
  final String text;
  final Color bg;
  final Color fg;
}

/// Vertical dashed connector between timeline nodes.
class _DashedLine extends StatelessWidget {
  const _DashedLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(1, double.infinity),
      painter: _DashedLinePainter(color),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 4.0;
    const gap = 3.0;
    var y = 2.0;
    while (y < size.height - 2) {
      canvas.drawLine(Offset(0.5, y), Offset(0.5, (y + dash).clamp(0, size.height - 2)), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}

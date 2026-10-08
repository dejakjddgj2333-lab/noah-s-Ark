import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/data.dart';

/// 资讯详情页 — 从资讯列表/研报卡 push 进入.
///
/// 数据: GET /api/news/{id} → NewsItem. 深色主题, 永不红屏:
/// 加载中转圈, 失败给紧凑的 加载失败 + 重试.
/// 互动: 点赞/评论/收藏/分享 + 查看原文 + 评论区 (/api/interaction).
class NewsDetailPage extends StatefulWidget {
  const NewsDetailPage({super.key, required this.id});

  final int id;

  @override
  State<NewsDetailPage> createState() => _NewsDetailPageState();
}

class _NewsDetailPageState extends State<NewsDetailPage> {
  NewsItem? _item;
  bool _loading = true;
  bool _error = false;

  // 互动状态
  InteractionState _state = InteractionState.fromJson(const {});
  bool _stateLoaded = false;

  // 评论
  final List<McComment> _comments = [];
  int _commentsTotal = 0;
  int _commentsPage = 1;
  bool _commentsLoading = false;
  bool _commentsError = false;

  // 回复展开
  final Set<int> _expanded = {};
  final Map<int, List<McComment>> _replies = {};
  final Set<int> _repliesLoading = {};

  // 评论输入
  final TextEditingController _composer = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  McComment? _replyTo;
  bool _sending = false;

  final ScrollController _scroll = ScrollController();
  final GlobalKey _commentsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _composer.dispose();
    _composerFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final item = await McData.newsDetail(widget.id);
      if (!mounted) return;
      setState(() {
        _item = item;
        _loading = false;
      });
      _refreshState();
      _loadComments(reset: true);
    } on ApiException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  // ---- 互动状态 ----

  Future<void> _refreshState() async {
    try {
      final s = await McInteraction.state(widget.id);
      if (!mounted) return;
      setState(() {
        _state = s;
        _stateLoaded = true;
      });
    } catch (_) {
      // 静默: 互动状态失败不影响正文阅读
    }
  }

  Future<void> _onLike() async {
    if (!await _requireLogin()) return;
    // 乐观更新
    final prev = _state;
    setState(() {
      _state = _state.copyWith(
        likedByMe: !_state.likedByMe,
        likeCount: _state.likedByMe
            ? (_state.likeCount - 1).clamp(0, 1 << 31)
            : _state.likeCount + 1,
      );
    });
    try {
      final (liked, count) = await McInteraction.toggleLike(widget.id);
      if (!mounted) return;
      setState(() {
        _state = _state.copyWith(likedByMe: liked, likeCount: count);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = prev); // 回滚
      _toast(tr('news_op_failed'));
    }
  }

  Future<void> _onFavorite() async {
    if (!await _requireLogin()) return;
    final prev = _state;
    setState(() {
      _state = _state.copyWith(favoritedByMe: !_state.favoritedByMe);
    });
    try {
      final favorited = await McInteraction.toggleFavorite(widget.id);
      if (!mounted) return;
      setState(() {
        _state = _state.copyWith(favoritedByMe: favorited);
      });
      _toast(favorited ? tr('news_favorited') : tr('news_unfavorited'));
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = prev);
      _toast(tr('news_op_failed'));
    }
  }

  void _onCommentTap() {
    final ctx = _commentsKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
  }

  /// 未登录则跳登录页, 返回后刷新状态. 已登录返回 true.
  Future<bool> _requireLogin() async {
    if (AuthStore.instance.loggedIn) return true;
    await Navigator.pushNamed(context, '/login');
    if (!mounted) return false;
    if (AuthStore.instance.loggedIn) {
      _refreshState();
      _loadComments(reset: true);
      return true;
    }
    return false;
  }

  // ---- 评论 ----

  Future<void> _loadComments({bool reset = false}) async {
    if (_commentsLoading) return;
    if (reset) {
      _commentsPage = 1;
    }
    setState(() {
      _commentsLoading = true;
      _commentsError = false;
    });
    try {
      final (items, total) =
          await McInteraction.comments(widget.id, page: _commentsPage);
      if (!mounted) return;
      setState(() {
        if (reset) {
          _comments
            ..clear()
            ..addAll(items);
        } else {
          _comments.addAll(items);
        }
        _commentsTotal = total;
        _commentsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _commentsLoading = false;
        _commentsError = true;
      });
    }
  }

  Future<void> _loadMoreComments() async {
    _commentsPage++;
    await _loadComments();
  }

  Future<void> _toggleReplies(McComment c) async {
    if (_expanded.contains(c.id)) {
      setState(() => _expanded.remove(c.id));
      return;
    }
    setState(() {
      _expanded.add(c.id);
      _repliesLoading.add(c.id);
    });
    try {
      final list = await McInteraction.replies(c.id);
      if (!mounted) return;
      setState(() {
        _replies[c.id] = list;
        _repliesLoading.remove(c.id);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _replies[c.id] = const [];
        _repliesLoading.remove(c.id);
      });
    }
  }

  Future<void> _sendComment() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    if (!await _requireLogin()) return;
    setState(() => _sending = true);
    try {
      await McInteraction.addComment(widget.id, text, replyToId: _replyTo?.id);
      if (!mounted) return;
      _composer.clear();
      setState(() {
        _replyTo = null;
        _sending = false;
      });
      _composerFocus.unfocus();
      _toast(tr('news_comment_published'));
      await _loadComments(reset: true);
      await _refreshState();
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      _toast(tr('news_publish_failed'));
    }
  }

  Future<void> _deleteComment(McComment c) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: McColors.surfaceContainer,
        title: Text(tr('news_delete_comment'), style: McText.sans(size: 15, weight: FontWeight.w600)),
        content: Text(tr('news_delete_comment_hint'),
            style: McText.sans(size: 13, color: McColors.onSurfaceVariant)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel'), style: McText.sans(size: 13, color: McColors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('delete'), style: McText.sans(size: 13, color: McColors.bear)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await McInteraction.deleteComment(c.id);
      if (!mounted) return;
      _toast(tr('news_deleted'));
      await _loadComments(reset: true);
      await _refreshState();
    } catch (_) {
      if (!mounted) return;
      _toast(tr('news_delete_failed'));
    }
  }

  /// 弹举报原因选择, 返回 reason key 或 null.
  Future<String?> _pickReportReason() {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: McColors.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(tr('report_title'),
                  style: McText.sans(size: 15, weight: FontWeight.w700)),
            ),
            for (final (key, label) in [
              ('spam', tr('report_spam')),
              ('abuse', tr('report_abuse')),
              ('fraud', tr('report_fraud')),
              ('porn', tr('report_porn')),
              ('other', tr('report_other')),
            ])
              ListTile(
                title: Text(label, style: McText.sans(size: 14)),
                onTap: () => Navigator.pop(ctx, key),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _reportComment(McComment c) async {
    if (!AuthStore.instance.loggedIn) {
      _requireLogin();
      return;
    }
    final reason = await _pickReportReason();
    if (reason == null) return;
    try {
      await McInteraction.reportComment(c.id, reason: reason);
      if (!mounted) return;
      _toast(tr('report_done'));
    } catch (_) {
      if (!mounted) return;
      _toast(tr('news_publish_failed'));
    }
  }

  void _setReplyTo(McComment c) {
    if (!AuthStore.instance.loggedIn) {
      _requireLogin();
      return;
    }
    setState(() => _replyTo = c);
    _composerFocus.requestFocus();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: McText.sans(size: 13)),
        backgroundColor: McColors.surfaceContainerHighest,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  // ---- 查看原文 ----

  Future<void> _openSource(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _toast(tr('news_link_invalid'));
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _toast(tr('news_link_cannot_open'));
    } catch (_) {
      _toast(tr('news_link_cannot_open'));
    }
  }

  // ---- 格式化 ----

  String _categoryLabel(String category) {
    switch (category) {
      case 'flash':
        return tr('flash');
      case 'notice':
        return tr('notice');
      case 'research':
        return tr('news_research');
      default:
        return tr('news');
    }
  }

  String _fmtTime(DateTime utc) {
    final local = utc.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inMinutes < 1) return tr('time_just_now');
    if (diff.inMinutes < 60) return tr('time_minutes_ago').replaceAll('{n}', '${diff.inMinutes}');
    if (diff.inHours < 24) return tr('time_hours_ago').replaceAll('{n}', '${diff.inHours}');
    final y = local.year.toString().padLeft(4, '0');
    final mo = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    return '$y-$mo-$d $h:$mi';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: McColors.surface,
      appBar: AppBar(
        backgroundColor: McColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back,
              size: 20, color: McColors.onSurface),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(tr('news_detail_title'),
            style: McText.sans(size: 15, weight: FontWeight.w600)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
              height: 1,
              color: McColors.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: McColors.primaryContainer),
      );
    }
    if (_error || _item == null) {
      return _errorView();
    }
    final item = _item!;
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _metaRow(item),
              const SizedBox(height: 12),
              Text(
                item.title,
                style:
                    McText.display(size: 18, weight: FontWeight.w700, height: 1.4),
              ),
              if (item.coverUrl != null && item.coverUrl!.isNotEmpty) ...[
                const SizedBox(height: 14),
                _cover(item.coverUrl!),
              ],
              if (item.summary.isNotEmpty) ...[
                const SizedBox(height: 14),
                _summaryCard(item.summary),
              ],
              const SizedBox(height: 16),
              ..._contentParagraphs(item),
              if (item.sourceUrl != null && item.sourceUrl!.isNotEmpty) ...[
                const SizedBox(height: 18),
                _sourceCard(item.sourceUrl!),
              ],
              const SizedBox(height: 24),
              _commentsSection(),
            ],
          ),
        ),
        _interactionBar(item),
      ],
    );
  }

  // 来源 + 分类 chip + 发布时间
  Widget _metaRow(NewsItem item) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (item.source.isNotEmpty)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.source, size: 13, color: McColors.primarySoft),
              const SizedBox(width: 4),
              Text(
                item.source,
                style: McText.mono(
                    size: 12,
                    weight: FontWeight.w600,
                    color: McColors.primarySoft),
              ),
            ],
          ),
        McPill(_categoryLabel(item.category), color: McColors.primaryContainer),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.schedule,
                size: 12, color: McColors.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              _fmtTime(item.publishAt),
              style:
                  McText.mono(size: 12, color: McColors.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }

  // 封面图 (加载失败则省略, 不留占位)
  Widget _cover(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            height: 180,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: McColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: McColors.primaryContainer),
            ),
          );
        },
      ),
    );
  }

  // 摘要高亮卡
  Widget _summaryCard(String summary) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: McColors.primaryContainer.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
              color: McColors.primaryContainer.withValues(alpha: 0.8), width: 3),
        ),
      ),
      child: Text(
        summary,
        style: McText.sans(
            size: 13,
            weight: FontWeight.w500,
            color: McColors.onSurface,
            height: 1.6),
      ),
    );
  }

  // 正文: 按 \n 分段的可选中文本
  List<Widget> _contentParagraphs(NewsItem item) {
    final body = item.content.isNotEmpty ? item.content : item.summary;
    final paras = body
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (paras.isEmpty) {
      return [
        Text(tr('news_no_content'),
            style: McText.sans(size: 14, color: McColors.onSurfaceVariant)),
      ];
    }
    return [
      for (var i = 0; i < paras.length; i++)
        Padding(
          padding: EdgeInsets.only(bottom: i == paras.length - 1 ? 0 : 12),
          child: SelectableText(
            paras[i],
            style: McText.sans(size: 14, height: 1.6),
          ),
        ),
    ];
  }

  // 查看原文卡
  Widget _sourceCard(String url) {
    return McCard(
      onTap: () => _openSource(url),
      color: McColors.surfaceContainerLow,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: McColors.primaryContainer.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.open_in_new,
                size: 18, color: McColors.primarySoft),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('news_view_original'),
                  style: McText.sans(size: 14, weight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      McText.mono(size: 12, color: McColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right,
              size: 18, color: McColors.onSurfaceVariant),
        ],
      ),
    );
  }

  // ---- 底部互动栏 ----

  Widget _interactionBar(NewsItem item) {
    final state = _stateLoaded
        ? _state
        : InteractionState.fromJson({
            'like_count': item.likeCount,
            'comment_count': item.commentCount,
          });
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLow,
        border: Border(
          top: BorderSide(
              color: McColors.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _barAction(
              icon: state.likedByMe
                  ? Icons.thumb_up
                  : Icons.thumb_up_outlined,
              label: tr('news_like'),
              count: state.likeCount,
              color: state.likedByMe
                  ? McColors.primarySoft
                  : McColors.onSurfaceVariant,
              active: state.likedByMe,
              onTap: _onLike,
            ),
            _barAction(
              icon: Icons.mode_comment_outlined,
              label: tr('news_comment'),
              count: state.commentCount,
              color: McColors.onSurfaceVariant,
              onTap: _onCommentTap,
            ),
            _barAction(
              icon: state.favoritedByMe ? Icons.star : Icons.star_border,
              label: tr('news_favorite'),
              color: state.favoritedByMe
                  ? McColors.goldBright
                  : McColors.onSurfaceVariant,
              active: state.favoritedByMe,
              onTap: _onFavorite,
            ),
            _barAction(
              icon: Icons.share_outlined,
              label: tr('news_share'),
              count: item.shareCount,
              color: McColors.onSurfaceVariant,
              onTap: () => SharePlus.instance.share(
                ShareParams(
                  text: item.summary.isNotEmpty
                      ? '${item.title}\n\n${item.summary}'
                      : item.title,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _barAction({
    required IconData icon,
    required String label,
    int? count,
    required Color color,
    bool active = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 5),
            Text(
              count != null ? '$label $count' : label,
              style: McText.sans(
                size: 12,
                weight: active ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 评论区 ----

  Widget _commentsSection() {
    return Column(
      key: _commentsKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 16,
              decoration: BoxDecoration(
                color: McColors.primaryContainer,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                      color: McColors.primaryContainer.withValues(alpha: 0.6),
                      blurRadius: 8)
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${tr('news_comment')} ${_stateLoaded ? _state.commentCount : _commentsTotal}',
              style: McText.sans(size: 15, weight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _composerBox(),
        const SizedBox(height: 18),
        _commentsList(),
      ],
    );
  }

  Widget _composerBox() {
    final loggedIn = AuthStore.instance.loggedIn;
    if (!loggedIn) {
      return GestureDetector(
        onTap: _requireLogin,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: McColors.primaryContainer.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: McColors.primaryContainer.withValues(alpha: 0.4)),
          ),
          alignment: Alignment.center,
          child: Text(
            tr('news_login_to_comment'),
            style: McText.sans(
                size: 13,
                weight: FontWeight.w600,
                color: McColors.primarySoft),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_replyTo != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    tr('news_reply_to').replaceAll('{name}', _replyTo!.username),
                    style: McText.mono(size: 12, color: McColors.primarySoft),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => setState(() => _replyTo = null),
                  child: const Icon(Icons.close,
                      size: 14, color: McColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: McColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: McColors.outlineVariant.withValues(alpha: 0.7)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _composer,
                  focusNode: _composerFocus,
                  maxLines: 4,
                  minLines: 1,
                  style: McText.sans(size: 13),
                  decoration: InputDecoration(
                    hintText: _replyTo != null
                        ? tr('news_reply_hint').replaceAll('{name}', _replyTo!.username)
                        : tr('news_comment_hint'),
                    hintStyle:
                        McText.sans(size: 13, color: McColors.onSurfaceVariant),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _sendComment,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: McColors.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          tr('news_send'),
                          style: McText.mono(
                              size: 12,
                              weight: FontWeight.w700,
                              color: const Color(0xFFFFFFFF)),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _commentsList() {
    if (_comments.isEmpty) {
      if (_commentsLoading) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: McColors.primaryContainer),
            ),
          ),
        );
      }
      if (_commentsError) {
        return _commentsRetry();
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(tr('news_no_comments'),
              style: McText.sans(size: 13, color: McColors.onSurfaceVariant)),
        ),
      );
    }
    final hasMore = _comments.length < _commentsTotal;
    return Column(
      children: [
        for (final c in _comments) _commentTile(c),
        if (hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: GestureDetector(
              onTap: _commentsLoading ? null : _loadMoreComments,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                decoration: BoxDecoration(
                  color: McColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: McColors.outlineVariant.withValues(alpha: 0.6)),
                ),
                child: _commentsLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: McColors.primarySoft),
                      )
                    : Text(
                        tr('news_load_more'),
                        style: McText.mono(
                            size: 12,
                            weight: FontWeight.w600,
                            color: McColors.primarySoft),
                      ),
              ),
            ),
          ),
        if (_commentsError)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _commentsRetry(),
          ),
      ],
    );
  }

  Widget _commentsRetry() {
    return GestureDetector(
      onTap: () => _loadComments(reset: _comments.isEmpty),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.refresh, size: 14, color: McColors.primarySoft),
          const SizedBox(width: 4),
          Text(tr('news_comments_failed_retry'),
              style: McText.sans(size: 12, color: McColors.primarySoft)),
        ],
      ),
    );
  }

  Widget _commentTile(McComment c, {bool isReply = false}) {
    final isOwn = AuthStore.instance.loggedIn &&
        AuthStore.instance.username != null &&
        AuthStore.instance.username == c.username;
    return Padding(
      padding: EdgeInsets.only(bottom: isReply ? 12 : 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _avatar(c.username, size: isReply ? 26 : 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        c.username.isEmpty ? tr('news_anonymous') : c.username,
                        style: McText.sans(
                            size: 13,
                            weight: FontWeight.w600,
                            color: isOwn
                                ? McColors.primarySoft
                                : McColors.onSurface),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _fmtTime(c.createdAt),
                      style: McText.mono(
                          size: 12, color: McColors.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SelectableText(
                  c.content,
                  style: McText.sans(size: 13, height: 1.5),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => _setReplyTo(c),
                      child: Text(
                        tr('news_reply'),
                        style: McText.sans(
                            size: 12,
                            weight: FontWeight.w600,
                            color: McColors.onSurfaceVariant),
                      ),
                    ),
                    if (isOwn) ...[
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: () => _deleteComment(c),
                        child: Text(
                          tr('delete'),
                          style: McText.sans(
                              size: 12,
                              weight: FontWeight.w600,
                              color: McColors.bear),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: () => _reportComment(c),
                        child: Text(
                          tr('news_report'),
                          style: McText.sans(
                              size: 12,
                              weight: FontWeight.w600,
                              color: McColors.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ],
                ),
                if (!isReply && c.replyCount > 0) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _toggleReplies(c),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _expanded.contains(c.id)
                              ? tr('news_collapse_replies')
                              : tr('news_view_replies').replaceAll('{n}', '${c.replyCount}'),
                          style: McText.sans(
                              size: 12,
                              weight: FontWeight.w600,
                              color: McColors.primarySoft),
                        ),
                        Icon(
                          _expanded.contains(c.id)
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 14,
                          color: McColors.primarySoft,
                        ),
                      ],
                    ),
                  ),
                ],
                if (!isReply && _expanded.contains(c.id)) _repliesBlock(c),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _repliesBlock(McComment c) {
    if (_repliesLoading.contains(c.id)) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: McColors.primaryContainer),
        ),
      );
    }
    final list = _replies[c.id] ?? const [];
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(tr('news_no_replies'),
            style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(10, 10, 0, 0),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLowest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
              color: McColors.outlineVariant.withValues(alpha: 0.7), width: 2),
        ),
      ),
      child: Column(
        children: [for (final r in list) _commentTile(r, isReply: true)],
      ),
    );
  }

  Widget _avatar(String username, {double size = 32}) {
    final initial =
        username.isEmpty ? tr('news_anon_initial') : username.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: McColors.primaryContainer.withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(
            color: McColors.primaryContainer.withValues(alpha: 0.4)),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: McText.mono(
            size: 13, weight: FontWeight.w700, color: McColors.primarySoft),
      ),
    );
  }

  // 紧凑失败态 + 重试
  Widget _errorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off,
              size: 32, color: McColors.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(tr('news_load_failed'),
              style: McText.sans(size: 13, color: McColors.onSurfaceVariant)),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _load,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: McColors.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                tr('news_retry'),
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
}

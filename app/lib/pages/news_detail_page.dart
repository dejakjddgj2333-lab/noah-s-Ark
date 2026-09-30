import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/api.dart';
import '../services/data.dart';

/// 资讯详情页 — 从资讯列表/研报卡 push 进入.
///
/// 数据: GET /api/news/{id} → NewsItem. 深色主题, 永不红屏:
/// 加载中转圈, 失败给紧凑的 加载失败 + 重试.
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

  @override
  void initState() {
    super.initState();
    _load();
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

  String _categoryLabel(String category) {
    switch (category) {
      case 'flash':
        return '快讯';
      case 'notice':
        return '公告';
      case 'research':
        return '研报';
      default:
        return '资讯';
    }
  }

  /// 发布时间: 1 小时内 'X分钟前', 24 小时内 'X小时前', 否则 yyyy-MM-dd HH:mm.
  String _fmtTime(DateTime utc) {
    final local = utc.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
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
        title: Text('资讯详情',
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
            ],
          ),
        ),
        _bottomBar(item),
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
        Text('暂无正文内容',
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

  // 底部: 利好 / 利空 / 分享 计数 (仅展示, 无交互)
  Widget _bottomBar(NewsItem item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            _countChip(Icons.trending_up, '利好', item.likeCount, McColors.bull),
            _countChip(
                Icons.trending_down, '利空', item.commentCount, McColors.bear),
            _countChip(Icons.share, '分享', item.shareCount, McColors.primarySoft),
          ],
        ),
      ),
    );
  }

  Widget _countChip(IconData icon, String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            '$label $count',
            style: McText.mono(size: 12, weight: FontWeight.w700, color: color),
          ),
        ],
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
          Text('加载失败',
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
                '重试',
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

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/api.dart';
import '../services/data.dart';

/// 巨鲸雷达 (Home → Whale Radar tab) — content body only.
/// Rendered inside the existing shell (header + top tabs + bottom nav).
///
/// 实时异动时间线固定走 Hyperliquid 大额成交流 (免费源, 比 CoinGlass
/// whale-alert 更全); 无数据时显示诚实空态, 不放编造 mock.
class HomeWhalePage extends StatefulWidget {
  const HomeWhalePage({super.key});

  @override
  State<HomeWhalePage> createState() => _HomeWhalePageState();
}

class _HomeWhalePageState extends State<HomeWhalePage> {
  // 时间线条目: 仅 Hyperliquid 真实大额成交, 初始为空, 失败保持空态.
  List<_WhaleFeedItem> _feedItems = const [];

  // 链上流动性总览: null = 未加载/失败, 对应数值显示 '--'.
  LiquidityOverview? _liq;

  // 时间线筛选: '' = 全部, '异动' = 合约仓位异动 (HL 流只有这一类).
  String _filter = '';
  // 预警阈值: 只显示 >= 该美元值的异动 (0 = 全部).
  double _minUsd = 0;

  List<_WhaleFeedItem> get _visibleFeed => _feedItems.where((f) {
        if (_filter.isNotEmpty && f.category != _filter) return false;
        return f.usdValue >= _minUsd;
      }).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 两块独立拉取, 互不影响; 任一失败保持空态/'--'.
    await Future.wait<void>([_loadFeed(), _loadLiquidity()]);
  }

  Future<void> _loadFeed() async {
    try {
      final resp = await McData.overview('whale-alerts');
      final items = _parseAlerts(resp['alerts']);
      if (!mounted || items.isEmpty) return;
      setState(() => _feedItems = items);
    } on ApiException {
      // 上游/后端异常 — 保持空态.
    } catch (_) {
      // 网络/解析异常 — 保持空态.
    }
  }

  Future<void> _loadLiquidity() async {
    try {
      final liq = await McData.liquidityOverview();
      if (!mounted || liq.isEmpty) return;
      setState(() => _liq = liq);
    } on ApiException {
      // 上游/后端异常 — 显示 '--'.
    } catch (_) {
      // 网络/解析异常 — 显示 '--'.
    }
  }

  // Hyperliquid whale-alert → 时间线条目 (best-effort, 字段缺失即用占位).
  static List<_WhaleFeedItem> _parseAlerts(dynamic raw) {
    final list = _asList(raw);
    final out = <_WhaleFeedItem>[];
    for (final e in list) {
      if (e is! Map) continue;
      final m = e.cast<String, dynamic>();
      final symbol = _str(m, ['symbol', 'coin', 'asset'], 'UNKNOWN');
      final user = _str(m, ['user', 'address', 'wallet'], '');
      final sizeUsd = _num(m['positionSize'] ?? m['positionValue'] ??
          m['usdValue'] ?? m['amountUsd'] ?? m['size']);
      final sideRaw =
          _str(m, ['side', 'positionSide', 'direction'], '').toLowerCase();
      final isLong = sideRaw.contains('long') || sideRaw.contains('buy');
      final isShort = sideRaw.contains('short') || sideRaw.contains('sell');
      final accent = isShort
          ? McColors.error
          : (isLong ? McColors.tertiary : McColors.primary);
      final ts = m['time'] ?? m['timestamp'] ?? m['createTime'] ?? m['ts'];
      out.add(_WhaleFeedItem(
        pillIcon: isShort
            ? Icons.warning
            : (isLong ? Icons.download_for_offline : Icons.sync_alt),
        pillText: isShort
            ? tr('whale_feed_short')
            : (isLong ? tr('whale_feed_long') : tr('whale_feed_move')),
        pillColor: accent,
        chain: 'Hyperliquid',
        time: _relTime(ts),
        amount: sizeUsd > 0
            ? '$symbol ${_fmtUsd(sizeUsd)}'
            : tr('whale_position_change').replaceAll('{symbol}', symbol),
        usd: sizeUsd > 0 ? '≈ ${_fmtUsd(sizeUsd)} USD' : tr('whale_position_update'),
        usdColor: accent,
        from: _shortAddr(user),
        to: isShort ? tr('whale_verb_reduce') : (isLong ? tr('whale_verb_add') : tr('whale_verb_move')),
        fromColor: McColors.onSurfaceVariant,
        toColor: accent,
        arrowColor: accent,
        txHash: _shortAddr(user),
        usdValue: sizeUsd,
        category: '异动',
      ));
      if (out.length >= 10) break;
    }
    return out;
  }

  // ---- 解析辅助 ----
  static List<dynamic> _asList(dynamic v) {
    if (v is List) return v;
    if (v is Map) {
      for (final e in v.values) {
        if (e is List) return e;
      }
    }
    return const [];
  }

  static double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  static String _str(Map<String, dynamic> m, List<String> keys, String dflt) {
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.isNotEmpty) return v;
      if (v is num) return '$v';
    }
    return dflt;
  }

  static String _shortAddr(String addr) {
    if (addr.length <= 10) return addr.isEmpty ? tr('whale_anon') : addr;
    return '${addr.substring(0, 6)}...${addr.substring(addr.length - 4)}';
  }

  // 美元金额中文紧凑格式: 万/亿, 不用 K/M/B.
  static String _fmtUsd(double v) {
    final a = v.abs();
    if (a >= 1e8) return '\$${(v / 1e8).toStringAsFixed(2)}亿';
    if (a >= 1e4) return '\$${(v / 1e4).toStringAsFixed(1)}万';
    return '\$${v.toStringAsFixed(0)}';
  }

  // 大额紧凑: 复用全局 fmtUsdCompact (2.86T/112.3B/3.4M).
  static String _fmtCap(double? v) =>
      v == null ? '--' : McData.fmtUsdCompact(v);

  // 带符号百分数, null 显示 --.
  static String _fmtPct(double? v) {
    if (v == null) return '--';
    final sign = v >= 0 ? '+' : '';
    return '$sign${v.toStringAsFixed(2)}%';
  }

  // 涨跌着色: 正 bull / 负 bear / 未知 outline.
  static Color _pctColor(double? v) =>
      v == null ? McColors.outline : (v >= 0 ? McColors.bull : McColors.bear);

  static String _relTime(dynamic ts) {
    final ms = ts is num ? ts.toInt() : int.tryParse('$ts') ?? 0;
    if (ms <= 0) return tr('time_just_now');
    final dt =
        DateTime.fromMillisecondsSinceEpoch(ms > 100000000000 ? ms : ms * 1000);
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return tr('time_just_now');
    if (diff.inMinutes < 60) {
      return tr('time_minutes_ago').replaceAll('{n}', '${diff.inMinutes}');
    }
    if (diff.inHours < 24) {
      return tr('time_hours_ago').replaceAll('{n}', '${diff.inHours}');
    }
    return tr('time_days_ago').replaceAll('{n}', '${diff.inDays}');
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      color: McColors.primaryContainer,
      backgroundColor: McColors.surfaceContainer,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 32),
        children: [
          _liquidityOverview(),
          const SizedBox(height: 20),
          _whaleFeedSection(),
          const SizedBox(height: 24),
          _alertThresholdButton(),
        ],
      ),
    );
  }

  // 1. 链上流动性异动总览 bento card
  Widget _liquidityOverview() {
    final liq = _liq;
    // 真实值缺失即回退 mock 首帧.
    final stableTotal = liq?.stableTotalUsd;
    final stableChg = liq?.stableChange1dPct;
    final tvlTotal = liq?.tvlTotalUsd;
    final tvlChg = liq?.tvlChange1dPct;
    final tops = liq?.topStables ?? const <StableCoin>[];
    return McCard(
      color: McColors.surfaceContainer,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.radar, size: 20, color: McColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    tr('whale_liq_overview'),
                    style: McText.display(size: 18, weight: FontWeight.w600),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: McColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const McGlowDot(color: McColors.tertiary, size: 6),
                    const SizedBox(width: 6),
                    Text(
                      tr('whale_listening_24h'),
                      style: McText.sans(
                          size: 12,
                          weight: FontWeight.w600,
                          color: McColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // core metrics
          Row(
            children: [
              Expanded(
                child: _metricBox(
                  label: tr('whale_stable_total'),
                  value: stableTotal != null ? _fmtCap(stableTotal) : '--',
                  valueColor: McColors.onSurface,
                  delta: stableTotal != null ? _fmtPct(stableChg) : '--',
                  deltaColor: stableTotal != null
                      ? _pctColor(stableChg)
                      : McColors.onSurfaceVariant,
                  caption: tr('whale_stable_caption'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _metricBox(
                  label: tr('whale_tvl_total'),
                  value: tvlTotal != null ? _fmtCap(tvlTotal) : '--',
                  valueColor: McColors.onSurface,
                  delta: tvlTotal != null ? _fmtPct(tvlChg) : '--',
                  deltaColor: tvlTotal != null
                      ? _pctColor(tvlChg)
                      : McColors.onSurfaceVariant,
                  caption: tr('whale_tvl_caption'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // top 稳定币 mini 列表
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: McColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: McColors.outlineVariant.withValues(alpha: 0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.currency_exchange,
                            size: 14, color: McColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          tr('whale_top_stable'),
                          style: McText.sans(
                              size: 12,
                              weight: FontWeight.w600,
                              color: McColors.onSurfaceVariant),
                        ),
                      ],
                    ),
                    Text(
                      tr('whale_circ_change'),
                      style: McText.sans(size: 12, color: McColors.outline),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (tops.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(tr('no_data'),
                        style: McText.sans(
                            size: 12, color: McColors.onSurfaceVariant)),
                  )
                else
                  ...[
                    for (var i = 0; i < tops.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      _stableRow(tops[i]),
                    ],
                  ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          // filter pills: HL 大额成交流只有合约异动一类
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _filterPill(tr('whale_filter_all'), value: ''),
                _filterPill(tr('whale_filter_position'), value: '异动'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricBox({
    required String label,
    required String value,
    required Color valueColor,
    String? delta,
    Color? deltaColor,
    String? badge,
    required String caption,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: McColors.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: McText.sans(
                      size: 12,
                      weight: FontWeight.w600,
                      color: McColors.outline,
                      letterSpacing: 0.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: McColors.tertiary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badge,
                    style: McText.sans(
                        size: 12,
                        weight: FontWeight.w700,
                        color: McColors.tertiary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: McText.display(
                        size: 24,
                        weight: FontWeight.w700,
                        color: valueColor,
                        letterSpacing: -0.5),
                  ),
                ),
              ),
              if (delta != null) ...[
                const SizedBox(width: 6),
                Text(
                  delta,
                  style: McText.sans(
                      size: 12,
                      weight: FontWeight.w500,
                      color: deltaColor ?? McColors.tertiary),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            caption,
            style: McText.sans(size: 12, color: McColors.outline),
          ),
        ],
      ),
    );
  }

  // 单个稳定币行: 名称 + 流通 + 24H 涨跌 (bull/bear 着色).
  Widget _stableRow(StableCoin s) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            s.name,
            style: McText.sans(
                size: 12, weight: FontWeight.w600, color: McColors.onSurface),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _fmtCap(s.circulatingUsd),
              style:
                  McText.sans(size: 12, color: McColors.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 64,
              child: Text(
                _fmtPct(s.change1dPct),
                textAlign: TextAlign.right,
                style: McText.sans(
                    size: 12,
                    weight: FontWeight.w600,
                    color: _pctColor(s.change1dPct)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _filterPill(String text, {required String value}) {
    final selected = _filter == value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _filter = value),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? McColors.primaryContainer
              : McColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(999),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: McColors.primaryContainer.withValues(alpha: 0.4),
                      blurRadius: 8)
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: McText.sans(
            size: 12,
            weight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected
                ? McColors.onPrimaryContainer
                : McColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  // 3. 实时异动高精时间线
  Widget _whaleFeedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.stream,
                      size: 18, color: McColors.primaryContainer),
                  const SizedBox(width: 8),
                  Text(
                    tr('whale_feed_title'),
                    style: McText.display(size: 18, weight: FontWeight.w600),
                  ),
                ],
              ),
              Row(
                children: [
                  const McGlowDot(color: McColors.tertiary, size: 6),
                  const SizedBox(width: 6),
                  Text(
                    tr('whale_ws_connected'),
                    style: McText.sans(size: 12, color: McColors.tertiary),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_visibleFeed.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(tr('whale_no_feed'),
                  style: McText.sans(size: 12, color: McColors.outline)),
            ),
          )
        else
          for (var i = 0; i < _visibleFeed.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            _feedCard(_visibleFeed[i]),
          ],
      ],
    );
  }

  Widget _feedCard(_WhaleFeedItem item) {
    return Container(
      decoration: BoxDecoration(
        color: McColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: McColors.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: item.pillColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(item.pillIcon,
                                    size: 14, color: item.pillColor),
                                const SizedBox(width: 6),
                                Text(
                                  item.pillText,
                                  style: McText.sans(
                                      size: 12,
                                      weight: FontWeight.w600,
                                      color: item.pillColor),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: McColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.chain,
                              style: McText.sans(
                                  size: 12,
                                  color: McColors.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.time,
                      style: McText.sans(size: 12, color: McColors.outline),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.amount,
                          style: McText.display(
                              size: 18,
                              weight: FontWeight.w700,
                              color: McColors.onSurface),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.usd,
                          style: McText.sans(
                              size: 12,
                              weight: FontWeight.w500,
                              color: item.usdColor),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _flowTag(item.from, item.fromColor),
                          Icon(Icons.trending_flat,
                              size: 16, color: item.arrowColor),
                          _flowTag(item.to, item.toColor),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: McColors.surfaceContainerLow.withValues(alpha: 0.6),
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(12)),
              border: Border(
                top: BorderSide(
                    color: McColors.outlineVariant.withValues(alpha: 0.1)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Row(
                    children: [
                      Text(
                        'TxHash:',
                        style: McText.sans(size: 12, color: McColors.outline),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          item.txHash,
                          style: McText.mono(
                              size: 12,
                              color: McColors.primary,
                              letterSpacing: 1),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openDetail(item),
                  child: Row(
                    children: [
                      Text(
                        tr('whale_detail_link'),
                        style: McText.sans(size: 12, color: McColors.primary),
                      ),
                      const Icon(Icons.chevron_right,
                          size: 14, color: McColors.primary),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _flowTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: McText.sans(size: 12, weight: FontWeight.w500, color: color),
      ),
    );
  }

  // 研判详情弹层: 完整字段 + 解读.
  void _openDetail(_WhaleFeedItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: McColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: McColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(item.pillIcon, size: 18, color: item.pillColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(item.pillText,
                      style: McText.sans(
                          size: 15,
                          weight: FontWeight.w700,
                          color: item.pillColor)),
                ),
                Text(item.time,
                    style: McText.sans(size: 12, color: McColors.outline)),
              ],
            ),
            const SizedBox(height: 14),
            _detailRow(tr('whale_detail_amount'), item.amount),
            _detailRow(tr('whale_detail_value'), item.usd),
            _detailRow(tr('whale_detail_chain'), item.chain),
            _detailRow(tr('whale_detail_from'), item.from),
            _detailRow(tr('whale_detail_to'), item.to),
            _detailRow('TxHash', item.txHash),
            const SizedBox(height: 12),
            Text(
              _interpretation(item),
              style: McText.sans(
                  size: 12, height: 1.6, color: McColors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  // 解读文案: 依据当前语言的动词标签判断方向 (item.to 已是译文).
  String _interpretation(_WhaleFeedItem item) {
    final body = item.to == tr('whale_verb_reduce')
        ? tr('whale_interpret_reduce')
        : item.to == tr('whale_verb_add')
            ? tr('whale_interpret_add')
            : tr('whale_interpret_move');
    return tr('whale_interpret_prefix').replaceAll('{text}', body);
  }

  Widget _detailRow(String label, String value) {    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(label,
                style: McText.sans(size: 12, color: McColors.outline)),
          ),
          Expanded(
            child: Text(value,
                style: McText.mono(size: 12, color: McColors.onSurface)),
          ),
        ],
      ),
    );
  }

  // 预警阈值: 选择后只显示 >= 阈值的异动.
  void _pickThreshold() {
    final options = <(String, double)>[
      (tr('whale_filter_all'), 0),
      ('≥ \$1M', 1e6),
      ('≥ \$10M', 1e7),
      ('≥ \$50M', 5e7),
      ('≥ \$100M', 1e8),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: McColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text(tr('whale_threshold_title'),
                style: McText.sans(size: 14, weight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final (label, v) in options)
              ListTile(
                dense: true,
                title: Text(label, style: McText.mono(size: 13)),
                trailing: _minUsd == v
                    ? const Icon(Icons.check,
                        size: 18, color: McColors.tertiary)
                    : null,
                onTap: () {
                  setState(() => _minUsd = v);
                  Navigator.pop(context);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _alertThresholdButton() {
    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _pickThreshold,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: McColors.primaryContainer,
            borderRadius: BorderRadius.circular(999),
            border:
                Border.all(color: McColors.primary.withValues(alpha: 0.2)),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 16),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_alert,
                  size: 18, color: McColors.onPrimaryContainer),
              const SizedBox(width: 8),
              Text(
                _minUsd > 0
                    ? tr('whale_threshold_set').replaceAll('{v}', _fmtUsd(_minUsd))
                    : tr('whale_threshold_cta'),
                style: McText.sans(
                    size: 12,
                    weight: FontWeight.w600,
                    color: McColors.onPrimaryContainer),
              ),
              const SizedBox(width: 6),
              const McGlowDot(color: McColors.tertiary, size: 6),
            ],
          ),
        ),
      ),
    );
  }
}

/// 时间线条目的不可变数据模型.
class _WhaleFeedItem {
  const _WhaleFeedItem({
    required this.pillIcon,
    required this.pillText,
    required this.pillColor,
    required this.chain,
    required this.time,
    required this.amount,
    required this.usd,
    required this.usdColor,
    required this.from,
    required this.to,
    required this.fromColor,
    required this.toColor,
    required this.arrowColor,
    required this.txHash,
    this.usdValue = 0,
    this.category = '',
  });

  final IconData pillIcon;
  final String pillText;
  final Color pillColor;
  final String chain;
  final String time;
  final String amount;
  final String usd;
  final Color usdColor;
  final String from;
  final String to;
  final Color fromColor;
  final Color toColor;
  final Color arrowColor;
  final String txHash;
  final double usdValue; // 原始美元值, 阈值过滤用
  final String category; // 分类过滤用 (提币/充值/做市/转账)
}

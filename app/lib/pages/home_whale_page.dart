import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/api.dart';
import '../services/data.dart';

/// 巨鲸雷达 (Home → Whale Radar tab) — content body only.
/// Rendered inside the existing shell (header + top tabs + bottom nav).
///
/// 实时异动时间线尝试接 `/api/market-overview/whale-alerts`; 失败(未配置
/// CoinGlass/上游错误/后端未启动)时静默保留内置 mock, 永不红屏.
class HomeWhalePage extends StatefulWidget {
  const HomeWhalePage({super.key});

  @override
  State<HomeWhalePage> createState() => _HomeWhalePageState();
}

class _HomeWhalePageState extends State<HomeWhalePage> {
  // 时间线条目: coinglass 模式首屏展示内置 mock, 拉取成功后整体替换;
  // free 模式无链上数据, 初始为空, 只展示 Hyperliquid 真实大额成交.
  List<_WhaleFeedItem> _feedItems = const [];

  // 链上流动性总览: null = 未加载/失败, 卡片回退 mock.
  LiquidityOverview? _liq;

  // 数据源: free 隐藏链上内容 (聪明钱/链上转账类异动); coinglass 全量.
  String _source = 'free';
  bool _sourceReady = false;

  // 时间线筛选: '' = 全部, 否则按 category 匹配 (提币/充值/做市/转账/异动).
  String _filter = '';
  // 预警阈值: 只显示 >= 该美元值的异动 (0 = 全部).
  double _minUsd = 0;

  List<_WhaleFeedItem> get _visibleFeed => _feedItems.where((f) {
        if (_filter.isNotEmpty && f.category != _filter) return false;
        return f.usdValue >= _minUsd;
      }).toList();

  static List<_WhaleFeedItem> _mockFeedItems() => const [
        _WhaleFeedItem(
          pillIcon: Icons.download_for_offline,
          pillText: '提币囤积 · 强烈利好',
          usdValue: 115704000,
          category: '提币',
          pillColor: McColors.tertiary,
          chain: 'Bitcoin Mainnet',
          time: '3分钟前',
          amount: '1,200 BTC',
          usd: '≈ \$115,704,000 USD',
          usdColor: McColors.tertiary,
          from: 'Binance',
          to: '未知安全冷钱包',
          fromColor: McColors.onSurfaceVariant,
          toColor: McColors.tertiary,
          arrowColor: McColors.tertiary,
          txHash: '8f42...a90b',
        ),
        _WhaleFeedItem(
          pillIcon: Icons.warning,
          pillText: '大额充值 · 潜在抛压',
          usdValue: 85500000,
          category: '充值',
          pillColor: McColors.error,
          chain: 'Ethereum',
          time: '14分钟前',
          amount: '25,000 ETH',
          usd: '≈ \$85,500,000 USD',
          usdColor: McColors.error,
          from: '神秘以太坊巨鲸',
          to: 'Coinbase',
          fromColor: McColors.error,
          toColor: McColors.onSurfaceVariant,
          arrowColor: McColors.error,
          txHash: '3c1a...7e2d',
        ),
        _WhaleFeedItem(
          pillIcon: Icons.sync_alt,
          pillText: '做市机构动向',
          usdValue: 15000000,
          category: '做市',
          pillColor: McColors.primary,
          chain: 'ERC-20',
          time: '21分钟前',
          amount: '15,000,000 USDT',
          usd: '≈ \$15,000,000 USD',
          usdColor: McColors.onSurfaceVariant,
          from: 'Wintermute',
          to: 'Kraken',
          fromColor: McColors.secondary,
          toColor: McColors.onSurfaceVariant,
          arrowColor: McColors.outline,
          txHash: '1d98...54fb',
        ),
        _WhaleFeedItem(
          pillIcon: Icons.local_fire_department,
          pillText: '大额链上交互 · 官方铸造',
          usdValue: 1000000000,
          category: '转账',
          pillColor: McColors.onSurface,
          pillNeutral: true,
          chain: 'TRON (TRC-20)',
          time: '45分钟前',
          amount: '1,000,000,000 USDT',
          usd: '流动性补给印钞',
          usdColor: McColors.tertiary,
          from: 'Tether Treasury',
          to: 'Authorized Inventory',
          fromColor: McColors.onSurfaceVariant,
          toColor: McColors.onSurface,
          arrowColor: McColors.outline,
          txHash: '92ef...63c8',
        ),
      ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_sourceReady) {
      _source = await McData.marketSource();
      _sourceReady = true;
      if (!mounted) return;
      // coinglass 首帧给链上 mock; free 保持空等真实 HL 数据.
      setState(() {
        if (_source == 'coinglass') _feedItems = _mockFeedItems();
      });
    }
    // 两块独立拉取, 互不影响; 任一失败静默保留对应 mock.
    await Future.wait<void>([_loadFeed(), _loadLiquidity()]);
  }

  Future<void> _loadFeed() async {
    try {
      final resp = await McData.overview('whale-alerts');
      final items = _parseAlerts(resp['alerts']);
      if (!mounted || items.isEmpty) return;
      setState(() => _feedItems = items);
    } on ApiException {
      // 503 未配置 / 502 上游错误 — 保留 mock.
    } catch (_) {
      // 网络/解析异常 — 保留 mock.
    }
  }

  Future<void> _loadLiquidity() async {
    try {
      final liq = await McData.liquidityOverview();
      if (!mounted || liq.isEmpty) return;
      setState(() => _liq = liq);
    } on ApiException {
      // 上游/后端异常 — 保留 mock.
    } catch (_) {
      // 网络/解析异常 — 保留 mock.
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
            ? '巨鲸减仓 · 空头异动'
            : (isLong ? '巨鲸加仓 · 多头异动' : '巨鲸仓位异动'),
        pillColor: accent,
        chain: 'Hyperliquid',
        time: _relTime(ts),
        amount: sizeUsd > 0
            ? '${_fmtUsd(sizeUsd)} $symbol'
            : '$symbol 仓位变动',
        usd: sizeUsd > 0 ? '≈ ${_fmtUsd(sizeUsd)} USD' : '仓位规模更新',
        usdColor: accent,
        from: _shortAddr(user),
        to: isShort ? '减仓/平仓' : (isLong ? '加仓/开仓' : '仓位调整'),
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
    if (addr.length <= 10) return addr.isEmpty ? '匿名巨鲸' : addr;
    return '${addr.substring(0, 6)}...${addr.substring(addr.length - 4)}';
  }

  static String _fmtUsd(double v) {
    final a = v.abs();
    if (a >= 1e9) return '\$${(v / 1e9).toStringAsFixed(2)}B';
    if (a >= 1e6) return '\$${(v / 1e6).toStringAsFixed(2)}M';
    if (a >= 1e3) return '\$${(v / 1e3).toStringAsFixed(1)}K';
    return '\$${v.toStringAsFixed(2)}';
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
    if (ms <= 0) return '刚刚';
    final dt =
        DateTime.fromMillisecondsSinceEpoch(ms > 100000000000 ? ms : ms * 1000);
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
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
          // 机构与聪明钱仅 CoinGlass 模式展示 (链上地址追踪无免费源)
          if (_source == 'coinglass') ...[
            const SizedBox(height: 20),
            _smartMoneySection(),
          ],
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
                    '链上流动性异动总览',
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
                      '24H 连续监听',
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
                  label: '稳定币总流通',
                  value: stableTotal != null ? _fmtCap(stableTotal) : '\$300.5B',
                  valueColor: McColors.onSurface,
                  delta: stableTotal != null ? _fmtPct(stableChg) : '+0.32%',
                  deltaColor: stableTotal != null
                      ? _pctColor(stableChg)
                      : McColors.bull,
                  caption: 'DefiLlama 全稳定币 24H',
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _metricBox(
                  label: 'DeFi 总锁仓 TVL',
                  value: tvlTotal != null ? _fmtCap(tvlTotal) : '\$94.6B',
                  valueColor: McColors.onSurface,
                  delta: tvlTotal != null ? _fmtPct(tvlChg) : '+0.85%',
                  deltaColor:
                      tvlTotal != null ? _pctColor(tvlChg) : McColors.bull,
                  caption: 'DefiLlama 全链锁仓 24H',
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
                          'TOP 稳定币 · 24H',
                          style: McText.sans(
                              size: 12,
                              weight: FontWeight.w600,
                              color: McColors.onSurfaceVariant),
                        ),
                      ],
                    ),
                    Text(
                      '流通 / 涨跌',
                      style: McText.sans(size: 12, color: McColors.outline),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (tops.isEmpty)
                  ..._mockStableRows()
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
          // filter pills: 链上分类 (提币/充值/做市/转账) 仅 coinglass 模式有数据
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _filterPill('全部', value: ''),
                if (_source == 'coinglass') ...[
                  _filterPill('提币囤积', value: '提币'),
                  _filterPill('充值抛压预警', value: '充值'),
                  _filterPill('做市机构动向', value: '做市'),
                  _filterPill('巨额转账', value: '转账'),
                ],
                _filterPill('合约仓位异动', value: '异动'),
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

  // mock 首帧的稳定币行 (真实数据未到时).
  List<Widget> _mockStableRows() {
    const mock = [
      ('USDT', 183.7e9, 0.00),
      ('USDC', 74.2e9, 0.01),
      ('DAI', 5.3e9, -0.02),
    ];
    return [
      for (var i = 0; i < mock.length; i++) ...[
        if (i > 0) const SizedBox(height: 8),
        _stableRow(StableCoin.fromJson({
          'name': mock[i].$1,
          'circulating_usd': mock[i].$2,
          'change_1d_pct': mock[i].$3,
        })),
      ],
    ];
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

  // 2. 机构与聪明钱地址追踪
  Widget _smartMoneySection() {
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
                  const Icon(Icons.psychology,
                      size: 18, color: McColors.secondary),
                  const SizedBox(width: 8),
                  Text(
                    '机构与聪明钱地址追踪',
                    style: McText.display(size: 18, weight: FontWeight.w600),
                  ),
                ],
              ),
              Text(
                'Top 3 深度异动',
                style: McText.sans(size: 12, color: McColors.outline),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _mmCard(
          initials: 'DW',
          initialsColor: McColors.primary,
          initialsBg: McColors.surfaceContainerHighest,
          name: 'DWF Labs',
          tag: '做市主力',
          tagColor: McColors.secondary,
          desc: '净充值主流衍生品所 \$18.5M',
          trailing: '部署流动性',
          trailingColor: McColors.outline,
        ),
        const SizedBox(height: 10),
        _mmCard(
          initials: 'JT',
          initialsColor: McColors.secondary,
          initialsBg: McColors.surfaceContainerHighest,
          name: 'Jump Trading',
          tag: '高频机构',
          tagColor: McColors.outline,
          tagNeutral: true,
          desc: '冷钱包转出 4,500 ETH 至托管',
          trailing: '内部调仓',
          trailingColor: McColors.outline,
        ),
        const SizedBox(height: 10),
        _mmCard(
          initials: '🐋',
          initialsColor: McColors.tertiary,
          initialsBg: McColors.tertiary.withValues(alpha: 0.3),
          name: '远古巨鲸 (0x7a8...9f21)',
          tag: '休眠激活',
          tagColor: McColors.tertiary,
          desc: '提取 1,200 BTC (\$115.7M) 入冷钱包',
          trailing: '长线囤积',
          trailingColor: McColors.tertiary,
        ),
      ],
    );
  }

  Widget _mmCard({
    required String initials,
    required Color initialsColor,
    required Color initialsBg,
    required String name,
    required String tag,
    required Color tagColor,
    bool tagNeutral = false,
    required String desc,
    required String trailing,
    required Color trailingColor,
  }) {
    final bool emoji = initials.runes.length > 2;
    return McCard(
      color: McColors.surfaceContainer,
      padding: const EdgeInsets.all(14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: initialsBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: emoji
                      ? Text(initials, style: const TextStyle(fontSize: 18))
                      : Text(
                          initials,
                          style: McText.sans(
                              size: 12,
                              weight: FontWeight.w700,
                              color: initialsColor),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: McText.sans(
                                  size: 12,
                                  weight: FontWeight.w600,
                                  color: McColors.onSurface),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: tagNeutral
                                  ? McColors.surfaceContainerHigh
                                  : tagColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              tag,
                              style: McText.sans(size: 12, color: tagColor),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        desc,
                        style: McText.sans(
                            size: 12, color: McColors.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            trailing,
            style: McText.sans(
                size: 12, weight: FontWeight.w500, color: trailingColor),
          ),
        ],
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
                    '实时异动高精时间线',
                    style: McText.display(size: 18, weight: FontWeight.w600),
                  ),
                ],
              ),
              Row(
                children: [
                  const McGlowDot(color: McColors.tertiary, size: 6),
                  const SizedBox(width: 6),
                  Text(
                    'WebSocket 已连通',
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
              child: Text('当前筛选下暂无异动',
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
                              color: item.pillNeutral
                                  ? McColors.surfaceContainerHigh
                                  : item.pillColor.withValues(alpha: 0.2),
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
                        '研判详情',
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
            _detailRow('金额', item.amount),
            _detailRow('估值', item.usd),
            _detailRow('链/网络', item.chain),
            _detailRow('转出方', item.from),
            _detailRow('接收方', item.to),
            _detailRow('TxHash', item.txHash),
            const SizedBox(height: 12),
            Text(
              '解读: 大额${item.to.contains('冷钱包') ? '提币至冷钱包通常意味着长线囤积, 短期抛压减小' : item.to.contains('减仓') || item.to.contains('平仓') ? '减仓平仓, 该巨鲸短期看空或止盈' : item.to.contains('加仓') || item.to.contains('开仓') ? '加仓开仓, 该巨鲸短期看多' : '转入交易所通常被视为潜在卖出信号, 需关注后续盘口承接'}。',
              style: McText.sans(
                  size: 12, height: 1.6, color: McColors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
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
    const options = <(String, double)>[
      ('全部', 0),
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
            Text('巨鲸预警阈值',
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
                    ? '预警阈值: ≥ ${_fmtUsd(_minUsd)}'
                    : '设置巨鲸预警阈值',
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

/// 时间线条目的不可变数据模型 (mock 与真实数据共用).
class _WhaleFeedItem {
  const _WhaleFeedItem({
    required this.pillIcon,
    required this.pillText,
    required this.pillColor,
    this.pillNeutral = false,
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
  final bool pillNeutral;
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

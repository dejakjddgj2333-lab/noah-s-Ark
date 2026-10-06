import 'dart:async';

import 'package:flutter/material.dart';

import '../core/coin_icon.dart';
import '../core/color_pref.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/data.dart';
import '../services/ticker_ws.dart';
import 'market_detail_page.dart';

/// 板块分类内部键 (中文, 亦作 _categories 查询键) → 显示文案.
String mktCatLabel(String key) {
  switch (key) {
    case '全部':
      return tr('mkt_cat_all');
    case 'Solana生态':
      return tr('mkt_cat_solana');
    default:
      return key; // Layer 1 / DeFi / AI Agent / Meme / RWA 等拉丁名不译
  }
}

/// 行情 board.
/// Reference: stitch_ref/home_market.html (content body only).
/// NOTE: this screen uses the Material-3 token palette, where outline /
/// on-surface-variant / secondary / error differ from the terminal screen.
class HomeMarketPage extends StatefulWidget {
  const HomeMarketPage({super.key});

  // Palette local to this screen (from home_market.html tailwind config).
  static const _onSurfVar = Color(0xFFC4C5D9); // on-surface-variant
  static const _outline = Color(0xFF8E90A2); // outline
  static const _outlineVar = Color(0xFF434656); // outline-variant
  static const _secondary = Color(0xFF9AECFF); // secondary
  static const _bull = Color(0xFF00E388); // tertiary
  static const _bullCont = Color(0xFF007E49); // tertiary-container
  // 涨跌红/绿已由 ColorPref 接管; _err 仅留作调色板定义 (跌色容器 _errCont 仍用).
  // ignore: unused_field
  static const _err = Color(0xFFFFB4AB); // error
  static const _errCont = Color(0xFF93000A); // error-container

  /// 主流币种白名单 (若后端返回则展示).
  static const _majors = [
    'BTC', 'ETH', 'SOL', 'XRP', 'DOGE', 'ADA', 'AVAX', 'LINK', 'NEAR', 'SUI',
  ];

  /// 板块分类 symbol 白名单 (客户端筛选).
  static const _categories = <String, List<String>>{
    'Layer 1': ['BTC', 'ETH', 'SOL', 'ADA', 'AVAX', 'NEAR', 'SUI'],
    'DeFi': ['UNI', 'AAVE', 'LINK', 'MKR', 'CRV', 'LDO'],
    'AI Agent': ['NEAR', 'FET', 'RNDR', 'WLD', 'TAO', 'GRT'],
    'Meme': ['DOGE', 'SHIB', 'PEPE', 'WIF', 'BONK', 'FLOKI'],
    'Solana生态': ['SOL', 'JUP', 'RAY', 'PYTH', 'WIF', 'BONK'],
    'RWA': ['ONDO', 'MKR', 'POLYX', 'TRU', 'CFG'],
  };

  @override
  State<HomeMarketPage> createState() => _HomeMarketPageState();
}

class _HomeMarketPageState extends State<HomeMarketPage> {
  /// 当前榜单排序: 0 成交额, 1 涨幅, 2 跌幅.
  int _sortIndex = 0;

  /// 当前板块筛选: 全部 / 自选 / Layer 1 / DeFi / AI Agent (客户端过滤).
  /// 值为 _categories 内部键 (中文), 显示时经 _catLabel 翻译.
  String _category = '全部';

  /// 真实行情行 (拉取成功后填充); 已加载但仍为空表示拉取失败.
  List<_RowData> _liveRows = [];

  /// 首轮行情是否已加载完成 (成功或失败都算); false 期间列表区显示骨架屏.
  bool _loaded = false;

  /// WS 实时推送订阅 (取消于 dispose).
  StreamSubscription<TickerPush>? _wsSub;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }

  /// 名义成交额 USD = 24H 成交量 * 现价 (排序/显示统一用名义值).
  static double _notional(OkxTicker t) => t.volCcy24h * t.last;

  Future<void> _load() async {
    try {
      final tickers = await McData.tickers(instType: 'SWAP');
      // 过滤主流币并按 24H 名义成交额(USD)排序, 同一 symbol 只留成交额最高的合约, 取前 10.
      final majors = tickers
          .where((t) => HomeMarketPage._majors.contains(t.symbol))
          .toList()
        ..sort((a, b) => _notional(b).compareTo(_notional(a)));
      final seen = <String>{};
      final top = majors.where((t) => seen.add(t.symbol)).take(10).toList();
      if (top.isEmpty) throw StateError('no major tickers');

      // 并行拉取前 6 行的分时线, 单个失败回退平线.
      final sparkSymbols = top.take(6).map((t) => t.symbol).toList();
      final sparks = await Future.wait(
        top.take(6).map((t) => McData.sparkline(t.instId).catchError(
            (_) => const <double>[0.5, 0.5, 0.5, 0.5, 0.5, 0.5])),
      );
      final sparkMap = <String, List<double>>{
        for (var i = 0; i < sparkSymbols.length; i++)
          sparkSymbols[i]: sparks[i].isEmpty
              ? const [0.5, 0.5, 0.5, 0.5, 0.5, 0.5]
              : sparks[i],
      };

      final rows = [
        for (final t in top) _buildRow(t, sparkMap[t.symbol]),
      ];
      if (!mounted) return;
      setState(() {
        _liveRows = rows;
        _loaded = true;
      });
      _subscribeLive(top.map((t) => t.instId).toSet());
    } catch (_) {
      // 后端不可用 / 数据异常 -> 标记已加载, 列表区显示空态而非假数据.
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  /// REST 加载成功后订阅 OKX WS 实时推送, 就地更新对应行.
  void _subscribeLive(Set<String> instIds) {
    _wsSub?.cancel();
    final ws = TickerWs.instance;
    ws.subscribe(instIds);
    _wsSub = ws.stream.listen((p) {
      if (!mounted) return;
      final idx = _liveRows.indexWhere((r) => r.instId == p.instId);
      if (idx < 0) return;
      final pct = p.changePct;
      final positive = pct >= 0;
      setState(() {
        _liveRows[idx] = _liveRows[idx].copyWith(
          vol: '24H ${_fmtVol(p.notionalUsd)}',
          price: _fmtPrice(p.last),
          note: '${tr('mkt_high')} ${_fmtPrice(p.high24h)}',
          noteColor: positive ? ColorPref.instance.bullColor : ColorPref.instance.bearColor,
          sparkColor: positive ? ColorPref.instance.bullColor : ColorPref.instance.bearColor,
          delta: _fmtDelta(pct),
          positive: positive,
          notional: p.notionalUsd,
          pct: pct,
        );
      });
    });
  }

  _RowData _buildRow(OkxTicker t, List<double>? spark) {
    final pct = t.changePct;
    final positive = pct >= 0;
    return _RowData(
      symbol: t.symbol,
      vol: '24H ${_fmtVol(_notional(t))}',
      price: _fmtPrice(t.last),
      note: '${tr('mkt_high')} ${_fmtPrice(t.high24h)}',
      noteColor: positive ? ColorPref.instance.bullColor : ColorPref.instance.bearColor,
      spark: (spark == null || spark.isEmpty)
          ? const [0.5, 0.5, 0.5, 0.5, 0.5, 0.5]
          : spark,
      sparkColor: positive ? ColorPref.instance.bullColor : ColorPref.instance.bearColor,
      delta: _fmtDelta(pct),
      positive: positive,
      alt: false, // 斑马纹由渲染序号决定
      instId: t.instId,
      notional: _notional(t),
      pct: pct,
    );
  }

  /// 依据当前榜单对行排序 (基于原始数值, 非格式化字符串).
  List<_RowData> _sorted(List<_RowData> rows) {
    final list = [...rows];
    switch (_sortIndex) {
      case 1: // 涨幅榜
        list.sort((a, b) => b.pct.compareTo(a.pct));
        break;
      case 2: // 跌幅榜
        list.sort((a, b) => a.pct.compareTo(b.pct));
        break;
      default: // 成交额榜 (名义 USD)
        list.sort((a, b) => b.notional.compareTo(a.notional));
    }
    return list;
  }

  /// 依据板块分类客户端过滤 (仅保留已拉取到的 symbol).
  List<_RowData> _categorized(List<_RowData> rows) {
    final symbols = HomeMarketPage._categories[_category];
    if (symbols == null) return rows; // 全部 -> 不过滤
    return rows.where((r) => symbols.contains(r.symbol)).toList();
  }

  /// 板块热力: 由真实榜单计算各板块平均涨跌 + 领涨币. null=行情未加载.
  List<_HeatTile>? _heatTiles() {
    if (_liveRows.isEmpty) return null;
    const sectors = ['AI Agent', 'Meme', 'Solana生态', 'DeFi'];
    final out = <_HeatTile>[];
    for (final s in sectors) {
      final whitelist = HomeMarketPage._categories[s]!;
      final rows =
          _liveRows.where((r) => whitelist.contains(r.symbol)).toList();
      if (rows.isEmpty) continue;
      final avg = rows.fold<double>(0, (a, r) => a + r.pct) / rows.length;
      final leader = rows.reduce((a, b) => a.pct >= b.pct ? a : b);
      final hot = avg.abs() >= 3;
      out.add(_HeatTile(
        name: mktCatLabel(s),
        pct: _fmtDelta(avg),
        leader:
            '${avg >= 0 ? tr('mkt_leader_up') : tr('mkt_leader_down')}: ${leader.symbol}',
        tag: avg >= 5
            ? tr('mkt_tag_breakout')
            : avg >= 2
                ? tr('mkt_tag_volume')
                : avg > -2
                    ? tr('mkt_tag_range')
                    : tr('mkt_tag_weak'),
        hot: hot,
        overlay: (avg.abs() / 50).clamp(0.02, 0.15),
        borderAlpha: hot ? 0.20 : 0.15,
        neg: avg < 0,
      ));
    }
    return out.isEmpty ? null : out;
  }

  static String _fmtPrice(double p) {
    if (p >= 1000) return '\$${_comma(p)}';
    if (p > 0 && p < 10) return '\$${p.toStringAsFixed(4)}';
    return '\$${p.toStringAsFixed(2)}';
  }

  static String _fmtVol(double v) {
    if (v >= 1e9) return '\$${(v / 1e9).toStringAsFixed(1)}B';
    if (v >= 1e6) return '\$${(v / 1e6).toStringAsFixed(0)}M';
    if (v >= 1e3) return '\$${(v / 1e3).toStringAsFixed(0)}K';
    return '\$${v.toStringAsFixed(0)}';
  }

  static String _fmtDelta(double pct) =>
      '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%';

  static String _comma(double v) {
    final fixed = v.toStringAsFixed(2);
    final dot = fixed.indexOf('.');
    final intPart = fixed.substring(0, dot);
    final buf = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      buf.write(intPart[i]);
      final remaining = intPart.length - i - 1;
      if (remaining > 0 && remaining % 3 == 0) buf.write(',');
    }
    return '$buf.${fixed.substring(dot + 1)}';
  }

  Future<void> _refresh() => _load();

  /// 列表区空态提示 (加载失败 / 板块为空).
  Widget _emptyHint(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      alignment: Alignment.center,
      child: Text(text,
          style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
    );
  }

  /// 点击行 -> 行情详情页. 无 instId 时由 symbol 推导.
  void _openDetail(_RowData row) {
    final instId =
        row.instId.isEmpty ? '${row.symbol}-USDT-SWAP' : row.instId;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            MarketDetailPage(instId: instId, symbol: row.symbol),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _categorized(_sorted(_liveRows));
    return RefreshIndicator(
      onRefresh: _refresh,
      color: McColors.primary,
      backgroundColor: McColors.surfaceContainer,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 32),
        children: [
          // 1. 全网市场热度概览卡片
          _MarketVitalsCard(
            category: _category,
            onCategory: (c) => setState(() => _category = c),
          ),
          const SizedBox(height: 20),

          // 2. 榜单切换胶囊 + 时间尺度控制器
          _ListControlBar(
            sortIndex: _sortIndex,
            onChanged: (i) => setState(() => _sortIndex = i),
          ),
          const SizedBox(height: 12),

          // 3. 专业行情数据列表: 未加载 -> 骨架屏; 加载失败 -> 空态; 否则真实榜单.
          if (!_loaded)
            McSkeleton.card(lines: 6, height: 16)
          else if (_liveRows.isEmpty)
            _emptyHint(tr('mkt_load_failed'))
          else if (rows.isEmpty)
            _emptyHint(tr('mkt_sector_empty'))
          else
            _MarketListCard(rows: rows, onRowTap: _openDetail),
          const SizedBox(height: 20),

          // 4. 板块轮动热力概览
          _SectorHeatmapCard(tiles: _heatTiles()),
          const SizedBox(height: 12),

          // 5. 底部系统监控心跳条
          const _HeartbeatBar(),
        ],
      ),
    );
  }
}

/// 1. 全网市场热度 + 板块筛选标签.
class _MarketVitalsCard extends StatefulWidget {
  const _MarketVitalsCard({required this.category, required this.onCategory});

  final String category;
  final ValueChanged<String> onCategory;

  @override
  State<_MarketVitalsCard> createState() => _MarketVitalsCardState();
}

class _MarketVitalsCardState extends State<_MarketVitalsCard> {
  // 横幅 vitals (mock 默认, 拉取成功后覆盖).
  String _mcTotal = '\$3.24T';
  String _mcDelta = '+2.84%';
  bool _mcDeltaUp = true;
  String _mcVolume = '\$142.8B';
  String _longPct = '64%';
  double _longFrac = 0.64;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Future.wait([_loadGlobal(), _loadLongShort()]);
  }

  Future<void> _loadGlobal() async {
    try {
      final g = await McData.globalStats();
      if (!mounted) return;
      final cap = g.totalMarketCapUsd;
      final vol = g.totalVolumeUsd;
      final chg = g.changePct24h;
      if (cap == null && vol == null && chg == null) return;
      setState(() {
        if (cap != null) _mcTotal = McData.fmtUsdCompact(cap);
        if (vol != null) _mcVolume = McData.fmtUsdCompact(vol);
        if (chg != null) {
          _mcDeltaUp = chg >= 0;
          _mcDelta = '${chg >= 0 ? '+' : ''}${chg.toStringAsFixed(2)}%';
        }
      });
    } catch (_) {/* 保留 mock */}
  }

  Future<void> _loadLongShort() async {
    try {
      final r = await McData.longShortRatio();
      if (!mounted) return;
      final lp = r.longPct;
      if (lp == null) return;
      setState(() {
        _longPct = '${lp.round()}%';
        _longFrac = (lp / 100).clamp(0.0, 1.0);
      });
    } catch (_) {/* 保留 mock */}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: McColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  children: [
                    const Icon(Icons.query_stats,
                        size: 18, color: McColors.primary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(tr('mkt_market_heat'),
                          overflow: TextOverflow.ellipsis,
                          style:
                              McText.sans(size: 13, weight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: McColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    const McGlowDot(color: HomeMarketPage._bull, size: 6),
                    const SizedBox(width: 6),
                    Text(
                      'BULL DOMINANT',
                      style: McText.sans(
                          size: 12,
                          weight: FontWeight.w700,
                          color: HomeMarketPage._bull,
                          letterSpacing: 1),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                Expanded(
                  child: _vital(
                    tr('ov_mcap_24h'),
                    _mcTotal,
                    valueColor: McColors.onSurface,
                    sub: Row(
                      children: [
                        Icon(
                            _mcDeltaUp
                                ? Icons.trending_up
                                : Icons.trending_down,
                            size: 12,
                            color: _mcDeltaUp
                                ? ColorPref.instance.bullColor
                                : ColorPref.instance.bearColor),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(_mcDelta,
                              overflow: TextOverflow.ellipsis,
                              style: McText.sans(
                                  size: 12,
                                  weight: FontWeight.w600,
                                  color: _mcDeltaUp
                                      ? ColorPref.instance.bullColor
                                      : ColorPref.instance.bearColor)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _vital(
                    tr('mkt_volume_24h'),
                    _mcVolume,
                    valueColor: McColors.onSurface,
                    sub: Text(tr('mkt_very_active'),
                        style: McText.sans(
                            size: 12, color: HomeMarketPage._outlineVar)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _vital(
                    tr('ov_long_index'),
                    _longPct,
                    valueColor: ColorPref.instance.bullColor,
                    sub: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Container(
                        height: 6,
                        color: McColors.surfaceContainerHighest,
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: _longFrac,
                          child: Container(
                            decoration: BoxDecoration(
                              color: ColorPref.instance.bullColor,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
          ),
          const SizedBox(height: 16),
          // 板块筛选标签 (横向滚动)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                _tag('全部'),
                _tag('Layer 1'),
                _tag('DeFi'),
                _tag('AI Agent', dot: true),
                _tag('Meme'),
                _tag('Solana生态'),
                _tag('RWA'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _vital(
    String label,
    String value, {
    required Color valueColor,
    required Widget sub,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 窄列不折行: 标签/数值超出时等比缩小
          SizedBox(
            height: 16,
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(label,
                  style:
                      McText.sans(size: 12, color: HomeMarketPage._outline)),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 20,
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: McText.sans(
                      size: 16, weight: FontWeight.w700, color: valueColor)),
            ),
          ),
          const SizedBox(height: 4),
          sub,
        ],
      ),
    );
  }

  Widget _tag(String text, {IconData? icon, bool dot = false}) {
    // 全部 + _categories 表内的分类均可点; 表外(null)即 全部 不过滤.
    final active = widget.category == text;
    final color = active
        ? McColors.onPrimaryContainer
        : (dot ? McColors.primary : HomeMarketPage._onSurfVar);
    return GestureDetector(
      onTap: () => widget.onCategory(text),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? McColors.primaryContainer
              : McColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: HomeMarketPage._secondary),
              const SizedBox(width: 6),
            ],
            Text(
              mktCatLabel(text),
              style: McText.sans(
                size: 12,
                weight: active ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
            if (dot) ...[
              const SizedBox(width: 6),
              const McGlowDot(color: HomeMarketPage._bull, size: 6),
            ],
          ],
        ),
      ),
    );
  }
}

/// 2. 榜单切换胶囊 + 24H 周期控制器.
class _ListControlBar extends StatelessWidget {
  const _ListControlBar({required this.sortIndex, required this.onChanged});

  final int sortIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: McColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _capsule(tr('mkt_sort_volume'), index: 0),
                _capsule(tr('mkt_sort_gainers'), index: 1),
                _capsule(tr('mkt_sort_losers'), index: 2),
              ],
            ),
          ),
          // 数据窗口标识 (OKX tickers 固定 24H, 不可切换)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text('24H',
                style: McText.sans(
                    size: 12,
                    weight: FontWeight.w700,
                    color: McColors.primary)),
          ),
        ],
      ),
    );
  }

  Widget _capsule(String text, {required int index}) {
    final active = sortIndex == index;
    return GestureDetector(
      onTap: () => onChanged(index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color:
              active ? McColors.surfaceContainerHighest : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: McText.sans(
            size: 12,
            weight: active ? FontWeight.w600 : FontWeight.w500,
            color: active ? McColors.onSurface : HomeMarketPage._outline,
          ),
        ),
      ),
    );
  }
}

/// 3. 专业行情数据列表.
class _MarketListCard extends StatelessWidget {
  const _MarketListCard({required this.rows, this.onRowTap});

  final List<_RowData> rows;
  final ValueChanged<_RowData>? onRowTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: McColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: HomeMarketPage._outlineVar.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            // 列头
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: McColors.surfaceContainerLowest,
                border: Border(
                  bottom: BorderSide(
                      color:
                          HomeMarketPage._outlineVar.withValues(alpha: 0.2)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(tr('mkt_col_pair_vol'), style: _headStyle()),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(tr('mkt_col_price'),
                        textAlign: TextAlign.right, style: _headStyle()),
                  ),
                  Expanded(
                    flex: 4,
                    child: Text(tr('mkt_col_trend'),
                        textAlign: TextAlign.right, style: _headStyle()),
                  ),
                ],
              ),
            ),
            for (var i = 0; i < rows.length; i++)
              _MarketRow(
                  data: rows[i],
                  alt: i.isEven,
                  isLast: i == rows.length - 1,
                  onTap: onRowTap == null ? null : () => onRowTap!(rows[i])),
          ],
        ),
      ),
    );
  }

  TextStyle _headStyle() => McText.sans(
      size: 12,
      weight: FontWeight.w600,
      color: HomeMarketPage._outline,
      letterSpacing: 1);
}

class _RowData {
  const _RowData({
    required this.symbol,
    required this.vol,
    required this.price,
    required this.note,
    required this.noteColor,
    required this.spark,
    required this.sparkColor,
    required this.delta,
    required this.positive,
    required this.alt,
    this.instId = '',
    this.notional = 0,
    this.pct = 0,
  });

  final String symbol;
  final String vol;
  final String price;
  final String note;
  final Color noteColor;
  final List<double> spark;
  final Color sparkColor;
  final String delta;
  final bool positive;
  final bool alt;

  /// 交易对 ID (如 BTC-USDT-SWAP), 缺省为 ''.
  final String instId;

  /// 名义成交额 USD (排序键), 涨跌幅原始值.
  final double notional;
  final double pct;

  _RowData copyWith({
    String? vol,
    String? price,
    String? note,
    Color? noteColor,
    Color? sparkColor,
    String? delta,
    bool? positive,
    double? notional,
    double? pct,
  }) =>
      _RowData(
        symbol: symbol,
        vol: vol ?? this.vol,
        price: price ?? this.price,
        note: note ?? this.note,
        noteColor: noteColor ?? this.noteColor,
        spark: spark,
        sparkColor: sparkColor ?? this.sparkColor,
        delta: delta ?? this.delta,
        positive: positive ?? this.positive,
        alt: alt,
        instId: instId,
        notional: notional ?? this.notional,
        pct: pct ?? this.pct,
      );
}

class _MarketRow extends StatelessWidget {
  const _MarketRow(
      {required this.data, required this.alt, required this.isLast, this.onTap});

  final _RowData data;
  final bool alt;
  final bool isLast;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final deltaColor =
        data.positive ? ColorPref.instance.bullColor : ColorPref.instance.bearColor;
    final deltaBg = data.positive
        ? HomeMarketPage._bullCont.withValues(alpha: 0.3)
        : HomeMarketPage._errCont.withValues(alpha: 0.4);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: alt ? McColors.surfaceContainer : McColors.surfaceContainerLow,
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                    color: HomeMarketPage._outlineVar.withValues(alpha: 0.15)),
              ),
      ),
      child: Row(
        children: [
          // 币种 / 成交额
          Expanded(
            flex: 5,
            child: Row(
              children: [
                CoinIcon(data.symbol, size: 36),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(data.symbol,
                                overflow: TextOverflow.ellipsis,
                                style: McText.sans(
                                    size: 14, weight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 4),
                          Text('/USDT',
                              style: McText.sans(
                                  size: 12, color: HomeMarketPage._outline)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(data.vol,
                          overflow: TextOverflow.ellipsis,
                          style: McText.sans(
                              size: 12, color: HomeMarketPage._outline)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 现价
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(data.price,
                        style: McText.sans(
                            size: 13, weight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 2),
                  Text(data.note,
                      overflow: TextOverflow.ellipsis,
                      style: McText.sans(size: 12, color: data.noteColor)),
                ],
              ),
            ),
          ),
          // 趋势 / 涨跌
          Expanded(
            flex: 4,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: McSparkline(
                      points: data.spark,
                      color: data.sparkColor,
                      width: 40,
                      height: 20,
                      strokeWidth: 1.75),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 62),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: deltaBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        data.delta,
                        style: McText.sans(
                            size: 12, weight: FontWeight.w600, color: deltaColor),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// 4. 板块轮动动能热力概览. tiles 由真实行情计算; null=加载中.
class _SectorHeatmapCard extends StatelessWidget {
  const _SectorHeatmapCard({required this.tiles});

  final List<_HeatTile>? tiles;

  @override
  Widget build(BuildContext context) {
    final list = tiles;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: McColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: HomeMarketPage._outlineVar.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  children: [
                    const Icon(Icons.grid_view,
                        size: 18, color: HomeMarketPage._secondary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(tr('mkt_heatmap_title'),
                          overflow: TextOverflow.ellipsis,
                          style:
                              McText.sans(size: 13, weight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(tr('mkt_okx_realtime'),
                  style: McText.sans(
                      size: 12,
                      color: HomeMarketPage._outline,
                      letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 14),
          if (list == null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(tr('mkt_sector_loading'),
                    style: McText.sans(
                        size: 12, color: HomeMarketPage._outline)),
              ),
            )
          else
            Column(
              children: [
                for (var i = 0; i < list.length; i += 2) ...[
                  if (i > 0) const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: list[i]),
                      const SizedBox(width: 12),
                      Expanded(
                          child: i + 1 < list.length
                              ? list[i + 1]
                              : const SizedBox()),
                    ],
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _HeatTile extends StatelessWidget {
  const _HeatTile({
    required this.name,
    required this.pct,
    required this.leader,
    required this.tag,
    required this.hot,
    required this.overlay,
    this.borderAlpha = 0.20,
    this.neg = false,
  });

  final String name;
  final String pct;
  final String leader;
  final String tag;
  final bool hot;
  final double overlay;
  final double borderAlpha;
  final bool neg;

  @override
  Widget build(BuildContext context) {
    final bull = ColorPref.instance.bullColor;
    final accent = neg ? ColorPref.instance.bearColor : bull;
    final borderColor = hot
        ? accent.withValues(alpha: borderAlpha)
        : HomeMarketPage._outlineVar.withValues(alpha: 0.2);
    return Container(
      constraints: const BoxConstraints(minHeight: 78),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(color: accent.withValues(alpha: overlay)),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(name,
                        overflow: TextOverflow.ellipsis,
                        style: McText.sans(size: 13, weight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 6),
                  Text(pct,
                      style: McText.sans(
                          size: 12, weight: FontWeight.w700, color: accent)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(leader,
                        overflow: TextOverflow.ellipsis,
                        style: McText.sans(
                            size: 12, color: HomeMarketPage._outline)),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: hot
                          ? accent.withValues(alpha: 0.15)
                          : McColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      tag,
                      style: McText.sans(
                        size: 12,
                        weight: hot ? FontWeight.w600 : FontWeight.w500,
                        color: hot ? accent : HomeMarketPage._outline,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 5. 底部系统监控心跳条.
class _HeartbeatBar extends StatelessWidget {
  const _HeartbeatBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: HomeMarketPage._outlineVar.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Row(
              children: [
                const McGlowDot(color: HomeMarketPage._bull, size: 8),
                const SizedBox(width: 8),
                Text(tr('mkt_data_source'),
                    style: McText.mono(
                        size: 12, color: HomeMarketPage._outline)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(tr('mkt_heartbeat_right'),
              style: McText.mono(size: 12, color: HomeMarketPage._outline)),
        ],
      ),
    );
  }
}

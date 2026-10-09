import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/coin_icon.dart';
import '../core/color_pref.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/api.dart';
import '../services/data.dart';
import '../services/ticker_ws.dart';
import 'market_detail_page.dart';

/// 首页 · 综合看板 — 聚合各分板核心指标的总览页.
///
/// 各卡片尝试接真实后端: 情绪 ← sentiment, 24H爆仓 ← liquidations,
/// 主流资产 ← OKX tickers+K线, 资金费率 ← funding. 首屏先显示骨架屏,
/// 首次加载完成后展示真实数据; 加载失败的字段显示 '--' 或空态, 绝不显示
/// 编造的假数字.
class HomeOverviewPage extends StatefulWidget {
  const HomeOverviewPage({super.key});

  @override
  State<HomeOverviewPage> createState() => _HomeOverviewPageState();
}

class _HomeOverviewPageState extends State<HomeOverviewPage> {
  /// 首次加载是否已完成 (成功或失败都算); false 时整页显示骨架屏.
  bool _loaded = false;

  // ---- 情绪指数卡 ----
  String? _sentimentValue;
  String? _sentimentLabel;
  Color _sentimentColor = McColors.bull;
  String? _sentimentSub;

  // ---- 24H 爆仓迷你卡 ----
  String? _liqTotal;
  double? _liqLongFrac;
  String? _liqLongText;
  String? _liqShortText;

  // ---- 资金费率迷你卡 ----
  String? _fundingRate;
  // 费率进度条 (-0.05%..+0.05% 映射) 与山寨季指数 (null=未加载).
  double? _fundingFrac;
  double? _altSeason;

  // ---- 市场全景横幅 ----
  String? _mcTotal;
  String? _mcDelta;
  bool _mcDeltaUp = true;
  String? _mcVolume;
  String? _longPct;
  double? _longFrac;

  // ---- 巨鲸异动速递 ----
  List<_WhaleItem> _whaleItems = const [];

  // ---- 主流资产速览 ----
  List<_AssetRow> _assets = const [];

  // ---- 主流资产实时推送 (OKX WS, 失败静默保留 REST 数据) ----
  StreamSubscription<TickerPush>? _tickerSub;
  static const _watchSymbols = ['BTC', 'ETH', 'SOL', 'SUI'];

  @override
  void initState() {
    super.initState();
    _restoreCache();
    _load();
    _subscribeTickers();
  }

  // 首屏缓存: 上次行情行落地到本地, 冷启动秒显, 网络回来再覆盖.
  static const _cacheKey = 'overview_assets_v1';

  Future<void> _restoreCache() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_cacheKey);
      if (raw == null || !mounted || _assets.isNotEmpty) return;
      final list = (jsonDecode(raw) as List)
          .map((e) => _AssetRow(
                e['symbol'] as String,
                e['pair'] as String,
                e['price'] as String,
                e['delta'] as String,
                e['up'] as bool,
                const [],
              ))
          .toList();
      if (list.isNotEmpty) setState(() => _assets = list);
    } catch (_) {/* 缓存损坏则忽略 */}
  }

  void _persistCache() {
    final rows = _assets
        .map((r) => {
              'symbol': r.symbol,
              'pair': r.pair,
              'price': r.price,
              'delta': r.delta,
              'up': r.up,
            })
        .toList();
    SharedPreferences.getInstance().then(
        (sp) => sp.setString(_cacheKey, jsonEncode(rows)),
        onError: (_) {});
  }

  @override
  void dispose() {
    _tickerSub?.cancel();
    super.dispose();
  }

  // REST 加载后订阅 4 个合约的实时推送, 命中行就地刷新价格与涨跌幅.
  void _subscribeTickers() {
    final instIds = {for (final s in _watchSymbols) '$s-USDT-SWAP'};
    TickerWs.instance.subscribe(instIds);
    _tickerSub = TickerWs.instance.stream.listen(
      _onTicker,
      onError: (_) {}, // WS 异常静默, 保留 REST 数据
    );
  }

  void _onTicker(TickerPush t) {
    if (!mounted) return;
    final symbol = t.instId.split('-').first;
    final idx = _assets.indexWhere((r) => r.symbol == symbol);
    if (idx < 0) return;
    final up = t.changePct >= 0;
    setState(() {
      final list = [..._assets];
      list[idx] = list[idx].copyWith(
        price: _fmtPrice(t.last),
        delta: '${up ? '+' : ''}${t.changePct.toStringAsFixed(2)}%',
        up: up,
      );
      _assets = list;
    });
  }

  Future<void> _load() async {
    // 首屏门槛只等最快的两个源 (情绪+行情), ~1s 脱离骨架屏;
    // 其余 (爆仓/资金费率/多空/山寨季/市值/巨鲸) 后台各自 setState, 不拖首屏.
    try {
      await Future.wait([_loadSentiment(), _loadAssets()]);
    } finally {
      if (mounted && !_loaded) setState(() => _loaded = true);
    }
    _loadLiquidation();
    _loadFunding();
    _loadLongShort();
    _loadAltSeason();
    _loadGlobalBanner();
    _loadWhales();
  }

  Future<void> _loadGlobalBanner() async {
    try {
      final g = await McData.globalStats();
      if (!mounted) return;
      final cap = g.totalMarketCapUsd;
      final vol = g.totalVolumeUsd;
      final chg = g.changePct24h;
      if (cap == null && vol == null && chg == null) return; // 全 null -> 保留空态
      setState(() {
        if (cap != null) _mcTotal = McData.fmtUsdCompact(cap);
        if (vol != null) _mcVolume = McData.fmtUsdCompact(vol);
        if (chg != null) {
          _mcDeltaUp = chg >= 0;
          _mcDelta = '${chg >= 0 ? '+' : ''}${chg.toStringAsFixed(2)}%';
        }
      });
    } on ApiException {
      // 保留空态.
    } catch (_) {}
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
    } on ApiException {
      // 保留空态.
    } catch (_) {}
  }

  Future<void> _loadWhales() async {
    try {
      final resp = await McData.overview('whale-alerts');
      final items = _parseWhaleAlerts(resp['alerts']);
      if (!mounted || items.isEmpty) return;
      setState(() => _whaleItems = items);
    } on ApiException {
      // 保留空态.
    } catch (_) {}
  }

  // Hyperliquid whale-alert → 速递条目 (取前 3, best-effort).
  static List<_WhaleItem> _parseWhaleAlerts(dynamic raw) {
    final list = _asList(raw);
    final out = <_WhaleItem>[];
    for (final e in list) {
      if (e is! Map) continue;
      final m = e.cast<String, dynamic>();
      final symbol = (m['symbol'] ?? m['coin'] ?? '').toString();
      if (symbol.isEmpty) continue;
      final user = (m['user'] ?? m['address'] ?? '').toString();
      final usd = _num(m['position_value_usd'] ??
          m['positionValueUsd'] ??
          m['usd_value'] ??
          m['positionSize'] ??
          m['positionValue']);
      final action = _num(m['position_action'] ?? m['action']);
      // position_action: 1 开仓/加仓, 2 平仓/减仓 (CoinGlass Hyperliquid).
      final isAdd = action == 1;
      final isReduce = action == 2;
      final color = isReduce
          ? ColorPref.instance.bearColor
          : (isAdd ? ColorPref.instance.bullColor : McColors.primary);
      final pill = isReduce
          ? tr('whale_pill_reduce')
          : (isAdd ? tr('whale_pill_add') : tr('whale_pill_move'));
      final emoji = isReduce ? '⚠️' : (isAdd ? '🐋' : '⚡');
      final verb = isReduce
          ? tr('whale_verb_reduce')
          : (isAdd ? tr('whale_verb_add') : tr('whale_verb_move'));
      out.add(_WhaleItem(
        emoji: emoji,
        pillText: pill,
        pillColor: color,
        time: _relTime(m['create_time'] ?? m['createTime'] ?? m['time']),
        body: tr('ov_whale_body')
            .replaceAll('{addr}', _shortAddr(user))
            .replaceAll('{verb}', verb)
            .replaceAll('{symbol}', symbol)
            .replaceAll('{usd}', _fmtUsdZh(usd)),
      ));
      if (out.length >= 3) break;
    }
    return out;
  }

  static String _shortAddr(String addr) {
    if (addr.length <= 10) return addr.isEmpty ? tr('whale_anon') : addr;
    return '${addr.substring(0, 6)}...${addr.substring(addr.length - 4)}';
  }

  static String _relTime(dynamic ts) {
    final ms = ts is num ? ts.toInt() : int.tryParse('$ts') ?? 0;
    if (ms <= 0) return tr('time_just_now');
    final dt = DateTime.fromMillisecondsSinceEpoch(ms > 100000000000 ? ms : ms * 1000);
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

  Future<void> _loadSentiment() async {
    try {
      final resp = await McData.overview('sentiment');
      final v = _fearGreedValue(resp['fear_greed']);
      if (v == null || !mounted) return;
      final (label, color) = _fearGreedLabel(v);
      setState(() {
        _sentimentValue = v.round().toString();
        _sentimentLabel = label;
        _sentimentColor = color;
        _sentimentSub = tr('ov_senti_sub').replaceAll('{label}', label);
      });
    } on ApiException {
      // 保留空态.
    } catch (_) {}
  }

  Future<void> _loadLiquidation() async {
    try {
      final resp =
          await McData.overview('liquidations/exchange-list?range=24h');
      final sums = _liqSums(resp['data']);
      if (sums == null || !mounted) return;
      final (total, long, short) = sums;
      if (total <= 0) return;
      setState(() {
        _liqTotal = _fmtUsdZh(total);
        _liqLongFrac = (long + short) <= 0 ? 0.5 : long / (long + short);
        _liqLongText = _fmtUsdZh(long);
        _liqShortText = _fmtUsdZh(short);
      });
    } on ApiException {
      // 保留空态.
    } catch (_) {}
  }

  Future<void> _loadFunding() async {
    try {
      final resp = await McData.overview('funding/exchange-rates?symbol=BTC');
      final avg = _avgFundingRate(resp['data']);
      if (avg == null || !mounted) return;
      setState(() {
        _fundingRate = '${avg >= 0 ? '+' : ''}${avg.toStringAsFixed(4)}%';
        _fundingFrac = ((avg + 0.05) / 0.1).clamp(0.02, 0.98);
      });
    } on ApiException {
      // 保留空态.
    } catch (_) {}
  }

  // 山寨季指数 (free 源 CoinGecko 自算 / coinglass 原生).
  Future<void> _loadAltSeason() async {
    try {
      final resp = await McData.overview('indicators');
      final list = resp['indicators'];
      if (list is! List || !mounted) return;
      for (final e in list) {
        if (e is! Map || e['key'] != 'altcoin_season') continue;
        final v = e['value'];
        if (v is num) setState(() => _altSeason = v.toDouble());
      }
    } on ApiException {
      // 未加载, 卡片显示 --
    } catch (_) {}
  }

  Future<void> _loadAssets() async {
    List<OkxTicker> tickers;
    try {
      tickers = await McData.tickers();
    } on ApiException {
      return; // 保留空态.
    } catch (_) {
      return;
    }
    if (!mounted) return;

    // 按关注列表从 tickers 组建行, 缺数据的币种直接缺席, 不造假.
    final rows = <_AssetRow>[];
    for (final sym in _watchSymbols) {
      OkxTicker? t;
      for (final x in tickers) {
        if (x.symbol == sym) {
          t = x;
          break;
        }
      }
      if (t == null) continue;
      final up = t.changePct >= 0;
      rows.add(_AssetRow(
        sym,
        '/USDT',
        _fmtPrice(t.last),
        '${up ? '+' : ''}${t.changePct.toStringAsFixed(2)}%',
        up,
        const [],
      ));
    }
    if (rows.isNotEmpty && mounted) {
      setState(() => _assets = rows);
      _persistCache();
    }

    // K线 sparkline: 后台并行补齐, 失败保持无曲线, 不阻塞首屏.
    unawaited(Future.wait(rows.map((row) async {
      try {
        final spark = await McData.sparkline('${row.symbol}-USDT-SWAP');
        if (spark.length >= 2 && mounted) {
          setState(() {
            final list = [..._assets];
            final idx = list.indexWhere((r) => r.symbol == row.symbol);
            if (idx < 0) return;
            list[idx] = list[idx].copyWith(spark: spark);
            _assets = list;
          });
        }
      } on ApiException {
        // 无曲线.
      } catch (_) {}
    })));
  }

  // ---- 解析/格式化辅助 ----
  static double? _fearGreedValue(dynamic raw) {
    if (raw is num) return raw.toDouble();
    if (raw is Map) {
      final v = raw['value'] ?? raw['fearGreed'] ?? raw['score'];
      if (v is num) return v.toDouble();
      return double.tryParse('$v');
    }
    return double.tryParse('$raw');
  }

  static (String, Color) _fearGreedLabel(double v) {
    if (v < 25) return (tr('senti_extreme_fear'), ColorPref.instance.bearColor);
    if (v < 45) return (tr('senti_fear'), ColorPref.instance.bearColor);
    if (v < 56) return (tr('senti_neutral'), McColors.onSurfaceVariant);
    if (v < 75) return (tr('senti_greed'), ColorPref.instance.bullColor);
    return (tr('senti_extreme_greed'), ColorPref.instance.bullColor);
  }

  static (double, double, double)? _liqSums(dynamic raw) {
    final list = _asList(raw);
    if (list.isEmpty) return null;
    double total = 0, long = 0, short = 0;
    for (final e in list) {
      if (e is! Map) continue;
      // 跳过 All 聚合行, 避免重复计数
      if ((e['exchange'] ?? '').toString().toLowerCase() == 'all') continue;
      final l = _num(e['longLiquidation_usd'] ??
          e['longLiquidationUsd'] ??
          e['long_liquidation_usd'] ??
          e['longLiquidation'] ??
          e['longVolUsd']);
      final s = _num(e['shortLiquidation_usd'] ??
          e['shortLiquidationUsd'] ??
          e['short_liquidation_usd'] ??
          e['shortLiquidation'] ??
          e['shortVolUsd']);
      var t = _num(e['liquidationUsd'] ??
          e['liquidation_usd'] ??
          e['totalLiquidationUsd'] ??
          e['volUsd']);
      if (t <= 0) t = l + s;
      total += t;
      long += l;
      short += s;
    }
    return total > 0 ? (total, long, short) : null;
  }

  static double? _avgFundingRate(dynamic raw) {
    final list = _asList(raw);
    if (list.isEmpty) return null;
    final rates = <double>[];
    for (final e in list) {
      if (e is! Map) continue;
      final r = _num(e['fundingRate'] ?? e['rate'] ?? e['funding_rate']);
      // CoinGlass 费率常为百分数; 兼容小数形式.
      rates.add(r.abs() < 0.001 && r != 0 ? r * 100 : r);
    }
    if (rates.isEmpty) return null;
    return rates.reduce((a, b) => a + b) / rates.length;
  }

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

  static String _fmtUsdZh(double v) {
    final a = v.abs();
    if (a >= 1e8) return '\$${(v / 1e8).toStringAsFixed(2)}亿';
    if (a >= 1e4) return '\$${(v / 1e4).toStringAsFixed(1)}万';
    return '\$${v.toStringAsFixed(2)}';
  }

  static String _fmtPrice(double v) {
    if (v >= 1000) return '\$${_addCommas(v.toStringAsFixed(2))}';
    if (v >= 1) return '\$${v.toStringAsFixed(2)}';
    return '\$${v.toStringAsFixed(4)}';
  }

  static String _addCommas(String numStr) {
    final parts = numStr.split('.');
    final intPart = parts[0];
    final buf = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      final posFromEnd = intPart.length - i;
      buf.write(intPart[i]);
      if (posFromEnd > 1 && posFromEnd % 3 == 1) buf.write(',');
    }
    if (parts.length > 1) {
      buf.write('.');
      buf.write(parts[1]);
    }
    return buf.toString();
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
          // 1. 市场全景横幅
          if (!_loaded) McSkeleton.card(lines: 3) else _marketBanner(),
          const SizedBox(height: 16),
          // 2. 情绪 + 爆仓 双子卡 (定高对齐; IntrinsicHeight 与 Expanded 基线冲突不可用)
          SizedBox(
            height: 156,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: !_loaded
                      ? McSkeleton.card(lines: 3)
                      : _SentimentCard(
                          value: _sentimentValue,
                          label: _sentimentLabel,
                          color: _sentimentColor,
                          sub: _sentimentSub,
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: !_loaded
                      ? McSkeleton.card(lines: 3)
                      : _LiquidationMiniCard(
                          total: _liqTotal,
                          longFrac: _liqLongFrac,
                          longText: _liqLongText,
                          shortText: _liqShortText,
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 3. 主流资产速览
          McSectionHeader(
            title: tr('ov_section_assets'),
            icon: Icons.trending_up,
            trailing: '24H',
          ),
          const SizedBox(height: 10),
          if (!_loaded) McSkeleton.card(lines: 4) else _assetList(),
          const SizedBox(height: 16),
          // 4. 巨鲸异动最新
          McSectionHeader(
            title: tr('ov_section_whale'),
            icon: Icons.radar,
            trailing: tr('ov_whale_syncing'),
            trailingColor: McColors.bull,
          ),
          const SizedBox(height: 10),
          if (!_loaded) McSkeleton.card(lines: 2) else _whaleFeed(),
          const SizedBox(height: 16),
          // 5. 资金费率 + 山寨季 双子卡 (定高对齐)
          SizedBox(
            height: 156,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: !_loaded
                      ? McSkeleton.card(lines: 3)
                      : _FundingMiniCard(
                          rate: _fundingRate, fraction: _fundingFrac),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: !_loaded
                      ? McSkeleton.card(lines: 3)
                      : _AltSeasonCard(value: _altSeason),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 全网市场全景横幅
  Widget _marketBanner() {
    return McCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(tr('ov_market_banner'),
                    overflow: TextOverflow.ellipsis,
                    style:
                        McText.sans(size: 13, weight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              const McGlowDot(color: McColors.bull),
              const SizedBox(width: 6),
              Text('BULL DOMINANT',
                  style: McText.mono(
                      size: 12,
                      weight: FontWeight.w700,
                      color: McColors.bull,
                      letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _vital(tr('ov_mcap_24h'), _mcTotal, _mcDelta, _mcDeltaUp),
              _vital(tr('ov_volume_24h'), _mcVolume, null, null),
              _vital(tr('ov_long_index'), _longPct, null, null, bar: _longFrac),
            ],
          ),
        ],
      ),
    );
  }

  Widget _vital(String label, String? value, String? delta, bool? up,
      {double? bar}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(value ?? '--',
              style: McText.display(size: 18, weight: FontWeight.w700)),
          if (delta != null) ...[
            const SizedBox(height: 2),
            Text(delta,
                style: McText.mono(
                    size: 12,
                    weight: FontWeight.w600,
                    color: up == true ? ColorPref.instance.bullColor : ColorPref.instance.bearColor)),
          ],
          if (bar != null) ...[
            const SizedBox(height: 6),
            McProgressBar(fraction: bar, color: ColorPref.instance.bullColor, height: 4),
          ],
        ],
      ),
    );
  }

  // 主流资产行
  Widget _assetList() {
    if (_assets.isEmpty) {
      return McCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: Text(tr('ov_no_assets'),
                style:
                    McText.mono(size: 12, color: McColors.onSurfaceVariant)),
          ),
        ),
      );
    }
    return McCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < _assets.length; i++) ...[
            if (i > 0)
              Divider(
                  height: 1,
                  color: McColors.outlineVariant.withValues(alpha: 0.3)),
            _assetRow(_assets[i]),
          ],
        ],
      ),
    );
  }

  Widget _assetRow(_AssetRow r) {
    final c = r.up ? ColorPref.instance.bullColor : ColorPref.instance.bearColor;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MarketDetailPage(
            instId: '${r.symbol}-USDT-SWAP',
            symbol: r.symbol,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          CoinIcon(r.symbol, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(r.symbol,
                        style: McText.sans(
                            size: 14, weight: FontWeight.w700)),
                    Text(r.pair,
                        style: McText.sans(
                            size: 12, color: McColors.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ),
          McSparkline(points: r.spark, color: c, width: 56, height: 22),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(r.price,
                  style:
                      McText.mono(size: 12, weight: FontWeight.w700)),
              McDeltaBadge(r.delta, positive: r.up),
            ],
          ),
        ],
      ),
      ),
    );
  }

  // 巨鲸异动速递 (实时, 失败显示空态)
  Widget _whaleFeed() {
    if (_whaleItems.isEmpty) {
      return McCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: Text(tr('ov_no_whale'),
                style:
                    McText.mono(size: 12, color: McColors.onSurfaceVariant)),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < _whaleItems.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _whaleCard(
            emoji: _whaleItems[i].emoji,
            pillText: _whaleItems[i].pillText,
            pillColor: _whaleItems[i].pillColor,
            time: _whaleItems[i].time,
            body: _whaleItems[i].body,
          ),
        ],
      ],
    );
  }

  Widget _whaleCard({
    required String emoji,
    required String pillText,
    required Color pillColor,
    required String time,
    required String body,
  }) {
    return McCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: pillColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: pillColor.withValues(alpha: 0.3)),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 14)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    McPill(pillText, color: pillColor),
                    Text(time,
                        style: McText.mono(
                            size: 12, color: McColors.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(body,
                    style: McText.sans(size: 12, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 巨鲸异动速递条目的不可变数据模型.
class _WhaleItem {
  const _WhaleItem({
    required this.emoji,
    required this.pillText,
    required this.pillColor,
    required this.time,
    required this.body,
  });

  final String emoji;
  final String pillText;
  final Color pillColor;
  final String time;
  final String body;
}

/// 主流资产行的不可变数据模型.
class _AssetRow {
  const _AssetRow(this.symbol, this.pair, this.price, this.delta,
      this.up, this.spark);

  final String symbol;
  final String pair;
  final String price;
  final String delta;
  final bool up;
  final List<double> spark;

  _AssetRow copyWith({
    String? price,
    String? delta,
    bool? up,
    List<double>? spark,
  }) {
    return _AssetRow(
      symbol,
      pair,
      price ?? this.price,
      delta ?? this.delta,
      up ?? this.up,
      spark ?? this.spark,
    );
  }
}

/// 情绪指数卡. value/label/sub 为 null 时显示占位, 不造假数字.
class _SentimentCard extends StatelessWidget {
  const _SentimentCard({
    required this.value,
    required this.label,
    required this.color,
    required this.sub,
  });

  final String? value;
  final String? label;
  final Color color;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return McCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology,
                  size: 15, color: McColors.primaryContainer),
              const SizedBox(width: 4),
              Text(tr('ov_sentiment_index'),
                  style: McText.sans(
                      size: 12,
                      weight: FontWeight.w500,
                      color: McColors.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value ?? '--',
                  style: McText.display(size: 24, weight: FontWeight.w700)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label ?? '',
                    style: McText.sans(
                        size: 12,
                        weight: FontWeight.w600,
                        color: color)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 5 段仪表条
          Container(
            height: 6,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: McColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Row(
              children: [
                _seg(const Color(0x66FF6363)),
                _seg(const Color(0xB3FF6363)),
                _seg(const Color(0x99F59E0B)),
                _seg(McColors.primaryContainer, glow: true),
                _seg(McColors.surfaceVariant.withValues(alpha: 0.4)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(sub ?? tr('no_data'),
              style: McText.mono(size: 12, color: McColors.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _seg(Color color, {bool glow = false}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            boxShadow: glow
                ? [
                    BoxShadow(
                        color: McColors.primaryContainer.withValues(alpha: 0.8),
                        blurRadius: 8)
                  ]
                : null,
          ),
        ),
      ),
    );
  }
}

/// 多空爆仓迷你卡. 各字段为 null 时显示占位, 不造假数字.
class _LiquidationMiniCard extends StatelessWidget {
  const _LiquidationMiniCard({
    required this.total,
    required this.longFrac,
    required this.longText,
    required this.shortText,
  });

  final String? total;
  final double? longFrac;
  final String? longText;
  final String? shortText;

  @override
  Widget build(BuildContext context) {
    final lf = longFrac?.clamp(0.0, 1.0);
    return McCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const McGlowDot(color: McColors.bear),
              const SizedBox(width: 4),
              Text(tr('ov_liq_24h'),
                  style: McText.sans(
                      size: 12,
                      weight: FontWeight.w500,
                      color: McColors.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 12),
          Text(total ?? '--',
              style: McText.display(
                  size: 20, weight: FontWeight.w700, color: McColors.bear)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: lf == null
                  ? Container(
                      color:
                          McColors.surfaceVariant.withValues(alpha: 0.4))
                  : Row(
                      children: [
                        Expanded(
                          flex: (lf * 1000).round(),
                          child: Container(color: McColors.bear),
                        ),
                        Expanded(
                          flex: ((1 - lf) * 1000).round(),
                          child: Container(color: McColors.bull),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
              longText == null
                  ? tr('no_data')
                  : tr('ov_liq_long_short')
                      .replaceAll('{long}', longText ?? '--')
                      .replaceAll('{short}', shortText ?? '--'),
              style: McText.mono(size: 12, color: McColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// 资金费率迷你卡. rate/fraction 为 null 时显示占位, 不造假数字.
class _FundingMiniCard extends StatelessWidget {
  const _FundingMiniCard({required this.rate, required this.fraction});

  final String? rate;
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    final neg = rate?.startsWith('-') ?? false;
    final color = neg ? McColors.bear : McColors.bull;
    return McCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.currency_exchange,
                  size: 15, color: McColors.primaryContainer),
              const SizedBox(width: 4),
              Flexible(
                child: Text(tr('ov_funding_weighted'),
                    overflow: TextOverflow.ellipsis,
                    style: McText.sans(
                        size: 12,
                        weight: FontWeight.w500,
                        color: McColors.onSurfaceVariant)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(rate ?? '--',
              style: McText.mono(
                  size: 20, weight: FontWeight.w700, color: color)),
          const SizedBox(height: 8),
          McProgressBar(fraction: fraction ?? 0, color: color),
          const SizedBox(height: 12),
          Text(
              rate == null
                  ? tr('no_data')
                  : '${neg ? tr('ov_short_pays') : tr('ov_long_pays')} · ${tr('ov_settle_8h')}',
              style: McText.mono(size: 12, color: McColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// 山寨季指数卡. value=null 显示 --.
class _AltSeasonCard extends StatelessWidget {
  const _AltSeasonCard({required this.value});

  final double? value;

  @override
  Widget build(BuildContext context) {
    final v = value;
    return McCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.grid_view,
                  size: 15, color: McColors.primaryContainer),
              const SizedBox(width: 4),
              Flexible(
                child: Text(tr('ov_alt_season'),
                    overflow: TextOverflow.ellipsis,
                    style: McText.sans(
                        size: 12,
                        weight: FontWeight.w500,
                        color: McColors.onSurfaceVariant)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(v == null ? '--' : v.round().toString(),
                  style: McText.mono(size: 20, weight: FontWeight.w700)),
              Text(' /100',
                  style: McText.mono(
                      size: 12, color: McColors.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          McProgressBar(
              fraction: v == null ? 0 : (v / 100).clamp(0.0, 1.0),
              color: McColors.primaryContainer),
          const SizedBox(height: 12),
          Text(
              v == null
                  ? tr('no_data')
                  : v >= 75
                      ? tr('ov_alt_in_season')
                      : v <= 25
                          ? tr('ov_btc_season')
                          : tr('ov_alt_gap')
                              .replaceAll('{n}', '${(75 - v).round()}'),
              style: McText.mono(size: 12, color: McColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

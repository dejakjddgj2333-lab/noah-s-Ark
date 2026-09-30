import 'dart:async';

import 'package:flutter/material.dart';

import '../core/coin_icon.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/api.dart';
import '../services/data.dart';
import '../services/ticker_ws.dart';
import 'market_detail_page.dart';

/// 首页 · 综合看板 — 聚合各分板核心指标的总览页.
///
/// 各卡片尝试接真实后端: 情绪 ← sentiment, 24H爆仓 ← liquidations,
/// 主流资产 ← OKX tickers+K线, 资金费率 ← funding. 失败(未配置 CoinGlass/
/// 上游错误/后端未启动)时静默保留内置 mock, 永不红屏.
class HomeOverviewPage extends StatefulWidget {
  const HomeOverviewPage({super.key});

  @override
  State<HomeOverviewPage> createState() => _HomeOverviewPageState();
}

class _HomeOverviewPageState extends State<HomeOverviewPage> {
  // ---- 情绪指数卡 (mock 默认) ----
  String _sentimentValue = '74';
  String _sentimentLabel = '贪婪';
  Color _sentimentColor = McColors.bull;
  String _sentimentSub = '昨日 68 · 贪婪';

  // ---- 24H 爆仓迷你卡 (mock 默认) ----
  String _liqTotal = '\$3.82 亿';
  double _liqLongFrac = 0.56;
  String _liqLongText = '\$2.14亿';
  String _liqShortText = '\$1.68亿';

  // ---- 资金费率迷你卡 (mock 默认) ----
  String _fundingRate = '+0.0125%';

  // ---- 市场全景横幅 (mock 默认) ----
  String _mcTotal = '\$3.24T';
  String _mcDelta = '+2.84%';
  bool _mcDeltaUp = true;
  String _mcVolume = '\$142.8B';
  String _longPct = '64%';
  double _longFrac = 0.64;

  // ---- 巨鲸异动速递 (mock 默认) ----
  List<_WhaleItem> _whaleItems = _mockWhaleItems();

  static List<_WhaleItem> _mockWhaleItems() => const [
        _WhaleItem(
          emoji: '🐋',
          pillText: '提币囤积',
          pillColor: McColors.bull,
          time: '3分钟前',
          body: '巨鲸地址 0x7a8...9f21 从 Binance 提取 1,200 BTC (\$115.7M) 至冷钱包。',
        ),
        _WhaleItem(
          emoji: '⚠️',
          pillText: '大额充值',
          pillColor: McColors.bear,
          time: '14分钟前',
          body: '某以太坊鲸鱼将 25,000 ETH (\$85.5M) 从未知钱包充入 Coinbase 交易所。',
        ),
      ];

  // ---- 主流资产速览 (mock 默认) ----
  List<_AssetRow> _assets = _mockAssets();

  // ---- 主流资产实时推送 (OKX WS, 失败静默保留 REST/ mock) ----
  StreamSubscription<TickerPush>? _tickerSub;
  static const _watchSymbols = ['BTC', 'ETH', 'SOL', 'SUI'];

  static List<_AssetRow> _mockAssets() => const [
        _AssetRow('BTC', '/USDT', '\$96,450.00', '+3.42%', true,
            [0.1, 0.25, 0.2, 0.45, 0.4, 0.65, 0.6, 0.85]),
        _AssetRow('ETH', '/USDT', '\$3,420.50', '+2.18%', true,
            [0.05, 0.2, 0.35, 0.3, 0.55, 0.5, 0.75, 0.9]),
        _AssetRow('SOL', '/USDT', '\$194.20', '+6.85%', true,
            [0.0, 0.3, 0.5, 0.4, 0.7, 0.6, 0.85, 1.0]),
        _AssetRow('SUI', '/USDT', '\$3.85', '-1.24%', false,
            [0.9, 0.7, 0.75, 0.5, 0.4, 0.45, 0.2, 0.1]),
      ];

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeTickers();
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
    // 各数据源独立尝试, 任一失败不影响其它与已有 mock.
    await Future.wait([
      _loadSentiment(),
      _loadLiquidation(),
      _loadFunding(),
      _loadAssets(),
      _loadGlobalBanner(),
      _loadLongShort(),
      _loadWhales(),
    ]);
  }

  Future<void> _loadGlobalBanner() async {
    try {
      final g = await McData.globalStats();
      if (!mounted) return;
      final cap = g.totalMarketCapUsd;
      final vol = g.totalVolumeUsd;
      final chg = g.changePct24h;
      if (cap == null && vol == null && chg == null) return; // 全 null -> 保留 mock
      setState(() {
        if (cap != null) _mcTotal = McData.fmtUsdCompact(cap);
        if (vol != null) _mcVolume = McData.fmtUsdCompact(vol);
        if (chg != null) {
          _mcDeltaUp = chg >= 0;
          _mcDelta = '${chg >= 0 ? '+' : ''}${chg.toStringAsFixed(2)}%';
        }
      });
    } on ApiException {
      // 保留 mock.
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
      // 保留 mock.
    } catch (_) {}
  }

  Future<void> _loadWhales() async {
    try {
      final resp = await McData.overview('whale-alerts');
      final items = _parseWhaleAlerts(resp['alerts']);
      if (!mounted || items.isEmpty) return;
      setState(() => _whaleItems = items);
    } on ApiException {
      // 保留 mock.
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
          m['positionValue']);
      final action = _num(m['position_action'] ?? m['action']);
      // position_action: 1 开仓/加仓, 2 平仓/减仓 (CoinGlass Hyperliquid).
      final isAdd = action == 1;
      final isReduce = action == 2;
      final color = isReduce
          ? McColors.bear
          : (isAdd ? McColors.bull : McColors.primary);
      final pill = isReduce ? '减仓离场' : (isAdd ? '加仓开仓' : '仓位异动');
      final emoji = isReduce ? '⚠️' : (isAdd ? '🐋' : '⚡');
      final verb = isReduce ? '减仓/平仓' : (isAdd ? '加仓/开仓' : '调整仓位');
      out.add(_WhaleItem(
        emoji: emoji,
        pillText: pill,
        pillColor: color,
        time: _relTime(m['create_time'] ?? m['createTime'] ?? m['time']),
        body:
            '巨鲸地址 ${_shortAddr(user)} 在 Hyperliquid $verb $symbol，仓位规模约 ${_fmtUsdZh(usd)}。',
      ));
      if (out.length >= 3) break;
    }
    return out;
  }

  static String _shortAddr(String addr) {
    if (addr.length <= 10) return addr.isEmpty ? '匿名巨鲸' : addr;
    return '${addr.substring(0, 6)}...${addr.substring(addr.length - 4)}';
  }

  static String _relTime(dynamic ts) {
    final ms = ts is num ? ts.toInt() : int.tryParse('$ts') ?? 0;
    if (ms <= 0) return '刚刚';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms > 100000000000 ? ms : ms * 1000);
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
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
        _sentimentSub = '实时 · $label';
      });
    } on ApiException {
      // 保留 mock.
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
      // 保留 mock.
    } catch (_) {}
  }

  Future<void> _loadFunding() async {
    try {
      final resp = await McData.overview('funding/exchange-rates?symbol=BTC');
      final avg = _avgFundingRate(resp['data']);
      if (avg == null || !mounted) return;
      setState(() => _fundingRate =
          '${avg >= 0 ? '+' : ''}${avg.toStringAsFixed(4)}%');
    } on ApiException {
      // 保留 mock.
    } catch (_) {}
  }

  Future<void> _loadAssets() async {
    List<OkxTicker> tickers;
    try {
      tickers = await McData.tickers();
    } on ApiException {
      return; // 保留 mock.
    } catch (_) {
      return;
    }
    if (!mounted) return;

    const targets = ['BTC', 'ETH', 'SOL', 'SUI'];
    final updated = [..._assets];
    var changed = false;
    for (var i = 0; i < updated.length; i++) {
      final row = updated[i];
      OkxTicker? t;
      for (final x in tickers) {
        if (x.symbol == row.symbol) {
          t = x;
          break;
        }
      }
      if (t == null) continue;
      final up = t.changePct >= 0;
      updated[i] = row.copyWith(
        price: _fmtPrice(t.last),
        delta: '${up ? '+' : ''}${t.changePct.toStringAsFixed(2)}%',
        up: up,
      );
      changed = true;
    }
    if (changed && mounted) setState(() => _assets = updated);

    // K线 sparkline: 逐币种独立尝试, 失败保留 mock 曲线.
    for (var i = 0; i < targets.length; i++) {
      try {
        final spark = await McData.sparkline('${targets[i]}-USDT-SWAP');
        if (spark.length >= 2 && mounted) {
          setState(() {
            final list = [..._assets];
            list[i] = list[i].copyWith(spark: spark);
            _assets = list;
          });
        }
      } on ApiException {
        // 保留 mock 曲线.
      } catch (_) {}
    }
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
    if (v < 25) return ('极度恐慌', McColors.bear);
    if (v < 45) return ('恐慌', McColors.bear);
    if (v < 56) return ('中性', McColors.onSurfaceVariant);
    if (v < 75) return ('贪婪', McColors.bull);
    return ('极度贪婪', McColors.bull);
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
          _marketBanner(),
          const SizedBox(height: 16),
          // 2. 情绪 + 爆仓 双子卡 (定高对齐; IntrinsicHeight 与 Expanded 基线冲突不可用)
          SizedBox(
            height: 156,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _SentimentCard(
                    value: _sentimentValue,
                    label: _sentimentLabel,
                    color: _sentimentColor,
                    sub: _sentimentSub,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _LiquidationMiniCard(
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
          const McSectionHeader(
            title: '主流资产速览',
            icon: Icons.trending_up,
            trailing: '24H',
          ),
          const SizedBox(height: 10),
          _assetList(),
          const SizedBox(height: 16),
          // 4. 巨鲸异动最新
          const McSectionHeader(
            title: '巨鲸异动速递',
            icon: Icons.radar,
            trailing: '实时同步中',
            trailingColor: McColors.bull,
          ),
          const SizedBox(height: 10),
          _whaleFeed(),
          const SizedBox(height: 16),
          // 5. 资金费率 + 山寨季 双子卡 (定高对齐)
          SizedBox(
            height: 156,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _FundingMiniCard(rate: _fundingRate)),
                const SizedBox(width: 10),
                const Expanded(child: _AltSeasonCard()),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _statusBar(),
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
                child: Text('全网市场全景',
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
              _vital('24H 总市值', _mcTotal, _mcDelta, _mcDeltaUp),
              _vital('24H 成交额', _mcVolume, null, null),
              _vital('多头主导指数', _longPct, null, null, bar: _longFrac),
            ],
          ),
        ],
      ),
    );
  }

  Widget _vital(String label, String value, String? delta, bool? up,
      {double? bar}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(value,
              style: McText.display(size: 18, weight: FontWeight.w700)),
          if (delta != null) ...[
            const SizedBox(height: 2),
            Text(delta,
                style: McText.mono(
                    size: 12,
                    weight: FontWeight.w600,
                    color: up == true ? McColors.bull : McColors.bear)),
          ],
          if (bar != null) ...[
            const SizedBox(height: 6),
            McProgressBar(fraction: bar, color: McColors.bull, height: 4),
          ],
        ],
      ),
    );
  }

  // 主流资产行
  Widget _assetList() {
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
    final c = r.up ? McColors.bull : McColors.bear;
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

  // 巨鲸异动速递 (实时, 失败回退 mock)
  Widget _whaleFeed() {
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

  // 底部状态栏
  Widget _statusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: McColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const McGlowDot(),
          const SizedBox(width: 6),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text('WebSocket: 18ms (直连 Tokyo-A)',
                  style: McText.mono(
                      size: 12, color: McColors.onSurfaceVariant)),
            ),
          ),
          const SizedBox(height: 12),
          Text('BLOCK #21,498,924',
              style: McText.mono(
                  size: 12,
                  color: McColors.onSurfaceVariant,
                  letterSpacing: 1)),
        ],
      ),
    );
  }
}

/// 巨鲸异动速递条目的不可变数据模型 (mock 与真实数据共用).
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

/// 主流资产行的不可变数据模型 (mock 与真实数据共用).
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

/// 情绪指数卡.
class _SentimentCard extends StatelessWidget {
  const _SentimentCard({
    required this.value,
    required this.label,
    required this.color,
    required this.sub,
  });

  final String value;
  final String label;
  final Color color;
  final String sub;

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
              Text('情绪指数',
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
              Text(value,
                  style: McText.display(size: 24, weight: FontWeight.w700)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
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
          Text(sub,
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

/// 多空爆仓迷你卡.
class _LiquidationMiniCard extends StatelessWidget {
  const _LiquidationMiniCard({
    required this.total,
    required this.longFrac,
    required this.longText,
    required this.shortText,
  });

  final String total;
  final double longFrac;
  final String longText;
  final String shortText;

  @override
  Widget build(BuildContext context) {
    final lf = longFrac.clamp(0.0, 1.0);
    return McCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const McGlowDot(color: McColors.bear),
              const SizedBox(width: 4),
              Text('24H 爆仓',
                  style: McText.sans(
                      size: 12,
                      weight: FontWeight.w500,
                      color: McColors.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 12),
          Text(total,
              style: McText.display(
                  size: 20, weight: FontWeight.w700, color: McColors.bear)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Row(
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
          Text('多 $longText · 空 $shortText',
              style: McText.mono(size: 12, color: McColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// 资金费率迷你卡.
class _FundingMiniCard extends StatelessWidget {
  const _FundingMiniCard({required this.rate});

  final String rate;

  @override
  Widget build(BuildContext context) {
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
                child: Text('资金费率加权',
                    overflow: TextOverflow.ellipsis,
                    style: McText.sans(
                        size: 12,
                        weight: FontWeight.w500,
                        color: McColors.onSurfaceVariant)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(rate,
              style: McText.mono(
                  size: 20, weight: FontWeight.w700, color: McColors.bull)),
          const SizedBox(height: 8),
          const McProgressBar(fraction: 0.48, color: McColors.bull),
          const SizedBox(height: 12),
          Text('适度偏多 · 8H结算',
              style: McText.mono(size: 12, color: McColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// 山寨季指数卡.
class _AltSeasonCard extends StatelessWidget {
  const _AltSeasonCard();

  @override
  Widget build(BuildContext context) {
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
                child: Text('山寨季指数',
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
              Text('38',
                  style: McText.mono(size: 20, weight: FontWeight.w700)),
              Text(' /100',
                  style: McText.mono(
                      size: 12, color: McColors.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          const McProgressBar(
              fraction: 0.38, color: McColors.primaryContainer),
          const SizedBox(height: 12),
          Text('距山寨爆发差 37 点',
              style: McText.mono(size: 12, color: McColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

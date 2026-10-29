import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/kit.dart';
import '../widgets/shell.dart';
import 'market_detail_page.dart';
import 'market_page.dart';
import 'news_page.dart';

/// 行情总览页, 区块结构对齐 web-terminal/src/views/Overview.vue:
/// ROW1 KPI 四卡 (总市值 / BTC 占比 / 多空广度 / 情绪)
/// ROW2 24H 涨幅榜 (7) + BTC 迷你 K 线 (5)
/// ROW3 TERMINAL INTEL WIRE 资讯流
/// ROW4/5 近期爆仓 / 巨鲸警报 (桌面端保留)
class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key});

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  bool _loading = true;
  bool _fatal = false;

  Map<String, dynamic> _stats = const {};
  Map<String, dynamic> _lsRatio = const {};
  num? _sentiment;

  // 涨幅榜
  List<dynamic> _gainers = const [];
  List<dynamic> _allRows = const []; // TOP30 按量能, 供 tab 过滤
  String _gainerTab = 'main';
  Map<String, List<double>> _sparks = const {}; // instId -> closes

  // BTC 迷你 K 线
  Map<String, dynamic>? _btcTicker;
  List<List<num>> _btcRows = const []; // 时间正序 [o,h,l,c,vol]
  String _btcBar = '1H';
  num? _funding; // BTC 永续资金费率 (%)
  List<dynamic>? _bid; // 买一 [price, qty, ...]
  List<dynamic>? _ask; // 卖一

  // 资讯流
  List<dynamic> _newsList = const [];
  String _wireFilter = 'all';

  // 保留区块
  List<dynamic> _liqEvents = const [];
  List<dynamic> _whaleAlerts = const [];

  Timer? _timer;

  /// 纯展示: 币种标签 chip (对齐 web 端涨幅榜)
  static const _coinTags = {
    'BTC': 'POW', 'ETH': 'L1', 'SOL': 'HIGH-TPS', 'SUI': 'MOVE', 'TAO': 'DE-AI',
    'RENDER': 'AI/GPU', 'XRP': 'PAYMENT', 'DOGE': 'MEME', 'ADA': 'L1',
    'LINK': 'ORACLE', 'AVAX': 'L1', 'TON': 'L1', 'BNB': 'CEX', 'DOT': 'L0',
    'NEAR': 'L1', 'FET': 'AI',
  };

  static const _gainerTabs = [
    ('main', '主流币'),
    ('aidefi', 'AI / DeFi'),
    ('new', '新上线'),
  ];

  static const _wireFilters = [
    ('all', '全部快讯', <String>[]),
    ('whale', '巨鲸异动', ['巨鲸', 'whale', '鲸鱼', '大户']),
    ('liq', '宏观清算', ['清算', '爆仓', 'liquidat', '宏观', '美联储', '加息', '降息']),
    ('chain', '链上异动', ['链上', 'on-chain', 'onchain', '流入', '流出', '转账']),
  ];

  static const _btcBars = [
    ('1M', '1m'),
    ('15M', '15m'),
    ('1H', '1H'),
    ('4H', '4H'),
    ('1D', '1D'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<dynamic> _safe(Future<dynamic> f) async {
    try {
      return await f;
    } catch (_) {
      return null;
    }
  }

  static List<List<num>> _parseCandles(List<dynamic> data) => [
        for (final c in data.reversed)
          if (c is List && c.length > 5)
            [for (var i = 1; i <= 5; i++) Fmt.toNum(c[i]) ?? 0],
      ];

  Future<void> _load() async {
    final api = ApiClient.I;
    final r = await Future.wait([
      _safe(api.globalStats()),
      _safe(api.sentiment()),
      _safe(api.longShortRatio(symbol: 'BTC')),
      _safe(api.tickers()),
      _safe(api.newsList({'limit': 8})),
      _safe(api.ticker('BTC-USDT')),
      _safe(api.candles('BTC-USDT', bar: _btcBar, limit: 72)),
      _safe(api.fundingRate('BTC-USDT-SWAP')),
      _safe(api.books('BTC-USDT-SWAP', sz: 5)),
      _safe(api.liqRecent(limit: 50)),
      _safe(api.whaleAlerts()),
    ]);
    if (!mounted) return;

    final g = r[0], s = r[1], ls = r[2], tk = r[3], nw = r[4];
    final bt = r[5], bc = r[6], fr = r[7], bk = r[8];
    final li = r[9], wa = r[10];

    List<dynamic> gainers = _gainers;
    setState(() {
      if (g is Map) _stats = Map<String, dynamic>.from(g);
      if (s is Map) _sentiment = Fmt.toNum(s['fear_greed']);
      if (ls is Map) _lsRatio = Map<String, dynamic>.from(ls);
      if (bt is Map && bt['data'] is List && (bt['data'] as List).isNotEmpty) {
        _btcTicker = Map<String, dynamic>.from((bt['data'] as List).first);
      }
      if (bc is Map && bc['data'] is List) {
        _btcRows = _parseCandles(bc['data'] as List);
      }
      if (fr is Map && fr['data'] is List && (fr['data'] as List).isNotEmpty) {
        final v = Fmt.toNum((fr['data'] as List).first is Map
            ? (fr['data'] as List).first['fundingRate']
            : null);
        if (v != null) _funding = v * 100;
      }
      if (bk is Map && bk['data'] is List && (bk['data'] as List).isNotEmpty) {
        final d = (bk['data'] as List).first;
        if (d is Map) {
          final bids = d['bids'], asks = d['asks'];
          if (bids is List && bids.isNotEmpty) _bid = bids.first as List?;
          if (asks is List && asks.isNotEmpty) _ask = asks.first as List?;
        }
      }
      if (tk is Map && tk['data'] is List) {
        final rows = (tk['data'] as List)
            .where((t) => t is Map && t['instId'].toString().endsWith('-USDT'))
            .toList()
          ..sort((a, b) => (Fmt.toNum(b['volCcy24h']) ?? 0)
              .compareTo(Fmt.toNum(a['volCcy24h']) ?? 0));
        _allRows = rows.take(30).toList();
        gainers = [..._allRows]
          ..sort((a, b) => _pctOf(b).compareTo(_pctOf(a)));
        _gainers = gainers.take(10).toList();
      }
      if (nw != null) {
        final items = nw is Map
            ? (nw['items'] ?? nw['data'] ?? const [])
            : (nw is List ? nw : const []);
        if (items is List) _newsList = items.take(6).toList();
      }
      if (li is Map && li['data'] is List) _liqEvents = li['data'] as List;
      if (wa is Map && wa['alerts'] is List) _whaleAlerts = wa['alerts'] as List;

      _fatal = _stats.isEmpty &&
          _sentiment == null &&
          _btcTicker == null &&
          _newsList.isEmpty &&
          _liqEvents.isEmpty &&
          _whaleAlerts.isEmpty;
      _loading = false;
    });
    // sparkline 懒加载: 上榜币各拉 24 根 1H 收盘
    if (gainers.isNotEmpty) _loadSparks(gainers.take(10).toList());
  }

  Future<void> _loadSparks(List<dynamic> gainers) async {
    final api = ApiClient.I;
    final results = await Future.wait([
      for (final t in gainers)
        _safe(api.candles(t['instId'].toString(), bar: '1H', limit: 24)),
    ]);
    if (!mounted) return;
    final map = <String, List<double>>{};
    for (var i = 0; i < gainers.length; i++) {
      final r = results[i];
      if (r is Map && r['data'] is List) {
        map[gainers[i]['instId'].toString()] = [
          for (final c in (r['data'] as List).reversed)
            (Fmt.toNum(c is List && c.length > 4 ? c[4] : null) ?? 0)
                .toDouble(),
        ];
      }
    }
    setState(() => _sparks = map);
  }

  Future<void> _setBtcBar(String bar) async {
    if (bar == _btcBar) return;
    setState(() => _btcBar = bar);
    final r = await _safe(ApiClient.I.candles('BTC-USDT', bar: bar, limit: 72));
    if (!mounted || r is! Map || r['data'] is! List) return;
    setState(() => _btcRows = _parseCandles(r['data'] as List));
  }

  // ---------- 解析 ----------
  num _pctOf(dynamic t) {
    final open = Fmt.toNum(t?['open24h']);
    final last = Fmt.toNum(t?['last']);
    if (open == null || open == 0 || last == null) return 0;
    return (last - open) / open * 100;
  }

  static String _coinOf(dynamic symbol) =>
      (symbol ?? '').toString().split('-').first;

  num? get _btcDom => Fmt.toNum(_stats['btc_dominance']);
  num? get _ethDom => Fmt.toNum(_stats['eth_dominance']);
  num? get _otherDom {
    final b = _btcDom, e = _ethDom;
    if (b == null || e == null) return null;
    return 100 - b - e;
  }

  num? get _longPct => Fmt.toNum(_lsRatio['long_pct']);
  num? get _shortPct => Fmt.toNum(_lsRatio['short_pct']);

  String get _lsText {
    final l = _longPct, s = _shortPct;
    if (l == null || s == null) return '--';
    return '${(l / (s == 0 ? 0.01 : s)).toStringAsFixed(2)}:1';
  }

  num? get _btcPct {
    final t = _btcTicker;
    final open = Fmt.toNum(t?['open24h']);
    final last = Fmt.toNum(t?['last']);
    if (open == null || open == 0 || last == null) return null;
    return (last - open) / open * 100;
  }

  String get _sentimentLabel {
    final v = _sentiment;
    if (v == null) return '--';
    if (v >= 75) return '极度贪婪';
    if (v >= 50) return '贪婪';
    if (v >= 25) return '恐慌';
    return '极度恐慌';
  }

  Color get _sentimentColor {
    final v = _sentiment;
    if (v == null) return Mc.ink;
    if (v >= 50) return Mc.bull;
    if (v >= 25) return Mc.amber;
    return Mc.bear;
  }

  List<dynamic> get _filteredGainers {
    if (_gainerTab == 'aidefi') {
      return _gainers
          .where((t) => RegExp('AI|DEFI', caseSensitive: false)
              .hasMatch(_coinTags[_coinOf(t['instId'])] ?? ''))
          .toList();
    }
    if (_gainerTab == 'new') {
      final rows = [..._allRows]
        ..sort((a, b) => (Fmt.toNum(a['volCcy24h']) ?? 0)
            .compareTo(Fmt.toNum(b['volCcy24h']) ?? 0));
      return rows.take(10).toList();
    }
    return _gainers;
  }

  List<dynamic> get _filteredNews {
    final f = _wireFilters.firstWhere((x) => x.$1 == _wireFilter);
    if (f.$3.isEmpty) return _newsList;
    return _newsList.where((n) {
      final text =
          '${n['title'] ?? ''} ${n['summary'] ?? ''} ${n['content'] ?? ''}'
              .toLowerCase();
      return f.$3.any((kw) => text.contains(kw.toLowerCase()));
    }).toList();
  }

  String get _spreadPct {
    final b = Fmt.toNum(_bid?.isNotEmpty == true ? _bid![0] : null);
    final a = Fmt.toNum(_ask?.isNotEmpty == true ? _ask![0] : null);
    if (b == null || a == null || b == 0) return '--';
    return '${((a - b) / b * 100).toStringAsFixed(3)}%';
  }

  Future<void> _retry() async {
    setState(() {
      _loading = true;
      _fatal = false;
    });
    await _load();
  }

  // ---------- 页面 ----------
  @override
  Widget build(BuildContext context) {
    if (_loading) return const McLoading(label: '行情数据加载中');
    if (_fatal) {
      return McError('行情数据暂时不可用，请稍后重试', onRetry: _retry);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const McSection('行情总览', tag: 'MARKET OVERVIEW'),
        const SizedBox(height: 16),
        _kpiRow(),
        const SizedBox(height: 16),
        _midRow(),
        const SizedBox(height: 16),
        _wireCard(),
        const SizedBox(height: 16),
        _liqCard(),
        const SizedBox(height: 16),
        _whaleCard(),
      ]),
    );
  }

  // ---------- ROW 1: KPI 四卡 ----------
  Widget _kpiRow() {
    final tiles = [
      _mktCapCard(),
      _btcDomCard(),
      _breadthCard(),
      _sentimentCard(),
    ];
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth > 1100) return McRow(children: tiles);
      final cols = c.maxWidth > 620 ? 2 : 1;
      final w = (c.maxWidth - (cols - 1) * 16) / cols;
      return Wrap(spacing: 16, runSpacing: 16,
          children: [for (final t in tiles) SizedBox(width: w, child: t)]);
    });
  }

  Widget _mktCapCard() {
    final chg = Fmt.toNum(_stats['market_cap_change_pct_24h']);
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const McTag('GLOBAL MARKET CAP 全网总市值'),
        const SizedBox(height: 8),
        Text(Fmt.compact(_stats['total_market_cap_usd'], prefix: '\$'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Mc.mono(22, w: FontWeight.w600)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.only(top: 8),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Mc.hairline))),
          child: Row(children: [
            Text('${Fmt.pct(chg)} 24H',
                style: Mc.mono(11, color: Mc.upDown(chg))),
            const Spacer(),
            Text('24H 量能 ', style: Mc.mono(11, color: Mc.muted)),
            Text(Fmt.compact(_stats['total_volume_usd'], prefix: '\$'),
                style: Mc.mono(11)),
          ]),
        ),
      ]),
    );
  }

  Widget _btcDomCard() {
    final b = _btcDom, e = _ethDom, o = _otherDom;
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const McTag('BTC DOMINANCE BTC 占有率'),
        const SizedBox(height: 8),
        Text(b == null ? '--' : '${b.toStringAsFixed(1)}%',
            style: Mc.mono(22, w: FontWeight.w600)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.only(top: 8),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Mc.hairline))),
          child: Column(children: [
            Row(children: [
              Text('ETH ${e == null ? '--' : '${e.toStringAsFixed(1)}%'}',
                  style: Mc.mono(11, color: Mc.cobaltSoft)),
              const Spacer(),
              Text('OTHERS ${o == null ? '--' : '${o.toStringAsFixed(1)}%'}',
                  style: Mc.mono(11, color: Mc.muted)),
            ]),
            const SizedBox(height: 6),
            _segBar([
              ((b ?? 0), Mc.cobalt),
              ((e ?? 0), Mc.cobaltSoft),
              ((o ?? 100), Mc.hairline),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _breadthCard() {
    final l = _longPct, s = _shortPct;
    final lead = l == null || s == null
        ? null
        : (l >= s ? ('多头主导', Mc.bull) : ('空头主导', Mc.bear));
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const McTag('MARKET BREADTH 全局多空'),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(l == null ? '--' : '${l.toStringAsFixed(0)}%',
                  style: Mc.mono(22, w: FontWeight.w600, color: Mc.up)),
              Text(' / ', style: Mc.mono(14, color: Mc.muted)),
              Text(s == null ? '--' : '${s.toStringAsFixed(0)}%',
                  style: Mc.mono(22, w: FontWeight.w600, color: Mc.down)),
            ]),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.only(top: 8),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Mc.hairline))),
          child: Column(children: [
            Row(children: [
              Text(lead?.$1 ?? '--',
                  style: Mc.mono(11, color: lead?.$2 ?? Mc.muted)),
              const Spacer(),
              Text('多空比 $_lsText', style: Mc.mono(11, color: Mc.muted)),
            ]),
            const SizedBox(height: 6),
            _segBar([
              ((l ?? 50), Mc.up),
              ((s ?? 50), Mc.down),
            ]),
          ]),
        ),
      ]),
    );
  }

  /// 分段占比条: [(值, 颜色)]。
  Widget _segBar(List<(num, Color)> segs) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: Row(children: [
          for (final (v, c) in segs)
            Expanded(
                flex: (v * 100).round().clamp(0, 1000000),
                child: Container(color: c)),
        ]),
      ),
    );
  }

  Widget _sentimentCard() {
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const McTag('SENTIMENT INDEX 恐慌贪婪'),
        const SizedBox(height: 8),
        Row(children: [
          Text(_sentiment?.toStringAsFixed(0) ?? '--',
              style: Mc.mono(22, w: FontWeight.w600, color: _sentimentColor)),
          const SizedBox(width: 8),
          if (_sentiment != null)
            McBadge(_sentimentLabel, color: _sentimentColor),
        ]),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.only(top: 8),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Mc.hairline))),
          child: Row(children: [
            Text('数据源: alternative.me', style: Mc.mono(11, color: Mc.muted)),
            const Spacer(),
            if (_sentiment != null && _sentiment! >= 75) ...[
              Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      color: Mc.amber, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text('极度亢奋临界点', style: Mc.mono(11, color: Mc.amber)),
            ] else ...[
              Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      color: Mc.muted, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text('常规波动区间', style: Mc.mono(11, color: Mc.muted)),
            ],
          ]),
        ),
      ]),
    );
  }

  // ---------- ROW 2: 涨幅榜 (7) + BTC 迷你 K 线 (5) ----------
  Widget _midRow() {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > 980;
      final gainers = _gainersCard();
      final btc = _btcKlineCard();
      if (!wide) {
        return Column(children: [gainers, const SizedBox(height: 16), btc]);
      }
      return McRow(spans: const [7, 5], children: [gainers, btc]);
    });
  }

  Widget _gainersCard() {
    final rows = _filteredGainers;
    return McCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: McSection('24H 涨幅榜',
              tag: 'TOP GAINERS',
              trailing: _segGroup(
                _gainerTabs,
                _gainerTab,
                (k) => setState(() => _gainerTab = k),
              )),
        ),
        const Divider(height: 1, color: Mc.hairline),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(children: const [
            Expanded(flex: 1, child: McTh('#')),
            Expanded(flex: 3, child: McTh('币种')),
            Expanded(flex: 2, child: McTh('最新价', align: TextAlign.right)),
            Expanded(flex: 2, child: McTh('24H 涨跌', align: TextAlign.right)),
            Expanded(flex: 2, child: McTh('24H 量能', align: TextAlign.right)),
            Expanded(flex: 2, child: McTh('24H 趋势', align: TextAlign.right)),
          ]),
        ),
        const Divider(height: 1, color: Mc.hairline),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: McEmpty('该分类暂无上榜币种'),
          )
        else
          for (var i = 0; i < rows.length; i++) ...[
            _gainerRow(rows[i], i),
            if (i != rows.length - 1)
              const Divider(height: 1, color: Mc.hairline),
          ],
        const Divider(height: 1, color: Mc.hairline),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 12, 12),
          child: Row(children: [
            Text('展示 TOP 10 · 按 24H 涨跌幅排序 (USDT 现货)',
                style: Mc.mono(11, color: Mc.muted)),
            const Spacer(),
            _linkBtn('查看完整行情', () {
              ShellRouter.I.push('行情', 'MARKET', const MarketPage());
            }),
          ]),
        ),
      ]),
    );
  }

  Widget _gainerRow(dynamic t, int i) {
    final instId = t['instId'].toString();
    final coin = _coinOf(instId);
    final p = _pctOf(t);
    final tag = _coinTags[coin];
    return _HoverRow(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      onTap: () => ShellRouter.I
          .push('行情详情', 'MARKET', MarketDetailPage(instId: instId)),
      children: [
        Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text((i + 1).toString().padLeft(2, '0'),
                  style: Mc.mono(12, color: Mc.muted)),
            )),
        Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Text(coin, style: Mc.mono(12, w: FontWeight.w700)),
                const SizedBox(width: 6),
                Flexible(
                    child: Text(instId,
                        overflow: TextOverflow.ellipsis,
                        style: Mc.mono(10, color: Mc.muted))),
                if (tag != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                        color: Mc.cardHigh,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: Mc.hairline)),
                    child: Text(tag, style: Mc.mono(9, color: Mc.muted)),
                  ),
                ],
              ]),
            )),
        Expanded(
            flex: 2,
            child: _td(Fmt.num_(t['last']),
                align: TextAlign.right, w: FontWeight.w600)),
        Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerRight,
                child: McBadge(Fmt.pct(p), color: Mc.upDown(p)),
              ),
            )),
        Expanded(
            flex: 2,
            child: _td(Fmt.compact(t['volCcy24h']),
                align: TextAlign.right, color: Mc.muted)),
        Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                  alignment: Alignment.centerRight,
                  child: _spark(_sparks[instId])),
            )),
      ],
    );
  }

  Widget _td(String text,
      {TextAlign align = TextAlign.left,
      FontWeight w = FontWeight.w500,
      Color color = Mc.ink}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(text,
          textAlign: align,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Mc.mono(12, w: w, color: color)),
    );
  }

  /// 64x20 迷你走势线 (对齐 web sparkline)。
  Widget _spark(List<double>? closes) {
    if (closes == null || closes.length < 2) {
      return Text('--', style: Mc.mono(11, color: Mc.muted));
    }
    final up = closes.last >= closes.first;
    final color = up ? Mc.up : Mc.down;
    var mn = closes.first, mx = closes.first;
    for (final v in closes) {
      if (v < mn) mn = v;
      if (v > mx) mx = v;
    }
    final pad = (mx - mn) * 0.08 + 1e-9;
    return SizedBox(
      width: 64,
      height: 20,
      child: LineChart(LineChartData(
        minY: mn - pad,
        maxY: mx + pad,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < closes.length; i++)
                FlSpot(i.toDouble(), closes[i]),
            ],
            isCurved: false,
            color: color,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
          ),
        ],
      )),
    );
  }

  // ---------- BTC 迷你 K 线卡 ----------
  Widget _btcKlineCard() {
    final last = Fmt.toNum(_btcTicker?['last']);
    final pct = _btcPct;
    final rows = _btcRows.length > 36
        ? _btcRows.sublist(_btcRows.length - 36)
        : _btcRows;
    final closes = [for (final r in rows) r[3].toDouble()];
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                Text('BTC/USDT', style: Mc.display(16)),
                const SizedBox(width: 8),
                Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: Mc.bull, shape: BoxShape.circle)),
              ]),
              const SizedBox(height: 4),
              Row(crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('\$${Fmt.num_(last)}',
                        style: Mc.mono(20, w: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Text(Fmt.pct(pct),
                        style: Mc.mono(12, color: Mc.upDown(pct))),
                  ]),
            ]),
          ),
          _segGroup(
            [for (final (label, bar) in _btcBars) (bar, label)],
            _btcBar,
            _setBtcBar,
          ),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: const BoxDecoration(
              border: Border(
                  top: BorderSide(color: Mc.hairline),
                  bottom: BorderSide(color: Mc.hairline))),
          child: Row(children: [
            Expanded(
                child: _kv('24H 最高',
                    '\$${Fmt.num_(Fmt.toNum(_btcTicker?['high24h']))}')),
            Expanded(
                child: _kv('24H 最低',
                    '\$${Fmt.num_(Fmt.toNum(_btcTicker?['low24h']))}')),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('资金率: ', style: Mc.mono(10, color: Mc.muted)),
                  Text(
                      _funding == null ? '--' : Fmt.pct(_funding, dp: 4),
                      style: Mc.mono(10,
                          color: _funding == null
                              ? Mc.muted
                              : Mc.upDown(_funding))),
                ]),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        Container(
          height: 220,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: Mc.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Mc.hairline)),
          child: Column(children: [
            Row(children: [
              _maLegend('MA7', _maLast(closes, 7), Mc.cobalt),
              const SizedBox(width: 12),
              _maLegend('MA25', _maLast(closes, 25), Mc.amber),
            ]),
            const SizedBox(height: 6),
            Expanded(
              child: rows.length < 2
                  ? const McEmpty('暂无走势数据')
                  : CustomPaint(
                      painter: _KlinePainter(rows,
                          up: Mc.up, down: Mc.down),
                      size: Size.infinite,
                    ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        // 盘口微件: 买一 / 点差 / 卖一
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
              color: Mc.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Mc.hairline)),
          child: Row(children: [
            Flexible(child: _depthSide('买一', _bid, Mc.up)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: Mc.card,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Mc.hairline)),
              child: Text('点差 $_spreadPct',
                  style: Mc.mono(10, color: Mc.muted)),
            ),
            const Spacer(),
            Flexible(child: _depthSide('卖一', _ask, Mc.down)),
          ]),
        ),
      ]),
    );
  }

  Widget _kv(String k, String v) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$k: ', style: Mc.mono(10, color: Mc.muted)),
      Flexible(
          child: Text(v,
              overflow: TextOverflow.ellipsis,
              style: Mc.mono(10, color: Mc.ink))),
    ]);
  }

  Widget _maLegend(String label, double? v, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 2, color: color),
      const SizedBox(width: 4),
      Text('$label: ${v == null ? '--' : Fmt.num_(v)}',
          style: Mc.mono(10, color: color)),
    ]);
  }

  static double? _maLast(List<double> closes, int n) {
    if (closes.length < n) return null;
    var s = 0.0;
    for (var i = closes.length - n; i < closes.length; i++) {
      s += closes[i];
    }
    return s / n;
  }

  Widget _depthSide(String label, List<dynamic>? level, Color color) {
    final price = Fmt.toNum(level != null && level.isNotEmpty ? level[0] : null);
    final qty = Fmt.toNum(level != null && level.length > 1 ? level[1] : null);
    // 单个 Text.rich: Row 内非 flex 的 Text 不受宽限, 此前溢出 6/87px
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: '$label: ', style: Mc.mono(10, color: Mc.muted)),
        TextSpan(
            text: price == null ? '--' : Fmt.num_(price),
            style: Mc.mono(11, w: FontWeight.w600, color: color)),
        TextSpan(
            text: qty == null ? '' : ' (${Fmt.compact(qty)})',
            style: Mc.mono(9, color: Mc.muted)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  // ---------- ROW 3: TERMINAL INTEL WIRE 资讯流 ----------
  Widget _wireCard() {
    final rows = _filteredNews;
    return McCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: McSection('实时情报快讯',
              tag: 'TERMINAL INTEL WIRE',
              trailing: _segGroup(
                [for (final f in _wireFilters) (f.$1, f.$2)],
                _wireFilter,
                (k) => setState(() => _wireFilter = k),
              )),
        ),
        const Divider(height: 1, color: Mc.hairline),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: McEmpty(_wireFilter == 'all' ? '暂无快讯' : '该分类暂无快讯'),
          )
        else
          for (var i = 0; i < rows.length; i++) ...[
            _wireRow(rows[i]),
            if (i != rows.length - 1)
              const Divider(height: 1, color: Mc.hairline),
          ],
        const Divider(height: 1, color: Mc.hairline),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 12, 12),
          child: Row(children: [
            Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                    color: Mc.bull, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text('POLLING FEED · 30S REFRESH',
                style: Mc.mono(10, color: Mc.muted)),
            const Spacer(),
            _linkBtn('全部资讯', () {
              ShellRouter.I.push('资讯', 'NEWS', const NewsPage());
            }),
          ]),
        ),
      ]),
    );
  }

  Widget _wireRow(dynamic n) {
    final id = Fmt.toNum(n['id'])?.toInt();
    void open() {
      if (id == null) return;
      ShellRouter.I.push('资讯', 'NEWS', NewsArticleOverlay(id: id));
    }

    return _HoverRow(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      onTap: open,
      children: [
        SizedBox(
            width: 44,
            child: Text(Fmt.hm(n['publish_at']),
                style: Mc.mono(11, color: Mc.muted))),
        SizedBox(
          width: 92,
          child: Align(
            alignment: Alignment.centerLeft,
            child: McBadge((n['source'] ?? '快讯').toString(),
                color: Mc.cobaltSoft),
          ),
        ),
        Expanded(
            child: Text((n['title'] ?? '').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Mc.body(13))),
        const SizedBox(width: 12),
        Text(Fmt.ago(n['publish_at']),
            style: Mc.mono(11, color: Mc.muted)),
        const SizedBox(width: 12),
        InkWell(
          onTap: open,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: Mc.surface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Mc.hairline)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('深度分析', style: Mc.mono(10, color: Mc.cobaltSoft)),
              const Icon(Icons.north_east, size: 12, color: Mc.cobaltSoft),
            ]),
          ),
        ),
      ],
    );
  }

  // ---------- 通用小组件 ----------
  /// 分段切换按钮组 (涨幅榜 tab / K 线周期 / 资讯过滤)。
  Widget _segGroup(List<(String, String)> items, String current,
      ValueChanged<String> onSelect) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
          color: Mc.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Mc.hairline)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final (key, label) in items)
          GestureDetector(
            onTap: () => onSelect(key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: key == current ? Mc.cobalt : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(label,
                  style: Mc.mono(10,
                      w: FontWeight.w600,
                      color: key == current ? Mc.ink : Mc.muted)),
            ),
          ),
      ]),
    );
  }

  Widget _linkBtn(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: Mc.mono(11, w: FontWeight.w600)),
          const Icon(Icons.chevron_right, size: 14, color: Mc.ink),
        ]),
      ),
    );
  }

  // ---------- ROW 4: 近期爆仓 ----------
  Widget _liqCard() {
    final rows = _liqEvents.take(12).toList();
    return McCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: McSection('近期爆仓', tag: 'RECENT LIQUIDATIONS'),
        ),
        const Divider(height: 1, color: Mc.hairline),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(children: const [
            Expanded(flex: 2, child: McTh('时间')),
            Expanded(flex: 2, child: McTh('币种')),
            Expanded(flex: 3, child: McTh('方向', align: TextAlign.center)),
            Expanded(
                flex: 3, child: McTh('价格 (USD)', align: TextAlign.right)),
            Expanded(flex: 2, child: McTh('数量', align: TextAlign.right)),
            Expanded(
                flex: 3, child: McTh('名义价值', align: TextAlign.right)),
          ]),
        ),
        const Divider(height: 1, color: Mc.hairline),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: McEmpty('暂无爆仓事件'),
          )
        else
          for (var i = 0; i < rows.length; i++) ...[
            _liqRow(rows[i]),
            if (i != rows.length - 1)
              const Divider(height: 1, color: Mc.hairline),
          ],
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _liqRow(dynamic e) {
    final isLong = e['side'] == 'long' || e['side'] == 'buy';
    final coin = _coinOf(e['symbol']);
    return _HoverRow(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      children: [
        Expanded(
            flex: 2,
            child: Text(Fmt.hm(e['ts']),
                style: Mc.mono(12, color: Mc.muted))),
        Expanded(
            flex: 2,
            child: Text(coin, style: Mc.mono(12, w: FontWeight.w600))),
        Expanded(
            flex: 3,
            child: Center(
              child: McBadge(isLong ? '多单强平 LONG' : '空单强平 SHORT',
                  color: isLong ? Mc.up : Mc.down),
            )),
        Expanded(
            flex: 3,
            child: Text(Fmt.num_(e['price']),
                textAlign: TextAlign.right, style: Mc.mono(12))),
        Expanded(
            flex: 2,
            child: Text(Fmt.compact(e['qty']),
                textAlign: TextAlign.right,
                style: Mc.mono(12, color: Mc.muted))),
        Expanded(
            flex: 3,
            child: Text(Fmt.compact(e['notional_usd'], prefix: '\$'),
                textAlign: TextAlign.right,
                style: Mc.mono(12,
                    w: FontWeight.w600,
                    color: isLong ? Mc.up : Mc.down))),
      ],
    );
  }

  // ---------- ROW 5: 巨鲸警报 ----------
  Widget _whaleCard() {
    final rows = _whaleAlerts.take(10).toList();
    return McCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: McSection('巨鲸警报', tag: 'WHALE ALERTS'),
        ),
        const Divider(height: 1, color: Mc.hairline),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: McEmpty('暂无大额异动'),
          )
        else
          for (var i = 0; i < rows.length; i++) ...[
            _whaleRow(rows[i]),
            if (i != rows.length - 1)
              const Divider(height: 1, color: Mc.hairline),
          ],
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _whaleRow(dynamic a) {
    final isBuy = a['side'] == 'Buy';
    final source = (a['source'] ?? '链上').toString();
    final user = (a['user'] ?? '匿名大户').toString();
    return _HoverRow(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      children: [
        SizedBox(
            width: 56,
            child: Text(Fmt.hm(a['time']),
                style: Mc.mono(11, color: Mc.muted))),
        SizedBox(width: 110, child: McBadge(source, color: Mc.cobaltSoft)),
        Expanded(
            child: Text(user,
                overflow: TextOverflow.ellipsis, style: Mc.body(12))),
        SizedBox(
            width: 64,
            child: Text(_coinOf(a['symbol']),
                style: Mc.mono(12, w: FontWeight.w600))),
        SizedBox(
            width: 110,
            child: Text(Fmt.compact(a['positionSize'], prefix: '\$'),
                textAlign: TextAlign.right,
                style: Mc.mono(12, w: FontWeight.w600))),
        const SizedBox(width: 12),
        McBadge(isBuy ? '大额买入 BUY' : '大额卖出 SELL',
            color: isBuy ? Mc.up : Mc.down),
      ],
    );
  }
}

/// 蜡烛 + MA7/MA25 + 成交量副图 + 最新价虚线标签。
/// rows: 时间正序 [o,h,l,c,vol]。
class _KlinePainter extends CustomPainter {
  _KlinePainter(this.rows, {required this.up, required this.down});

  final List<List<num>> rows;
  final Color up;
  final Color down;

  @override
  void paint(Canvas canvas, Size size) {
    final n = rows.length;
    if (n == 0 || size.width <= 0 || size.height <= 0) return;
    final priceH = size.height * 0.74;
    final volTop = size.height * 0.82;
    final volH = size.height - volTop;

    double hi = -double.infinity, lo = double.infinity, maxVol = 0;
    for (final r in rows) {
      if (r[1] > hi) hi = r[1].toDouble();
      if (r[2] < lo) lo = r[2].toDouble();
      if (r[4] > maxVol) maxVol = r[4].toDouble();
    }
    final pad = (hi - lo) * 0.06 + 1e-9;
    hi += pad;
    lo -= pad;
    double py(double v) => (hi - v) / (hi - lo) * priceH;

    final slot = size.width / n;
    final bw = slot * 0.55;

    // 蜡烛 + 成交量
    for (var i = 0; i < n; i++) {
      final o = rows[i][0].toDouble(), h = rows[i][1].toDouble();
      final l = rows[i][2].toDouble(), c = rows[i][3].toDouble();
      final col = c >= o ? up : down;
      final x = slot * i + slot / 2;
      canvas.drawLine(Offset(x, py(h)), Offset(x, py(l)),
          Paint()
            ..color = col
            ..strokeWidth = 1);
      final yTop = py(math.max(o, c));
      final yBot = math.max(py(math.min(o, c)), yTop + 1);
      canvas.drawRect(
          Rect.fromLTRB(x - bw / 2, yTop, x + bw / 2, yBot),
          Paint()..color = col);
      if (maxVol > 0) {
        final vh = rows[i][4].toDouble() / maxVol * volH;
        canvas.drawRect(
            Rect.fromLTRB(x - bw / 2, size.height - vh, x + bw / 2,
                size.height),
            Paint()..color = col.withValues(alpha: 0.45));
      }
    }

    // MA7 (实线 cobalt) / MA25 (虚线 amber)
    final closes = [for (final r in rows) r[3].toDouble()];
    _strokePath(canvas, _maPath(closes, 7, py, slot),
        Paint()
          ..color = Mc.cobalt
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    _strokePath(canvas, _maPath(closes, 25, py, slot),
        Paint()
          ..color = Mc.amber
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
        dashed: true);

    // 最新价虚线 + 右侧标签
    final lastC = closes.last;
    final lastUp = rows.last[3] >= rows.last[0];
    final lastColor = lastUp ? up : down;
    final y = py(lastC).clamp(0.0, priceH);
    _dashedHLine(canvas, y, size.width, lastColor.withValues(alpha: 0.8));
    final tp = TextPainter(
        text: TextSpan(
            text: Fmt.num_(lastC, dp: 1),
            style: Mc.mono(9, w: FontWeight.w600, color: Mc.canvas)),
        textDirection: TextDirection.ltr)
      ..layout();
    final bx = size.width - tp.width - 8;
    final by = (y - tp.height / 2 - 2).clamp(0.0, size.height - tp.height - 4);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(bx, by, tp.width + 8, tp.height + 4),
            const Radius.circular(3)),
        Paint()..color = lastColor);
    tp.paint(canvas, Offset(bx + 4, by + 2));
  }

  Path _maPath(List<double> closes, int n, double Function(double) py,
      double slot) {
    final path = Path();
    var started = false;
    for (var i = 0; i < closes.length; i++) {
      if (i < n - 1) continue;
      var s = 0.0;
      for (var j = i - n + 1; j <= i; j++) {
        s += closes[j];
      }
      final x = slot * i + slot / 2;
      if (!started) {
        path.moveTo(x, py(s / n));
        started = true;
      } else {
        path.lineTo(x, py(s / n));
      }
    }
    return path;
  }

  void _strokePath(Canvas canvas, Path path, Paint paint,
      {bool dashed = false}) {
    if (!dashed) {
      canvas.drawPath(path, paint);
      return;
    }
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(
            m.extractPath(d, math.min(d + 4, m.length)), paint);
        d += 7;
      }
    }
  }

  void _dashedHLine(Canvas canvas, double y, double w, Color color) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x < w; x += 7) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, w), y), p);
    }
  }

  @override
  bool shouldRepaint(_KlinePainter old) => true;
}

/// 行悬停高亮 (Mc.cardHigh)，无斑马纹；可选整行点击。
class _HoverRow extends StatefulWidget {
  const _HoverRow({required this.children, this.padding, this.onTap});
  final List<Widget> children;
  final EdgeInsets? padding;
  final VoidCallback? onTap;

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: _hover ? Mc.cardHigh : Colors.transparent,
          padding: widget.padding ??
              const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(children: widget.children),
        ),
      ),
    );
  }
}

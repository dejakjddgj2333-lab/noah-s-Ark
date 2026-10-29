import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/kit.dart';
import '../widgets/shell.dart';
import 'market_detail_page.dart';

/// 行情页(对齐 PC 网页端 Market.vue):顶部遥测条 4 卡 + SPOT/永续切换 +
/// 搜索 + 行情表(7 日走势懒加载 + 自选星标)+ 分页条,15s 轮询。
class MarketPage extends StatefulWidget {
  const MarketPage({super.key});

  @override
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage> {
  /// 自选列表本地存储 key,与行情详情页共享契约。
  static const _watchKey = 'mc_watchlist';
  static const _pageSize = 20;

  final _search = TextEditingController();
  Timer? _timer;

  String _instType = 'SPOT';
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  int _page = 1;

  // ---- 顶部遥测条数据 ----
  Map<String, dynamic> _stats = const {};
  Map<String, dynamic> _lsRatio = const {};
  num? _fng;
  List<Map<String, dynamic>> _liqCoins = const [];

  // ---- 7 日走势缓存: instId -> 收盘价序列 (null = 无数据) ----
  final Map<String, List<double>?> _spark = {};
  final Set<String> _sparkPending = {};

  Set<String> _watchlist = {};

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() => _page = 1));
    _loadWatchlist();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<dynamic> _safe(Future<dynamic> f) async {
    try {
      return await f;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final res = await Future.wait([
      _safe(ApiClient.I.tickers(instType: _instType)),
      _safe(ApiClient.I.globalStats()),
      _safe(ApiClient.I.sentiment()),
      _safe(ApiClient.I.longShortRatio(symbol: 'BTC')),
      _safe(ApiClient.I.liqCoinList()),
    ]);
    if (!mounted) return;

    final tk = res[0];
    if (tk == null && !silent) {
      setState(() {
        _loading = false;
        _error = '行情加载失败';
      });
      return;
    }
    List<Map<String, dynamic>> rows = _rows;
    if (tk != null) {
      final list = (tk is Map ? tk['data'] : null) as List? ?? const [];
      rows = list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((t) {
            final id = t['instId'] as String? ?? '';
            return _instType == 'SWAP'
                ? id.endsWith('-USDT-SWAP')
                : id.endsWith('-USDT');
          })
          .toList()
        ..sort((a, b) =>
            (Fmt.toNum(b['volCcy24h']) ?? 0).compareTo(Fmt.toNum(a['volCcy24h']) ?? 0));
      rows = rows.take(100).toList();
    }
    final g = res[1];
    final s = res[2];
    final ls = res[3];
    final lq = res[4];
    setState(() {
      _rows = rows;
      if (g is Map) _stats = Map<String, dynamic>.from(g);
      if (s is Map) _fng = Fmt.toNum(s['fear_greed']);
      if (ls is Map) _lsRatio = Map<String, dynamic>.from(ls);
      if (lq is Map) {
        _liqCoins = ((lq['coins'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      _loading = false;
      _error = null;
    });
  }

  // ---------- 自选 (shared_preferences 'mc_watchlist', StringList 存 instId) ----------
  Future<void> _loadWatchlist() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() =>
        _watchlist = (prefs.getStringList(_watchKey) ?? const []).toSet());
  }

  Future<void> _toggleWatch(String instId) async {
    final next = {..._watchlist};
    if (next.contains(instId)) {
      next.remove(instId);
    } else {
      next.add(instId);
    }
    setState(() => _watchlist = next);
    final prefs = await SharedPreferences.getInstance();
    final sorted = next.toList()..sort();
    await prefs.setStringList(_watchKey, sorted);
  }

  // ---------- 过滤 / 分页 (照搬网页端逻辑) ----------
  List<Map<String, dynamic>> get _filtered {
    final kw = _search.text.trim().toUpperCase();
    if (kw.isEmpty) return _rows;
    return _rows
        .where((t) => (t['instId'] as String? ?? '').toUpperCase().contains(kw))
        .toList();
  }

  int get _totalPages {
    final n = (_filtered.length + _pageSize - 1) ~/ _pageSize;
    return n < 1 ? 1 : n;
  }

  int get _curPage => _page > _totalPages ? _totalPages : _page;

  List<Map<String, dynamic>> get _paged {
    final list = _filtered;
    final from = (_curPage - 1) * _pageSize;
    if (from >= list.length) return const [];
    final to = from + _pageSize > list.length ? list.length : from + _pageSize;
    return list.sublist(from, to);
  }

  List<int> get _pageNums {
    final t = _totalPages;
    final c = _curPage;
    var start = c - 1;
    if (start > t - 2) start = t - 2;
    if (start < 1) start = 1;
    final end = start + 2 > t ? t : start + 2;
    return [for (var i = start; i <= end; i++) i];
  }

  void _goPage(int p) {
    if (p < 1 || p > _totalPages) return;
    setState(() => _page = p);
  }

  void _switchType(String t) {
    if (_instType == t) return;
    setState(() {
      _instType = t;
      _page = 1;
      _loading = true;
      _error = null;
      _rows = [];
    });
    _load();
  }

  num _pct(Map<String, dynamic> t) {
    final open = Fmt.toNum(t['open24h']) ?? 0;
    if (open == 0) return 0;
    return ((Fmt.toNum(t['last']) ?? 0) - open) / open * 100;
  }

  void _openDetail(String instId) {
    ShellRouter.I.push('行情详情', 'MARKET', MarketDetailPage(instId: instId));
  }

  // ---------- 遥测条派生值 ----------
  String get _lsText {
    final l = Fmt.toNum(_lsRatio['long_pct']);
    final s = Fmt.toNum(_lsRatio['short_pct']);
    if (l == null || s == null || l == 0 || s == 0) return '--';
    return '${(l / s).toStringAsFixed(2)} : 1';
  }

  bool? get _lsLongLead {
    final l = Fmt.toNum(_lsRatio['long_pct']);
    final s = Fmt.toNum(_lsRatio['short_pct']);
    if (l == null || s == null || l == 0 || s == 0) return null;
    return l >= s;
  }

  String get _fngLabel {
    final v = _fng;
    if (v == null) return '--';
    if (v >= 75) return '极度贪婪';
    if (v >= 50) return '贪婪';
    if (v >= 25) return '恐慌';
    return '极度恐慌';
  }

  Color? get _fngColor {
    final v = _fng;
    if (v == null) return null;
    if (v >= 50) return Mc.bull;
    if (v >= 25) return Mc.amber;
    return Mc.bear;
  }

  num get _liqTotal => _liqCoins.fold<num>(
      0,
      (s, c) =>
          s + (Fmt.toNum(c['liquidation_usd_24h'] ?? c['liqUsd24h']) ?? 0));

  num? get _liqShortPct {
    num long = 0, short = 0;
    for (final c in _liqCoins) {
      long += Fmt.toNum(c['long_liquidation_usd_24h'] ?? c['longLiqUsd24h']) ?? 0;
      short +=
          Fmt.toNum(c['short_liquidation_usd_24h'] ?? c['shortLiqUsd24h']) ?? 0;
    }
    if (long == 0 && short == 0) return null;
    return short / (long + short) * 100;
  }

  // ---------- 7 日走势懒加载 (1D x 7, 仅当前页) ----------
  void _ensureSparks() {
    for (final t in _paged) {
      final id = t['instId'] as String? ?? '';
      if (id.isEmpty) continue;
      if (_spark.containsKey(id) || _sparkPending.contains(id)) continue;
      _sparkPending.add(id);
      ApiClient.I.candles(id, bar: '1D', limit: 7).then((res) {
        // OKX 风格数组 [ts,o,h,l,c,...],最新在前,反转为时间正序
        final raw = (res is Map ? res['data'] : null) as List? ?? const [];
        final closes = <double>[];
        for (final c in raw.reversed) {
          if (c is List && c.length > 4) {
            final v = Fmt.toNum(c[4]);
            if (v != null) closes.add(v.toDouble());
          }
        }
        if (!mounted) return;
        setState(() {
          _sparkPending.remove(id);
          _spark[id] = closes.length > 1 ? closes : null;
        });
      }).catchError((_) {
        if (!mounted) return;
        setState(() {
          _sparkPending.remove(id);
          _spark[id] = null;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loading) _ensureSparks();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 20),
        McSection(
          '行情',
          tag: 'MARKET · $_instType',
          trailing: Text(
            '共 ${_filtered.length} 个币种 · 15S AUTO REFRESH',
            style: Mc.tag(),
          ),
        ),
        const SizedBox(height: 14),
        _buildTelemetry(),
        const SizedBox(height: 16),
        _buildToolbar(),
        const SizedBox(height: 14),
        Expanded(child: _buildTable()),
        const SizedBox(height: 20),
      ]),
    );
  }

  // ---------- 顶部遥测条 4 卡 ----------
  Widget _buildTelemetry() {
    final capChg = Fmt.toNum(_stats['market_cap_change_pct_24h']);
    final longLead = _lsLongLead;
    final fngColor = _fngColor;
    final shortPct = _liqShortPct;
    return McRow(spans: const [3, 3, 3, 3], gap: 16, children: [
      _teleCard(
        label: '24H 全网成交额',
        icon: Icons.query_stats,
        value: Fmt.compact(_stats['total_volume_usd'], prefix: '\$'),
        sub: capChg == null ? null : Fmt.pct(capChg),
        subColor: capChg == null ? null : Mc.upDown(capChg),
      ),
      _teleCard(
        label: '多空比 (BTC)',
        icon: Icons.stacked_bar_chart,
        value: _lsText,
        sub: longLead == null ? null : (longLead ? '多头占优' : '空头占优'),
        subColor: longLead == null ? null : (longLead ? Mc.bull : Mc.bear),
      ),
      _teleCard(
        label: '恐惧 & 贪婪指数',
        icon: Icons.speed,
        value: _fng?.toStringAsFixed(0) ?? '--',
        valueColor: fngColor,
        sub: _fngLabel,
        subColor: fngColor,
      ),
      _teleCard(
        label: '24H 爆仓总额',
        icon: Icons.warning_amber_outlined,
        value: _liqTotal > 0 ? Fmt.compact(_liqTotal, prefix: '\$') : '--',
        sub: shortPct == null ? null : '空单爆仓 ${shortPct.toStringAsFixed(0)}%',
        subColor: shortPct == null ? null : Mc.bear,
      ),
    ]);
  }

  Widget _teleCard({
    required String label,
    required IconData icon,
    required String value,
    Color? valueColor,
    String? sub,
    Color? subColor,
  }) {
    return McCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: McTag(label)),
          Icon(icon, size: 16, color: Mc.muted),
        ]),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      Mc.mono(18, w: FontWeight.w700, color: valueColor ?? Mc.ink)),
            ),
            if (sub != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Mc.mono(11,
                        w: FontWeight.w600, color: subColor ?? Mc.muted)),
              ),
            ],
          ],
        ),
      ]),
    );
  }

  // ---------- SPOT / 永续切换 + 搜索 + 刷新 ----------
  Widget _buildToolbar() {
    return Container(
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Mc.hairline))),
      child: Row(children: [
        _tab('现货 SPOT', 'SPOT'),
        const SizedBox(width: 24),
        _tab('永续 PERP', 'SWAP'),
        const Spacer(),
        SizedBox(
          width: 240,
          child: McInput(
            controller: _search,
            hint: '搜索币种',
            prefix: Icons.search,
            height: 32,
          ),
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: McButton('刷新',
              kind: McBtnKind.ghost,
              height: 32,
              icon: Icons.refresh,
              onPressed: _load),
        ),
      ]),
    );
  }

  Widget _tab(String label, String type) {
    final active = _instType == type;
    return InkWell(
      onTap: () => _switchType(type),
      child: Container(
        padding: const EdgeInsets.only(left: 2, right: 2, bottom: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
                color: active ? Mc.cobalt : Colors.transparent, width: 2),
          ),
        ),
        child: Text(label,
            style: active
                ? Mc.display(14, w: FontWeight.w600)
                : Mc.body(13, color: Mc.muted)),
      ),
    );
  }

  // ---------- 行情数据表 ----------
  Widget _buildTable() {
    const headerDeco = BoxDecoration(
        color: Mc.surface,
        border: Border(bottom: BorderSide(color: Mc.hairline)));
    return McCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        Container(
          decoration: headerDeco,
          child: const Row(children: [
            SizedBox(width: 44, child: McTh('#', align: TextAlign.center)),
            Expanded(flex: 3, child: McTh('币种 / 资产')),
            Expanded(flex: 2, child: McTh('最新价 (USD)', align: TextAlign.right)),
            Expanded(flex: 2, child: McTh('24H 涨跌', align: TextAlign.right)),
            Expanded(flex: 2, child: McTh('24H 最高', align: TextAlign.right)),
            Expanded(flex: 2, child: McTh('24H 最低', align: TextAlign.right)),
            Expanded(flex: 2, child: McTh('24H 成交额', align: TextAlign.right)),
            Expanded(flex: 2, child: McTh('7日走势', align: TextAlign.center)),
            SizedBox(width: 48, child: McTh('自选', align: TextAlign.center)),
          ]),
        ),
        Expanded(child: _buildBody()),
        _buildFooter(),
      ]),
    );
  }

  Widget _buildBody() {
    if (_loading) return const McLoading(label: '行情加载中');
    if (_error != null) return McError(_error!, onRetry: _load);
    final list = _paged;
    if (list.isEmpty) return const McEmpty('无匹配币种');
    return Scrollbar(
      child: ListView.separated(
        itemCount: list.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, thickness: 1, color: Mc.hairline),
        itemBuilder: (_, i) => _row(list[i], (_curPage - 1) * _pageSize + i + 1),
      ),
    );
  }

  Widget _row(Map<String, dynamic> t, int rank) {
    final id = t['instId'] as String? ?? '';
    final coin = id.split('-').first;
    final pct = _pct(t);
    final watched = _watchlist.contains(id);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openDetail(id),
        hoverColor: Mc.cardHigh,
        child: SizedBox(
          height: 44,
          child: Row(children: [
            SizedBox(
              width: 44,
              child: Text('$rank',
                  textAlign: TextAlign.center,
                  style: Mc.mono(11, color: Mc.muted)),
            ),
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Mc.cobalt.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: Mc.cobalt.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      coin.isEmpty ? '?' : coin.substring(0, 1),
                      style: Mc.mono(10, w: FontWeight.w700, color: Mc.cobaltSoft),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(coin,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Mc.body(13, w: FontWeight.w600)),
                  ),
                  const SizedBox(width: 4),
                  Text(_instType == 'SWAP' ? '/ USDT 永续' : '/ USDT',
                      style: Mc.body(11, color: Mc.muted)),
                ]),
              ),
            ),
            _numCell(Fmt.num_(t['last'])),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: McBadge(Fmt.pct(pct), color: Mc.upDown(pct)),
                ),
              ),
            ),
            _numCell(Fmt.num_(t['high24h']), color: Mc.muted),
            _numCell(Fmt.num_(t['low24h']), color: Mc.muted),
            _numCell(Fmt.compact(t['volCcy24h'])),
            Expanded(flex: 2, child: Center(child: _sparkCell(id))),
            SizedBox(
              width: 48,
              child: Center(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _toggleWatch(id),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      watched ? Icons.star : Icons.star_border,
                      size: 16,
                      color: watched ? Mc.amber : Mc.muted,
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _sparkCell(String id) {
    final data = _spark[id];
    if (data == null) {
      return SizedBox(
        width: 96,
        height: 24,
        child: Center(
          child: _sparkPending.contains(id)
              ? const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: Mc.muted))
              : Text('--', style: Mc.mono(10, color: Mc.muted)),
        ),
      );
    }
    final up = data.last >= data.first;
    final color = up ? Mc.up : Mc.down;
    return SizedBox(
      width: 96,
      height: 24,
      child: LineChart(LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < data.length; i++)
                FlSpot(i.toDouble(), data[i])
            ],
            isCurved: true,
            curveSmoothness: 0.3,
            color: color,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
            belowBarData:
                BarAreaData(show: true, color: color.withValues(alpha: 0.2)),
          ),
        ],
      )),
    );
  }

  // ---------- 表尾与分页条 ----------
  Widget _buildFooter() {
    final total = _filtered.length;
    final from = total == 0 ? 0 : (_curPage - 1) * _pageSize + 1;
    final to = _curPage * _pageSize > total ? total : _curPage * _pageSize;
    final nums = _pageNums;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
          color: Mc.surface,
          border: Border(top: BorderSide(color: Mc.hairline))),
      child: Row(children: [
        Text('显示 $from - $to / $total 条目', style: Mc.tag()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text('|', style: Mc.tag(color: Mc.hairline)),
        ),
        Container(
          width: 6,
          height: 6,
          decoration:
              const BoxDecoration(color: Mc.bull, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text('OKX $_instType · 15S POLLING', style: Mc.tag()),
        const Spacer(),
        _pageBtn(Icons.chevron_left, _curPage > 1, () => _goPage(_curPage - 1)),
        for (final n in nums) _numBtn(n),
        if (_totalPages > nums.last + 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('...', style: Mc.tag()),
          ),
        if (_totalPages > nums.last) _numBtn(_totalPages),
        _pageBtn(Icons.chevron_right, _curPage < _totalPages,
            () => _goPage(_curPage + 1)),
      ]),
    );
  }

  Widget _pageBtn(IconData icon, bool enabled, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Mc.card,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Mc.hairline),
            ),
            child: Icon(icon, size: 14, color: Mc.muted),
          ),
        ),
      ),
    );
  }

  Widget _numBtn(int n) {
    final active = n == _curPage;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: () => _goPage(n),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? Mc.cobalt.withValues(alpha: 0.2) : Mc.card,
            borderRadius: BorderRadius.circular(4),
            border:
                Border.all(color: active ? Mc.cobalt : Mc.hairline),
          ),
          child: Text('$n',
              style: Mc.mono(11,
                  w: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? Mc.cobaltSoft : Mc.muted)),
        ),
      ),
    );
  }

  Widget _numCell(String text, {Color color = Mc.ink}) => Expanded(
        flex: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(text,
              textAlign: TextAlign.right, style: Mc.mono(12, color: color)),
        ),
      );
}

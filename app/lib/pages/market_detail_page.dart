import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/api.dart';
import '../services/data.dart';
import '../services/ticker_ws.dart';

/// 行情详情页: 实时价格 (OKX WS), 24H 统计, K线 / 盘口 / 成交 三 Tab,
/// 资金费率倒计时, 持仓量 (后端缺失时整卡隐藏).
class MarketDetailPage extends StatefulWidget {
  const MarketDetailPage({
    super.key,
    required this.instId,
    required this.symbol,
  });

  final String instId;
  final String symbol;

  @override
  State<MarketDetailPage> createState() => _MarketDetailPageState();
}

class _MarketDetailPageState extends State<MarketDetailPage> {
  // 实时行情 (REST 初始 + WS 推送覆盖).
  double _last = 0;
  double _open24h = 0;
  double _high24h = 0;
  double _low24h = 0;
  double _volCcy24h = 0;

  // 盘口 (books5 全量替换).
  List<BookLevel> _bids = const [];
  List<BookLevel> _asks = const [];

  // 逐笔成交 (新在前, 封顶 50).
  final List<TradePush> _trades = [];

  StreamSubscription<TickerPush>? _wsSub;
  StreamSubscription<BookPush>? _bookSub;
  StreamSubscription<TradePush>? _tradeSub;

  // K线.
  List<Map<String, double>> _candles = [];
  String _bar = '1H';
  bool _candleLoading = true;

  // 资金费率.
  double? _fundingRate;
  DateTime? _nextFunding;

  // 持仓量 (null = 未加载/失败, 整卡隐藏).
  double? _openInterest;

  static const _bars = ['15m', '1H', '4H', '1D'];

  double get _changePct =>
      _open24h > 0 ? (_last - _open24h) / _open24h * 100 : 0;
  double get _changeAbs => _last - _open24h;
  double get _notional => _volCcy24h * _last;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _subscribeLive();
    _loadCandles();
    _loadFunding();
    _loadOpenInterest();
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _bookSub?.cancel();
    _tradeSub?.cancel();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    try {
      final t = await McData.ticker(widget.instId);
      if (!mounted) return;
      setState(() {
        _last = t.last;
        _open24h = t.open24h;
        _high24h = t.high24h;
        _low24h = t.low24h;
        _volCcy24h = t.volCcy24h;
      });
    } catch (_) {/* 保留占位, 等待 WS 推送 */}
  }

  void _subscribeLive() {
    final ws = TickerWs.instance;
    ws.subscribe({widget.instId});
    ws.subscribeBooks(widget.instId);
    ws.subscribeTrades(widget.instId);

    _wsSub = ws.stream.listen((p) {
      if (!mounted || p.instId != widget.instId) return;
      setState(() {
        _last = p.last;
        _open24h = p.open24h;
        _high24h = p.high24h;
        _low24h = p.low24h;
        _volCcy24h = p.volCcy24h;
      });
    }, onError: (_) {});

    _bookSub = ws.bookStream.listen((b) {
      if (!mounted || b.instId != widget.instId) return;
      setState(() {
        _bids = b.bids;
        _asks = b.asks;
      });
    }, onError: (_) {});

    _tradeSub = ws.tradeStream.listen((t) {
      if (!mounted || t.instId != widget.instId) return;
      setState(() {
        _trades.insert(0, t);
        if (_trades.length > 50) _trades.removeRange(50, _trades.length);
      });
    }, onError: (_) {});
  }

  Future<void> _loadCandles() async {
    setState(() => _candleLoading = true);
    try {
      final data = await McData.candles(widget.instId, bar: _bar, limit: 60);
      if (!mounted) return;
      setState(() {
        _candles = data;
        _candleLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _candles = [];
        _candleLoading = false;
      });
    }
  }

  Future<void> _loadFunding() async {
    try {
      final f = await McData.fundingRate(widget.instId);
      if (!mounted) return;
      setState(() {
        _fundingRate = f.rate;
        _nextFunding = f.nextFundingTime;
      });
    } catch (_) {/* 保留 null 占位 */}
  }

  /// 持仓量: 后端可能无此端点, ApiException 时整卡隐藏 (不报错).
  Future<void> _loadOpenInterest() async {
    try {
      final resp = await McData.overview('open-interest?symbol=${widget.symbol}');
      final v = _findNumber(resp);
      if (!mounted || v == null || v <= 0) return;
      setState(() => _openInterest = v);
    } on ApiException {
      // 端点不存在 -> 整卡隐藏.
    } catch (_) {}
  }

  /// 在响应里尽力找一个合理的持仓量数值 (USD).
  static double? _findNumber(dynamic raw) {
    double? pick(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse('$v');
    }

    dynamic node = raw;
    // 常见包裹: {data: ...} / {data: [...]}.
    if (node is Map && node.containsKey('data')) node = node['data'];
    if (node is List) node = node.isEmpty ? null : node.first;
    if (node is! Map) return pick(node);
    const keys = [
      'openInterest',
      'open_interest',
      'openInterestUsd',
      'open_interest_usd',
      'oi',
      'oiUsd',
      'value',
    ];
    for (final k in keys) {
      if (node.containsKey(k)) {
        final v = pick(node[k]);
        if (v != null) return v;
      }
    }
    // 兜底: 取第一个数值型字段.
    for (final e in node.values) {
      final v = pick(e);
      if (v != null) return v;
    }
    return null;
  }

  void _selectBar(String bar) {
    if (bar == _bar) return;
    setState(() => _bar = bar);
    _loadCandles();
  }

  @override
  Widget build(BuildContext context) {
    final pct = _changePct;
    final pctColor = pct >= 0 ? McColors.bull : McColors.bear;
    return Scaffold(
      backgroundColor: McColors.surface,
      body: SafeArea(
        child: DefaultTabController(
          length: 3,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: _buildHeader(pct, pctColor),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: _buildStatsRow(),
              ),
              if (_openInterest != null) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: _buildOpenInterestCard(),
                ),
              ],
              const SizedBox(height: 12),
              _buildTabBar(),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildKlineTab(),
                    _buildOrderBookTab(),
                    _buildTradesTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶部: 返回 + 标题 + 大字价格 + 涨跌徽章.
  Widget _buildHeader(double pct, Color pctColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back,
                  size: 20, color: McColors.onSurface),
              onPressed: () => Navigator.of(context).pop(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            const SizedBox(width: 4),
            Text(
              widget.symbol,
              style: McText.sans(size: 16, weight: FontWeight.w700),
            ),
            Text(
              '/USDT 永续',
              style: McText.sans(size: 13, color: McColors.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _last > 0 ? _fmtPrice(_last) : '--',
                    style: McText.display(
                        size: 30, weight: FontWeight.w700, color: pctColor),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: pctColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: pctColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
                  style: McText.mono(
                      size: 12, weight: FontWeight.w700, color: pctColor),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 24H 统计: 高 / 低 / 涨跌额 / 成交额 (2×2 网格).
  Widget _buildStatsRow() {
    final abs = _changeAbs;
    final absColor = abs >= 0 ? McColors.bull : McColors.bear;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _stat('24H 最高',
                  _high24h > 0 ? _fmtPrice(_high24h) : '--', McColors.bull),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _stat('24H 最低',
                  _low24h > 0 ? _fmtPrice(_low24h) : '--', McColors.bear),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _stat(
                  '24H 涨跌额',
                  _open24h > 0
                      ? '${abs >= 0 ? '+' : ''}${_fmtPrice(abs)}'
                      : '--',
                  absColor),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _stat('24H 成交额',
                  _notional > 0 ? McData.fmtUsdCompact(_notional) : '--',
                  McColors.onSurface),
            ),
          ],
        ),
      ],
    );
  }

  Widget _stat(String label, String value, Color valueColor) {
    return McCard(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: McText.sans(
                size: 14, weight: FontWeight.w700, color: valueColor),
          ),
        ],
      ),
    );
  }

  /// 持仓量卡 (仅成功加载时显示).
  Widget _buildOpenInterestCard() {
    final oi = _openInterest!;
    return McCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(Icons.stacked_bar_chart,
              size: 15, color: McColors.secondary),
          const SizedBox(width: 8),
          Text('持仓量',
              style: McText.sans(size: 13, weight: FontWeight.w600)),
          const Spacer(),
          Text(
            McData.fmtUsdCompact(oi),
            style: McText.mono(
                size: 16, weight: FontWeight.w700, color: McColors.onSurface),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: McColors.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: TabBar(
        labelColor: McColors.primary,
        unselectedLabelColor: McColors.onSurfaceVariant,
        indicatorColor: McColors.primaryContainer,
        indicatorWeight: 2.5,
        labelStyle: McText.sans(size: 13, weight: FontWeight.w700),
        unselectedLabelStyle: McText.sans(size: 13, weight: FontWeight.w500),
        tabs: const [
          Tab(text: 'K线'),
          Tab(text: '盘口'),
          Tab(text: '成交'),
        ],
      ),
    );
  }

  // ---------------- Tab 1: K线 + 资金费率 ----------------

  Widget _buildKlineTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
      children: [
        _buildKlineSection(),
        const SizedBox(height: 16),
        _FundingCountdownCard(rate: _fundingRate, nextFunding: _nextFunding),
      ],
    );
  }

  /// K线区: 周期切换 + 蜡烛图.
  Widget _buildKlineSection() {
    return McCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('K线走势',
                  style: McText.sans(size: 13, weight: FontWeight.w600)),
              Row(
                children: [
                  for (final b in _bars)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: _barChip(b),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 240,
            child: _candleLoading
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: McColors.primary),
                    ),
                  )
                : _candles.isEmpty
                    ? Center(
                        child: Text('暂无K线数据',
                            style: McText.sans(
                                size: 12,
                                color: McColors.onSurfaceVariant)),
                      )
                    : CustomPaint(
                        size: Size.infinite,
                        painter: _CandlePainter(
                          candles: _candles,
                          lastPrice: _last,
                          bull: McColors.bull,
                          bear: McColors.bear,
                          gridColor: McColors.outlineVariant,
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _barChip(String bar) {
    final active = _bar == bar;
    return GestureDetector(
      onTap: () => _selectBar(bar),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? McColors.surfaceContainerHighest
              : McColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          bar,
          style: McText.sans(
            size: 12,
            weight: active ? FontWeight.w600 : FontWeight.w500,
            color: active ? McColors.onSurface : McColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  // ---------------- Tab 2: 盘口 ----------------

  Widget _buildOrderBookTab() {
    // 卖盘升序 -> 反转, 顶部显示最高卖价.
    final asks = _asks.reversed.toList();
    final bids = _bids;
    var maxSz = 0.0;
    for (final l in _asks) {
      if (l.sz > maxSz) maxSz = l.sz;
    }
    for (final l in _bids) {
      if (l.sz > maxSz) maxSz = l.sz;
    }
    final empty = _asks.isEmpty && _bids.isEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
      children: [
        McCard(
          padding: const EdgeInsets.all(14),
          child: empty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text('等待盘口数据…',
                        style: McText.sans(
                            size: 12, color: McColors.onSurfaceVariant)),
                  ),
                )
              : Column(
                  children: [
                    _bookHeader(),
                    const SizedBox(height: 8),
                    // 卖盘 (上 5, 红).
                    for (final l in asks)
                      _bookRow(l, McColors.bear, maxSz, Alignment.centerRight),
                    const SizedBox(height: 8),
                    _spreadRow(),
                    const SizedBox(height: 8),
                    // 买盘 (下 5, 绿).
                    for (final l in bids)
                      _bookRow(l, McColors.bull, maxSz, Alignment.centerRight),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _bookHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('价格 (USDT)',
            style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
        Text('数量 (${widget.symbol})',
            style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
      ],
    );
  }

  Widget _bookRow(BookLevel l, Color color, double maxSz, Alignment align) {
    final frac = maxSz > 0 ? (l.sz / maxSz).clamp(0.0, 1.0) : 0.0;
    return SizedBox(
      height: 26,
      child: Stack(
        children: [
          // 深度条 (右侧对齐).
          Align(
            alignment: align,
            child: FractionallySizedBox(
              widthFactor: frac,
              child: Container(color: color.withValues(alpha: 0.10)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmtNum(l.px),
                    style: McText.mono(
                        size: 12, weight: FontWeight.w600, color: color)),
                Text(_fmtSz(l.sz),
                    style: McText.mono(
                        size: 12, color: McColors.onSurface)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 中间价差行: 最新价 + 标记提示.
  Widget _spreadRow() {
    final bestBid = _bids.isNotEmpty ? _bids.first.px : 0.0;
    final bestAsk = _asks.isNotEmpty ? _asks.first.px : 0.0;
    final spread = (bestAsk > 0 && bestBid > 0) ? bestAsk - bestBid : 0.0;
    final pctColor = _changePct >= 0 ? McColors.bull : McColors.bear;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Text(
            _last > 0 ? _fmtNum(_last) : '--',
            style: McText.mono(
                size: 15, weight: FontWeight.w700, color: pctColor),
          ),
          const SizedBox(width: 6),
          Text('标记',
              style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
          const Spacer(),
          Text(
            '价差 ${spread > 0 ? _fmtNum(spread) : '--'}',
            style: McText.mono(size: 12, color: McColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  // ---------------- Tab 3: 成交 ----------------

  Widget _buildTradesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: Text('时间',
                    style: McText.sans(
                        size: 12, color: McColors.onSurfaceVariant)),
              ),
              Expanded(
                child: Text('价格 (USDT)',
                    textAlign: TextAlign.center,
                    style: McText.sans(
                        size: 12, color: McColors.onSurfaceVariant)),
              ),
              Expanded(
                child: Text('数量 (${widget.symbol})',
                    textAlign: TextAlign.right,
                    style: McText.sans(
                        size: 12, color: McColors.onSurfaceVariant)),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: McColors.outlineVariant.withValues(alpha: 0.4)),
        Expanded(
          child: _trades.isEmpty
              ? Center(
                  child: Text('等待成交数据…',
                      style: McText.sans(
                          size: 12, color: McColors.onSurfaceVariant)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: _trades.length,
                  itemBuilder: (context, i) {
                    final t = _trades[i];
                    final buy = t.side == 'buy';
                    final c = buy ? McColors.bull : McColors.bear;
                    return SizedBox(
                      height: 26,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(_fmtClock(t.ts),
                                style: McText.mono(
                                    size: 12,
                                    color: McColors.onSurfaceVariant)),
                          ),
                          Expanded(
                            child: Text(_fmtNum(t.px),
                                textAlign: TextAlign.center,
                                style: McText.mono(
                                    size: 12,
                                    weight: FontWeight.w600,
                                    color: c)),
                          ),
                          Expanded(
                            child: Text(_fmtSz(t.sz),
                                textAlign: TextAlign.right,
                                style: McText.mono(
                                    size: 12, color: McColors.onSurface)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ---------------- 格式化 ----------------

  static String _fmtPrice(double p) {
    if (p >= 1000) return '\$${_comma(p)}';
    if (p.abs() > 0 && p.abs() < 10) return '\$${p.toStringAsFixed(4)}';
    return '\$${p.toStringAsFixed(2)}';
  }

  /// 无货币符号的裸价格 (盘口/成交用), 自适应精度.
  static String _fmtNum(double p) {
    if (p >= 1000) return _comma(p);
    if (p.abs() > 0 && p.abs() < 10) return p.toStringAsFixed(4);
    return p.toStringAsFixed(2);
  }

  static String _fmtSz(double sz) {
    if (sz >= 1000) return _comma(sz);
    if (sz.abs() > 0 && sz.abs() < 1) return sz.toStringAsFixed(4);
    return sz.toStringAsFixed(2);
  }

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

  /// ms 时间戳 → HH:mm:ss.
  static String _fmtClock(int ms) {
    if (ms <= 0) return '--:--:--';
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}

/// 资金费率卡: 当前费率 + 下次结算倒计时 (每秒滴答).
class _FundingCountdownCard extends StatefulWidget {
  const _FundingCountdownCard({required this.rate, required this.nextFunding});

  final double? rate;
  final DateTime? nextFunding;

  @override
  State<_FundingCountdownCard> createState() => _FundingCountdownCardState();
}

class _FundingCountdownCardState extends State<_FundingCountdownCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _countdown {
    final next = widget.nextFunding;
    if (next == null) return '--:--:--';
    var diff = next.difference(DateTime.now());
    if (diff.isNegative) diff = Duration.zero;
    String two(int n) => n.toString().padLeft(2, '0');
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    final s = diff.inSeconds % 60;
    return '${two(h)}:${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final rate = widget.rate;
    final rateColor = (rate ?? 0) >= 0 ? McColors.bull : McColors.bear;
    return McCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.percent, size: 15, color: McColors.secondary),
              const SizedBox(width: 6),
              Text('资金费率',
                  style: McText.sans(size: 13, weight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _item(
                  '当前费率',
                  rate == null
                      ? '--'
                      : '${rate >= 0 ? '+' : ''}${(rate * 100).toStringAsFixed(4)}%',
                  rateColor,
                ),
              ),
              Expanded(
                child: _item('下次结算', _countdown, McColors.onSurface),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _item(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text(value,
            style: McText.mono(
                size: 14, weight: FontWeight.w700, color: valueColor)),
      ],
    );
  }
}

/// 蜡烛图画笔: 绿涨红跌, 上下影线, 暗色背景网格 + 最新价虚线.
class _CandlePainter extends CustomPainter {
  _CandlePainter({
    required this.candles,
    required this.lastPrice,
    required this.bull,
    required this.bear,
    required this.gridColor,
  });

  final List<Map<String, double>> candles;
  final double lastPrice;
  final Color bull;
  final Color bear;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    var lo = double.infinity;
    var hi = -double.infinity;
    for (final c in candles) {
      if (c['l']! < lo) lo = c['l']!;
      if (c['h']! > hi) hi = c['h']!;
    }
    if (lastPrice > 0) {
      if (lastPrice < lo) lo = lastPrice;
      if (lastPrice > hi) hi = lastPrice;
    }
    final range = hi - lo;
    if (range <= 0) return;
    // 上下各留 6% 边距.
    final pad = range * 0.06;
    final min = lo - pad;
    final span = range + pad * 2;

    double yOf(double price) =>
        size.height - (price - min) / span * size.height;

    // 水平网格线 (4 条).
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    for (var i = 1; i <= 4; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final count = candles.length;
    final step = size.width / count;
    final bodyW = (step * 0.6).clamp(1.0, step);

    for (var i = 0; i < count; i++) {
      final c = candles[i];
      final o = c['o']!;
      final h = c['h']!;
      final l = c['l']!;
      final cl = c['c']!;
      final up = cl >= o;
      final color = up ? bull : bear;
      final cx = i * step + step / 2;

      // 影线.
      final wickPaint = Paint()
        ..color = color
        ..strokeWidth = 1;
      canvas.drawLine(Offset(cx, yOf(h)), Offset(cx, yOf(l)), wickPaint);

      // 实体.
      final bodyPaint = Paint()..color = color;
      final top = yOf(up ? cl : o);
      final bottom = yOf(up ? o : cl);
      final rect = Rect.fromLTRB(
        cx - bodyW / 2,
        top,
        cx + bodyW / 2,
        (bottom - top).abs() < 1 ? top + 1 : bottom,
      );
      canvas.drawRect(rect, bodyPaint);
    }

    // 最新价虚线.
    if (lastPrice > 0 && lastPrice >= min && lastPrice <= min + span) {
      final y = yOf(lastPrice);
      final dashPaint = Paint()
        ..color = McColors.onSurfaceVariant.withValues(alpha: 0.8)
        ..strokeWidth = 1;
      const dashW = 5.0;
      const gapW = 4.0;
      var x = 0.0;
      while (x < size.width) {
        canvas.drawLine(Offset(x, y), Offset(x + dashW, y), dashPaint);
        x += dashW + gapW;
      }
    }
  }

  @override
  bool shouldRepaint(_CandlePainter old) =>
      old.candles != candles || old.lastPrice != lastPrice;
}

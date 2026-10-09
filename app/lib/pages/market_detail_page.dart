import 'dart:async';

import 'package:flutter/material.dart';

import '../core/coin_icon.dart';
import '../core/color_pref.dart';
import '../core/l10n.dart';
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
  // 当前交易对 (init 来自路由参数, 页内可切换, OKX 风格下拉选币).
  late String _instId = widget.instId;
  late String _symbol = widget.symbol;

  // 实时行情 (REST 初始 + WS 推送覆盖).
  double _last = 0;
  double _open24h = 0;
  double _high24h = 0;
  double _low24h = 0;
  double _volCcy24h = 0;

  // 盘口 (OKX books5 WS 全量替换; REST 仅首帧+断流兜底).
  List<BookLevel> _bids = const [];
  List<BookLevel> _asks = const [];

  // 逐笔成交 (OKX trades WS 前置插入, 新在前, 封顶 50).
  final List<TradePush> _trades = [];

  StreamSubscription<TickerPush>? _wsSub;
  StreamSubscription<BookPush>? _bookSub;
  StreamSubscription<TradePush>? _tradeSub;
  // WS 断流兜底: 记录最后一次 WS 盘口到达时间, 超时用 REST 补.
  DateTime? _lastBookWsAt;
  Timer? _fallbackTimer;

  // K线.
  List<Map<String, double>> _candles = [];

  // K 线手势: 可见窗口 (startIndex=最旧可见下标, viewCount=可见根数).
  // viewCount<=0 表示"全部", 窗口锚定最新; 拖拽移动窗口, 捏合缩放根数.
  int _viewCount = 0;
  double _viewAnchor = 0; // 浮点锚点, 拖拽时按像素换算根数, 渲染时取整
  String _bar = '1H';
  bool _candleLoading = true;

  // 资金费率.
  double? _fundingRate;
  DateTime? _nextFunding;

  // 持仓量 (null = 未加载/失败, 整卡隐藏).
  double? _openInterest;

  static const _bars = ['15m', '1H', '4H', '1D'];

  /// 是否永续合约; 现货无资金费率/持仓量, 对应卡片隐藏.
  bool get _isSwap => _instId.endsWith('-SWAP');

  double get _changePct =>
      _open24h > 0 ? (_last - _open24h) / _open24h * 100 : 0;
  double get _changeAbs => _last - _open24h;
  double get _notional => _volCcy24h * _last;

  @override
  void initState() {
    super.initState();
    _subscribeLive();
    _fillOnce();
    // 兜底: WS 6s 无盘口数据(被墙/断流)时, REST 补一轮.
    _fallbackTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final at = _lastBookWsAt;
      if (at == null ||
          DateTime.now().difference(at) > const Duration(seconds: 6)) {
        _fillOnce();
      }
    });
    _loadCandles();
    if (_isSwap) {
      _loadFunding();
      _loadOpenInterest();
    }
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _bookSub?.cancel();
    _tradeSub?.cancel();
    _fallbackTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    try {
      final t = await McData.ticker(_instId);
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

  /// REST 首帧填充/断流兜底: ticker + 盘口 + 成交, 互不阻塞.
  Future<void> _fillOnce() async {
    await Future.wait([
      _loadInitial(),
      () async {
        try {
          final (bids, asks) = await McData.orderBook(_instId);
          if (!mounted) return;
          setState(() {
            _bids = bids;
            _asks = asks;
          });
        } catch (_) {/* 保留旧盘口 */}
      }(),
      () async {
        try {
          final trades = await McData.recentTrades(_instId);
          if (!mounted || trades.isEmpty) return;
          setState(() {
            _trades
              ..clear()
              ..addAll(trades);
          });
        } catch (_) {/* 保留旧成交 */}
      }(),
    ]);
  }

  void _subscribeLive() {
    final ws = TickerWs.instance;
    ws.subscribe({_instId});
    ws.subscribeBooks(_instId);
    ws.subscribeTrades(_instId);

    _wsSub = ws.stream.listen((p) {
      if (!mounted || p.instId != _instId) return;
      setState(() {
        _last = p.last;
        _open24h = p.open24h;
        _high24h = p.high24h;
        _low24h = p.low24h;
        _volCcy24h = p.volCcy24h;
      });
    }, onError: (_) {});

    _bookSub = ws.bookStream.listen((b) {
      if (!mounted || b.instId != _instId) return;
      _lastBookWsAt = DateTime.now();
      setState(() {
        _bids = b.bids;
        _asks = b.asks;
      });
    }, onError: (_) {});

    _tradeSub = ws.tradeStream.listen((t) {
      if (!mounted || t.instId != _instId) return;
      setState(() {
        _trades.insert(0, t);
        if (_trades.length > 50) _trades.removeRange(50, _trades.length);
      });
    }, onError: (_) {});
  }

  Future<void> _loadCandles() async {
    setState(() => _candleLoading = true);
    try {
      final data = await McData.candles(_instId, bar: _bar, limit: 200);
      if (!mounted) return;
      setState(() {
        _candles = data;
        _candleLoading = false;
        // 换周期/换币重置视图: 显示最近 60 根, 锚定最新.
        _viewCount = 60;
        _viewAnchor = (data.length - 60).clamp(0, data.length).toDouble();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _candles = [];
        _candleLoading = false;
        _viewCount = 0;
      });
    }
  }

  Future<void> _loadFunding() async {
    try {
      final f = await McData.fundingRate(_instId);
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
      final resp = await McData.overview('open-interest?symbol=${_symbol}');
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

  // ---------------- 币种切换 (OKX 风格下拉选币) ----------------

  /// 切换交易对: 重置全部状态并重拉/重订阅. WS 单例无需退订,
  /// 各监听按 _instId 过滤, 旧币种推送自动忽略.
  void _switchSymbol(String instId) {
    if (instId == _instId) return;
    setState(() {
      _instId = instId;
      _symbol = instId.replaceAll('-USDT-SWAP', '').replaceAll('-USDT', '');
      _last = 0;
      _open24h = 0;
      _high24h = 0;
      _low24h = 0;
      _volCcy24h = 0;
      _bids = const [];
      _asks = const [];
      _trades.clear();
      _lastBookWsAt = null;
      _candles = [];
      _candleLoading = true;
      _fundingRate = null;
      _nextFunding = null;
      _openInterest = null;
    });
    _subscribeLive();
    _fillOnce();
    _loadCandles();
    if (_isSwap) {
      _loadFunding();
      _loadOpenInterest();
    }
  }

  /// 全屏选币面板: 搜索 + 永续列表 (按 24H 成交额排序).
  void _openSwitcher() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: McColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _SymbolSwitcherSheet(
        current: _instId,
        onSelect: (id) {
          Navigator.of(context).pop();
          _switchSymbol(id);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pct = _changePct;
    final pctColor = pct >= 0 ? ColorPref.instance.bullColor : ColorPref.instance.bearColor;
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
            // 币名 + 下拉箭头: 点开全屏选币面板 (OKX 风格).
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openSwitcher,
              child: Row(
                children: [
                  Text(
                    _symbol,
                    style: McText.sans(size: 16, weight: FontWeight.w700),
                  ),
                  Text(
                    _isSwap
                        ? '/USDT ${tr('mktd_perp')}'
                        : '/USDT ${tr('mktd_spot')}',
                    style: McText.sans(
                        size: 13, color: McColors.onSurfaceVariant),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.keyboard_arrow_down,
                      size: 18, color: McColors.onSurfaceVariant),
                ],
              ),
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
    final absColor = abs >= 0 ? ColorPref.instance.bullColor : ColorPref.instance.bearColor;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _stat(tr('mktd_high_24h'),
                  _high24h > 0 ? _fmtPrice(_high24h) : '--', ColorPref.instance.bullColor),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _stat(tr('mktd_low_24h'),
                  _low24h > 0 ? _fmtPrice(_low24h) : '--', ColorPref.instance.bearColor),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _stat(
                  tr('mktd_change_24h'),
                  _open24h > 0
                      ? '${abs >= 0 ? '+' : ''}${_fmtPrice(abs)}'
                      : '--',
                  absColor),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _stat(tr('mktd_turnover_24h'),
                  _notional > 0 ? _fmtZh(_notional) : '--',
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
          Text(tr('mktd_open_interest'),
              style: McText.sans(size: 13, weight: FontWeight.w600)),
          const Spacer(),
          Text(
            _fmtZh(oi),
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
        tabs: [
          Tab(text: tr('mktd_tab_kline')),
          Tab(text: tr('mktd_tab_orderbook')),
          Tab(text: tr('mktd_tab_trades')),
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
        if (_isSwap) ...[
          const SizedBox(height: 16),
          _FundingCountdownCard(rate: _fundingRate, nextFunding: _nextFunding),
        ],
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
              Text(tr('mktd_kline_trend'),
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
                        child: Text(tr('mktd_no_kline'),
                            style: McText.sans(
                                size: 12,
                                color: McColors.onSurfaceVariant)),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final chartW = constraints.maxWidth - 52;
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onScaleStart: (_) {},
                            onScaleUpdate: (d) =>
                                _onChartScale(d, chartW),
                            child: CustomPaint(
                              size: Size.infinite,
                              painter: _CandlePainter(
                                candles: _candles,
                                lastPrice: _last,
                                bar: _bar,
                                startIndex: _viewCount > 0
                                    ? _viewAnchor.round().clamp(
                                        0, _candles.length - 1)
                                    : 0,
                                viewCount: _viewCount > 0
                                    ? _viewCount.clamp(
                                        1, _candles.length)
                                    : _candles.length,
                                bull: ColorPref.instance.bullColor,
                                bear: ColorPref.instance.bearColor,
                                gridColor: McColors.outlineVariant,
                                labelColor: McColors.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  /// K 线手势: 单指水平拖 = 移动窗口, 双指捏合 = 缩放可见根数.
  /// 缩放锚定最新端 (右缘不动), 拖到历史后缩放锚定窗口中心.
  void _onChartScale(ScaleUpdateDetails d, double chartW) {
    if (_candles.length < 2 || chartW <= 0) return;
    if (_viewCount <= 0) {
      _viewCount = _candles.length;
      _viewAnchor = 0;
    }
    setState(() {
      if (d.scale != 1.0) {
        // 捏合: 可见根数反比缩放, 10..全部.
        var cnt = (_viewCount / d.scale).round();
        cnt = cnt.clamp(10, _candles.length);
        if (cnt != _viewCount) {
          final atRightEdge =
              _viewAnchor >= _candles.length - _viewCount - 0.5;
          if (atRightEdge) {
            _viewAnchor = (_candles.length - cnt).toDouble();
          } else {
            final center = _viewAnchor + _viewCount / 2;
            _viewAnchor = center - cnt / 2;
          }
          _viewCount = cnt;
        }
      }
      if (d.focalPointDelta.dx != 0) {
        // 拖动: 每根蜡烛 step 像素, 向左拖 = 看更早 (窗口左移).
        final step = chartW / _viewCount;
        _viewAnchor -= d.focalPointDelta.dx / step;
      }
      _viewAnchor = _viewAnchor
          .clamp(0.0, (_candles.length - _viewCount).toDouble());
    });
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
                    child: Text(tr('mktd_waiting_orderbook'),
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
                      _bookRow(l, ColorPref.instance.bearColor, maxSz, Alignment.centerRight),
                    const SizedBox(height: 8),
                    _spreadRow(),
                    const SizedBox(height: 8),
                    // 买盘 (下 5, 绿).
                    for (final l in bids)
                      _bookRow(l, ColorPref.instance.bullColor, maxSz, Alignment.centerRight),
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
        Text(tr('mktd_price_usdt'),
            style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
        Text(tr('mktd_amount').replaceAll('{symbol}', _symbol),
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
    final pctColor = _changePct >= 0 ? ColorPref.instance.bullColor : ColorPref.instance.bearColor;
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
          Text(tr('mktd_mark'),
              style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
          const Spacer(),
          Text(
            '${tr('mktd_spread')} ${spread > 0 ? _fmtNum(spread) : '--'}',
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
                child: Text(tr('mktd_time'),
                    style: McText.sans(
                        size: 12, color: McColors.onSurfaceVariant)),
              ),
              Expanded(
                child: Text(tr('mktd_price_usdt'),
                    textAlign: TextAlign.center,
                    style: McText.sans(
                        size: 12, color: McColors.onSurfaceVariant)),
              ),
              Expanded(
                child: Text(tr('mktd_amount').replaceAll('{symbol}', _symbol),
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
                  child: Text(tr('mktd_waiting_trades'),
                      style: McText.sans(
                          size: 12, color: McColors.onSurfaceVariant)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: _trades.length,
                  itemBuilder: (context, i) {
                    final t = _trades[i];
                    final buy = t.side == 'buy';
                    final c = buy ? ColorPref.instance.bullColor : ColorPref.instance.bearColor;
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

  /// 美元金额中文紧凑格式: 万/亿, 不用 K/M/B.
  static String _fmtZh(double usd) {
    final a = usd.abs();
    if (a >= 1e8) return '\$${(usd / 1e8).toStringAsFixed(2)}亿';
    if (a >= 1e4) return '\$${(usd / 1e4).toStringAsFixed(1)}万';
    return '\$${usd.toStringAsFixed(2)}';
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
    final rateColor = (rate ?? 0) >= 0 ? ColorPref.instance.bullColor : ColorPref.instance.bearColor;
    return McCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.percent, size: 15, color: McColors.secondary),
              const SizedBox(width: 6),
              Text(tr('mktd_funding_rate'),
                  style: McText.sans(size: 13, weight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _item(
                  tr('mktd_current_rate'),
                  rate == null
                      ? '--'
                      : '${rate >= 0 ? '+' : ''}${(rate * 100).toStringAsFixed(4)}%',
                  rateColor,
                ),
              ),
              Expanded(
                child: _item(tr('mktd_next_settle'), _countdown, McColors.onSurface),
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

/// OKX 风格蜡烛图: 右轴价标 + 时间轴 + MA5/10/20 + 成交量副图 + 最新价标签.
class _CandlePainter extends CustomPainter {
  _CandlePainter({
    required this.candles,
    required this.lastPrice,
    required this.bar,
    required this.bull,
    required this.bear,
    required this.gridColor,
    required this.labelColor,
    this.startIndex = 0,
    this.viewCount = 0,
  });

  final List<Map<String, double>> candles;
  final double lastPrice;
  final String bar;
  final Color bull;
  final Color bear;
  final Color gridColor;
  final Color labelColor;

  /// 可见窗口: [startIndex, startIndex+viewCount); viewCount<=0 = 全部.
  final int startIndex;
  final int viewCount;

  static const _labelW = 52.0; // 右轴价标宽
  static const _timeH = 16.0; // 底部时间轴高
  static const _legendH = 20.0; // 顶部 MA 图例区高 (价格绘图区下移, 不压 K 线)
  static const _volRatio = 0.22; // 成交量副图占比
  static const _ma5Color = Color(0xFFE8EAF0);
  static const _ma10Color = Color(0xFFF0B90B);
  static const _ma20Color = Color(0xFFB877DB);

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;
    // 可见窗口裁剪.
    final total = candles.length;
    var s0 = startIndex.clamp(0, total - 1);
    var cnt = viewCount <= 0 ? total : viewCount.clamp(1, total - s0);
    final s1 = (s0 + cnt).clamp(0, total);
    cnt = s1 - s0;
    if (cnt <= 0) return;

    var lo = double.infinity;
    var hi = -double.infinity;
    var maxVol = 0.0;
    var hiIdx = 0;
    var loIdx = 0;
    for (var i = s0; i < s1; i++) {
      final c = candles[i];
      if (c['l']! < lo) {
        lo = c['l']!;
        loIdx = i;
      }
      if (c['h']! > hi) {
        hi = c['h']!;
        hiIdx = i;
      }
      if (c['v']! > maxVol) maxVol = c['v']!;
    }
    if (lastPrice > 0) {
      if (lastPrice < lo) lo = lastPrice;
      if (lastPrice > hi) hi = lastPrice;
    }
    final range = hi - lo;
    if (range <= 0) return;

    final chartW = size.width - _labelW;
    if (chartW <= 0) return;
    final chartH = size.height - _timeH;
    final topPad = _legendH; // 顶部预留图例区, 避免 MA 图例压住 K 线最高价
    final priceH = chartH * (1 - _volRatio) - 4 - topPad;
    final volH = chartH * _volRatio;
    final volTop = topPad + priceH + 4;

    final pad = range * 0.06;
    final min = lo - pad;
    final span = range + pad * 2;
    double yOf(double price) =>
        topPad + priceH - (price - min) / span * priceH;

    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.25)
      ..strokeWidth = 1;

    // 水平网格 + 右轴价标 (5 档).
    for (var i = 0; i <= 4; i++) {
      final y = topPad + priceH * i / 4;
      canvas.drawLine(Offset(0, y), Offset(chartW, y), gridPaint);
      final price = min + span * (1 - i / 4);
      _text(canvas, _axisPrice(price),
          Offset(chartW + 6, y - 5), labelColor, 10);
    }

    // 价格区与量区分隔线.
    canvas.drawLine(Offset(0, volTop), Offset(chartW, volTop), gridPaint);

    final step = chartW / cnt;
    final bodyW = (step * 0.62).clamp(1.0, step);
    double xOf(int i) => (i - s0) * step + step / 2;

    // 时间轴 (4 档).
    for (var i = 0; i < 4; i++) {
      final idx = s0 + (cnt - 1) * i ~/ 3;
      final x = xOf(idx);
      final label = _axisTime(candles[idx]['ts']!);
      final w = label.length * 5.4;
      var tx = x - w / 2;
      if (tx < 0) tx = 0;
      if (tx + w > chartW) tx = chartW - w;
      _text(canvas, label, Offset(tx, topPad + priceH + 6 + volH), labelColor, 9);
    }

    // 蜡烛 + 成交量.
    for (var i = s0; i < s1; i++) {
      final c = candles[i];
      final o = c['o']!;
      final h = c['h']!;
      final l = c['l']!;
      final cl = c['c']!;
      final up = cl >= o;
      final color = up ? bull : bear;
      final cx = xOf(i);

      canvas.drawLine(
          Offset(cx, yOf(h)),
          Offset(cx, yOf(l)),
          Paint()
            ..color = color
            ..strokeWidth = 1);
      final top = yOf(up ? cl : o);
      final bottom = yOf(up ? o : cl);
      canvas.drawRect(
        Rect.fromLTRB(cx - bodyW / 2, top, cx + bodyW / 2,
            (bottom - top).abs() < 1 ? top + 1 : bottom),
        Paint()..color = color,
      );

      if (maxVol > 0) {
        final vh = (c['v']! / maxVol) * volH;
        canvas.drawRect(
          Rect.fromLTRB(cx - bodyW / 2, volTop + volH - vh, cx + bodyW / 2,
              volTop + volH),
          Paint()..color = color.withValues(alpha: 0.35),
        );
      }
    }

    // MA 线 + 左上角图例 (带半透明底, 避免与 K 线/价标重叠).
    _maLine(canvas, 5, step, yOf, _ma5Color, s0, s1);
    _maLine(canvas, 10, step, yOf, _ma10Color, s0, s1);
    _maLine(canvas, 20, step, yOf, _ma20Color, s0, s1);
    final legend = <(String, Color)>[];
    for (final (n, color) in [(5, _ma5Color), (10, _ma10Color), (20, _ma20Color)]) {
      final v = _maAt(s1 - 1, n);
      legend.add((v == null ? 'MA$n' : 'MA$n ${_axisPrice(v)}', color));
    }
    const legendPadX = 6.0;
    const legendGap = 10.0;
    var legendW = legendPadX * 2;
    for (final (t, _) in legend) {
      legendW += _measure(t, 10) + legendGap;
    }
    legendW -= legendGap; // 末项后无 gap
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, legendW, 20),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0x660B0E14),
    );
    var lx = legendPadX;
    for (final (t, color) in legend) {
      _text(canvas, t, Offset(lx, 4), color, 10);
      lx += _measure(t, 10) + legendGap;
    }

    // 可见区最高/最低价指示 (OKX 风格: 极值点短横线 + 价格文本).
    final markColor = const Color(0xFFE8EAF0).withValues(alpha: 0.9);
    _hiLoMark(canvas, xOf(hiIdx), yOf(candles[hiIdx]['h']!),
        candles[hiIdx]['h']!, markColor, chartW);
    _hiLoMark(canvas, xOf(loIdx), yOf(candles[loIdx]['l']!),
        candles[loIdx]['l']!, markColor, chartW);

    // 最新价虚线 + 右轴标签.
    if (lastPrice > 0 && lastPrice >= min && lastPrice <= min + span) {
      final y = yOf(lastPrice);
      final lastClose = candles.last['c']!;
      final tagColor = lastPrice >= lastClose ? bull : bear;
      final dashPaint = Paint()
        ..color = tagColor.withValues(alpha: 0.7)
        ..strokeWidth = 1;
      var x = 0.0;
      while (x < chartW) {
        canvas.drawLine(Offset(x, y), Offset(x + 5, y), dashPaint);
        x += 9;
      }
      canvas.drawRect(
        Rect.fromLTWH(chartW, y - 8, _labelW, 16),
        Paint()..color = tagColor,
      );
      _text(canvas, _axisPrice(lastPrice), Offset(chartW + 4, y - 5),
          const Color(0xFF0B0E14), 10,
          bold: true);
    }
  }

  /// 极值标记: 从 (x,y) 向左右画 20px 短横线, 外侧跟价格文本 (x 过半屏向左).
  void _hiLoMark(Canvas canvas, double x, double y, double price, Color color,
      double chartW) {
    const lineSize = 20.0;
    const gap = 5.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final label = _axisPrice(price);
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: color, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    if (x < chartW / 2) {
      canvas.drawLine(Offset(x, y), Offset(x + lineSize, y), paint);
      tp.paint(canvas, Offset(x + lineSize + gap, y - tp.height / 2));
    } else {
      canvas.drawLine(Offset(x - lineSize, y), Offset(x, y), paint);
      tp.paint(canvas, Offset(x - lineSize - gap - tp.width, y - tp.height / 2));
    }
  }

  double? _maAt(int end, int n) {
    if (end < n - 1 || end < 0) return null;
    var sum = 0.0;
    for (var i = end - n + 1; i <= end; i++) {
      sum += candles[i]['c']!;
    }
    return sum / n;
  }

  void _maLine(Canvas canvas, int n, double step, double Function(double) yOf,
      Color color, int s0, int s1) {
    final path = Path();
    var started = false;
    final begin = s0 > n - 1 ? s0 : n - 1;
    for (var i = begin; i < s1; i++) {
      final v = _maAt(i, n)!;
      final x = (i - s0) * step + step / 2;
      if (!started) {
        path.moveTo(x, yOf(v));
        started = true;
      } else {
        path.lineTo(x, yOf(v));
      }
    }
    if (!started) return;
    canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.9)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke);
  }

  void _text(Canvas canvas, String s, Offset at, Color color, double size,
      {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  double _measure(String s, double size) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontSize: size, fontWeight: FontWeight.w400),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  String _axisPrice(double p) {
    if (p >= 1000) return p.toStringAsFixed(1);
    if (p >= 1) return p.toStringAsFixed(2);
    return p.toStringAsFixed(4);
  }

  String _axisTime(double tsMs) {
    final t = DateTime.fromMillisecondsSinceEpoch(tsMs.toInt());
    String two(int n) => n.toString().padLeft(2, '0');
    if (bar == '1D') return '${two(t.month)}-${two(t.day)}';
    return '${two(t.hour)}:${two(t.minute)}';
  }

  @override
  bool shouldRepaint(_CandlePainter old) =>
      old.candles != candles ||
      old.lastPrice != lastPrice ||
      old.bar != bar ||
      old.startIndex != startIndex ||
      old.viewCount != viewCount;
}

/// 全屏选币面板 (OKX 风格): 搜索 + 永续合约列表, 按 24H 成交额降序.
class _SymbolSwitcherSheet extends StatefulWidget {
  const _SymbolSwitcherSheet({required this.current, required this.onSelect});

  final String current;
  final ValueChanged<String> onSelect;

  @override
  State<_SymbolSwitcherSheet> createState() => _SymbolSwitcherSheetState();
}

class _SymbolSwitcherSheetState extends State<_SymbolSwitcherSheet> {
  List<OkxTicker>? _tickers;
  String _query = '';
  // 合约 SWAP / 现货 SPOT 分段.
  late String _type = widget.current.endsWith('-SWAP') ? 'SWAP' : 'SPOT';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      var list = await McData.tickers(instType: _type);
      // 现货接口含 EUR/USDC/BTC 等多种计价对, 同币多行价不同 — 只留 USDT 计价.
      if (_type == 'SPOT') {
        list = list.where((t) => t.instId.endsWith('-USDT')).toList();
      }
      list.sort((a, b) =>
          (b.last * b.volCcy24h).compareTo(a.last * a.volCcy24h));
      if (mounted) setState(() => _tickers = list);
    } catch (_) {
      if (mounted) setState(() => _tickers = const []);
    }
  }

  void _selectType(String type) {
    if (type == _type) return;
    setState(() {
      _type = type;
      _tickers = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toUpperCase();
    final all = _tickers;
    final list = all == null
        ? const <OkxTicker>[]
        : q.isEmpty
            ? all
            : all.where((t) => t.symbol.contains(q)).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: McColors.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: TextField(
              autofocus: false,
              onChanged: (v) => setState(() => _query = v),
              style: McText.sans(size: 14),
              decoration: InputDecoration(
                hintText: tr('mktd_search_coin'),
                hintStyle:
                    McText.sans(size: 14, color: McColors.onSurfaceVariant),
                prefixIcon: const Icon(Icons.search,
                    size: 18, color: McColors.onSurfaceVariant),
                filled: true,
                fillColor: McColors.surfaceContainerHigh,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // 合约 / 现货 分段切换.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                for (final (type, label) in [('SWAP', tr('mktd_contract')), ('SPOT', tr('mktd_spot'))])
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _selectType(type),
                      child: Container(
                        margin: EdgeInsets.only(
                            right: type == 'SWAP' ? 8 : 0),
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        decoration: BoxDecoration(
                          color: _type == type
                              ? McColors.primaryContainer
                              : McColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          label,
                          style: McText.sans(
                            size: 13,
                            weight: FontWeight.w600,
                            color: _type == type
                                ? McColors.onPrimaryContainer
                                : McColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (all == null)
            const Expanded(
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: McColors.primary),
                ),
              ),
            )
          else if (list.isEmpty)
            Expanded(
              child: Center(
                child: Text(tr('mktd_no_match'),
                    style: McText.sans(
                        size: 13, color: McColors.onSurfaceVariant)),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: list.length,
                itemBuilder: (context, i) => _row(list[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(OkxTicker t) {
    final isCurrent = t.instId == widget.current;
    final pct = t.changePct;
    final pctColor = pct >= 0 ? ColorPref.instance.bullColor : ColorPref.instance.bearColor;
    return InkWell(
      onTap: () => widget.onSelect(t.instId),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            CoinIcon(t.symbol, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Row(
                children: [
                  Text(t.symbol,
                      style: McText.sans(size: 14, weight: FontWeight.w700)),
                  Text('/USDT',
                      style: McText.sans(
                          size: 12, color: McColors.onSurfaceVariant)),
                  if (t.instId.endsWith('-SWAP')) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: McColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(tr('mktd_perp'),
                          style: McText.sans(
                              size: 10,
                              weight: FontWeight.w600,
                              color: McColors.primary)),
                    ),
                  ],
                  if (isCurrent) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.check_circle,
                        size: 14, color: McColors.primary),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  t.last > 0
                      ? '\$${t.last >= 1000 ? _MarketDetailPageState._comma(t.last) : t.last.toStringAsFixed(t.last < 10 ? 4 : 2)}'
                      : '--',
                  style: McText.mono(
                      size: 13,
                      weight: FontWeight.w600,
                      color: McColors.onSurface),
                ),
                Text(
                  '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
                  style:
                      McText.mono(size: 12, weight: FontWeight.w600, color: pctColor),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/kit.dart';
import '../widgets/shell.dart';
import 'deposit_page.dart';
import 'withdraw_page.dart';

/// 资产页: 双账户余额 + KPI 统计卡 + 产品卡网格 + 我的订单 + 资金明细。
/// 镜像 web-terminal/src/views/Assets.vue (申购邀请预检 / VIP 加成徽标已对齐)。
class AssetsPage extends StatefulWidget {
  const AssetsPage({super.key});
  @override
  State<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends State<AssetsPage> {
  final _acct = _Block<Map<String, dynamic>>();
  final _products = _Block<List<dynamic>>();
  final _orders = _Block<List<dynamic>>();
  final _logs = _Block<List<dynamic>>();
  final _summary = _Block<Map<String, dynamic>>();

  Map<String, dynamic>? _vip;
  String _productTab = 'all';
  String _orderTab = 'all';
  String _logTab = 'all';

  static const _logType = {
    'deposit_credited': '充值入账',
    'purchase': '申购扣款',
    'income_settled': '利息结算',
    'principal_returned': '本金返还',
    'commission': '返佣入账',
    'convert_out': '收益转出',
    'convert_in': '本金转入',
    'withdraw_request': '提现申请',
    'withdraw_approve': '提现通过',
    'withdraw_reject': '提现退回',
    'admin_adjust': '人工调整',
  };

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  void _loadAll() {
    _loadAccount();
    _loadProducts();
    _loadOrders();
    _loadLogs();
    _loadSummary();
    _loadVip();
  }

  Future<void> _loadAccount() async {
    setState(() => _acct.begin());
    try {
      final d = await ApiClient.I.depositAccount();
      _acct.data = d is Map ? Map<String, dynamic>.from(d) : {};
    } catch (e) {
      _acct.error = '余额加载失败';
    }
    if (mounted) setState(() => _acct.loading = false);
  }

  Future<void> _loadProducts() async {
    setState(() => _products.begin());
    try {
      _products.data = _asList(await ApiClient.I.products());
    } catch (e) {
      _products.error = '产品加载失败';
    }
    if (mounted) setState(() => _products.loading = false);
  }

  Future<void> _loadOrders() async {
    setState(() => _orders.begin());
    try {
      _orders.data = _asList(await ApiClient.I.orders());
    } catch (e) {
      _orders.error = '订单加载失败';
    }
    if (mounted) setState(() => _orders.loading = false);
  }

  Future<void> _loadLogs() async {
    setState(() => _logs.begin());
    try {
      final params = _logTab == 'all' ? null : {'account': _logTab};
      _logs.data = _asList(await ApiClient.I.accountLogs(params));
    } catch (e) {
      _logs.error = '明细加载失败';
    }
    if (mounted) setState(() => _logs.loading = false);
  }

  Future<void> _loadSummary() async {
    setState(() => _summary.begin());
    try {
      final d = await ApiClient.I.commissionsSummary();
      _summary.data = d is Map ? Map<String, dynamic>.from(d) : {};
    } catch (e) {
      _summary.error = '返佣统计加载失败';
    }
    if (mounted) setState(() => _summary.loading = false);
  }

  /// VIP 信息失败不阻塞页面 (与 Vue 版 allSettled 口径一致)。
  Future<void> _loadVip() async {
    try {
      final v = await ApiClient.I.vipMe();
      if (mounted) {
        setState(() =>
            _vip = v is Map ? Map<String, dynamic>.from(v) : null);
      }
    } catch (_) {}
  }

  static List<dynamic> _asList(dynamic d) {
    if (d is List) return d;
    if (d is Map && d['items'] is List) return d['items'] as List;
    return const [];
  }

  // ---------- 利率 / 收益计算 (与 Vue 版口径一致) ----------
  static double _ratePct(dynamic r) {
    final n = (Fmt.toNum(r) ?? 0).toDouble();
    return n > 1 ? n : n * 100;
  }

  static double _rateFrac(dynamic r) {
    final n = (Fmt.toNum(r) ?? 0).toDouble();
    return n > 1 ? n / 100 : n;
  }

  static String _annual(Map p) =>
      '${(_ratePct(p['base_daily_rate']) * 365).toStringAsFixed(2)}%';

  static String _dailyRate(Map o) =>
      '${_ratePct(o['actual_daily_rate'] ?? o['base_daily_rate']).toStringAsFixed(2)}%';

  static double _expected(Map o) =>
      (Fmt.toNum(o['amount']) ?? 0) *
      _rateFrac(o['actual_daily_rate'] ?? o['base_daily_rate']) *
      (Fmt.toNum(o['duration_days']) ?? 0);

  static bool _isActive(Map o) => o['status'] == 'effective';

  static String _time16(dynamic v) {
    final t = Fmt.parseServerTime(v);
    if (t == null) return '--';
    String p(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${p(t.month)}-${p(t.day)} ${p(t.hour)}:${p(t.minute)}';
  }

  static String _date(dynamic v) {
    final t = Fmt.parseServerTime(v);
    if (t == null) return '--';
    String p(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${p(t.month)}-${p(t.day)}';
  }

  // ---------- 过滤逻辑 (与 Vue 版一致) ----------
  List<Map> _orderList() =>
      (_orders.data ?? const []).whereType<Map>().toList();

  List<dynamic> _filteredProducts(List<dynamic> list) {
    num daysOf(dynamic p) =>
        Fmt.toNum(p is Map ? p['duration_days'] : null) ?? 0;
    if (_productTab == 'short') {
      return list.where((p) => daysOf(p) <= 7).toList();
    }
    if (_productTab == 'long') {
      return list.where((p) => daysOf(p) > 7).toList();
    }
    if (_productTab == 'vip') {
      return list
          .where((p) =>
              p is Map && (Fmt.toNum(p['vip_level_req']) ?? 0) > 0)
          .toList();
    }
    return list;
  }

  /// 收益账户卡右上角 VIP 等级 + 加成率徽标。
  Widget? _vipBadge() {
    final v = _vip;
    if (v == null) return null;
    final bonus = _ratePct(v['bonus_rate']);
    final lv = v['vip_level'] ?? 0;
    return McBadge(
      bonus > 0 ? 'VIP$lv · 加成 +${bonus.toStringAsFixed(2)}%' : 'VIP$lv',
      color: Mc.bull,
    );
  }

  // ---------- 弹窗入口 ----------
  void _openBuy(Map p) {
    final a = _acct.data ?? const {};
    showDialog(
      context: context,
      builder: (_) => _BuyDialog(
        product: p,
        principalBalance: a['principal_balance'],
        incomeBalance: a['income_balance'],
        onDone: _onBuyDone,
      ),
    );
  }

  void _onBuyDone() {
    _loadOrders();
    _loadAccount();
    _loadLogs();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Mc.surface,
      content: Text('申购成功, 订单已创建', style: Mc.body(13, color: Mc.bull)),
    ));
  }

  void _openConvert() {
    final a = _acct.data ?? const {};
    showDialog(
      context: context,
      builder: (_) => _ConvertDialog(
        incomeBalance: a['income_balance'],
        onDone: _onConvertDone,
      ),
    );
  }

  void _onConvertDone() {
    _loadAccount();
    _loadLogs();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Mc.surface,
      content: Text('收益已转为本金', style: Mc.body(13, color: Mc.bull)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        McSection('理财资产',
            tag: 'ASSET MANAGEMENT',
            trailing: Tooltip(
              message: '刷新全部',
              child: McButton('刷新',
                  kind: McBtnKind.ghost,
                  icon: Icons.refresh,
                  height: 34,
                  onPressed: _loadAll),
            )),
        const SizedBox(height: 16),
        _buildBalance(),
        const SizedBox(height: 16),
        _buildKpis(),
        const SizedBox(height: 24),
        McSection('理财产品',
            tag: 'WEALTH PRODUCTS', trailing: _buildProductTabs()),
        const SizedBox(height: 12),
        _buildProducts(),
        const SizedBox(height: 24),
        McSection('我的订单',
            tag: 'MY ORDERS', trailing: _buildOrderTabs()),
        const SizedBox(height: 12),
        _buildOrders(),
        const SizedBox(height: 24),
        McSection('资金明细',
            tag: 'ACCOUNT LOGS', trailing: _buildLogTabs()),
        const SizedBox(height: 12),
        _buildLogs(),
      ]),
    );
  }

  // ---------- 双账户余额 ----------
  Widget _buildBalance() {
    if (_acct.loading) {
      return const McCard(
          child: SizedBox(height: 120, child: McLoading(label: '余额加载中')));
    }
    if (_acct.error != null) {
      return McCard(
          child: SizedBox(
              height: 120,
              child: McError(_acct.error!, onRetry: _loadAccount)));
    }
    final a = _acct.data ?? const {};
    return McRow(children: [
      _BalanceCard(
          tag: '充值账户 PRINCIPAL',
          balance: a['principal_balance'],
          pending: a['principal_pending'],
          source: '链上充值 / 本金返还 / 收益转化',
          valueColor: Mc.ink,
          actions: [
            McButton('充值',
                kind: McBtnKind.ghost,
                icon: Icons.south,
                height: 32,
                onPressed: () =>
                    ShellRouter.I.push('充值', 'DEPOSIT', const DepositPage())),
            McButton('提现',
                kind: McBtnKind.ghost,
                icon: Icons.north,
                height: 32,
                onPressed: () => ShellRouter.I
                    .push('提现', 'WITHDRAW', const WithdrawPage())),
          ],
        ),
      _BalanceCard(
          tag: '理财账户 INCOME',
          balance: a['income_balance'],
          pending: a['income_pending'],
          source: '利息结算 / 邀请返佣',
          valueColor: Mc.up,
          badge: _vipBadge(),
          actions: [
            McButton('转本金',
                kind: McBtnKind.ghost,
                icon: Icons.currency_exchange,
                height: 32,
                onPressed: _openConvert),
          ],
        ),
    ]);
  }

  // ---------- KPI 统计卡 (累计返佣 / 预期收益 / 在投产品) ----------
  Widget _buildKpis() {
    final orders = _orderList();
    final active = orders.where(_isActive).toList();
    final principal = active.fold<double>(
        0, (s, o) => s + (Fmt.toNum(o['amount']) ?? 0));
    final profit =
        orders.fold<double>(0, (s, o) => s + _expected(o));
    final s = _summary.data ?? const {};
    final productCount = (_products.data ?? const []).length;
    return McRow(spans: const [4, 4, 4], children: [
      _KpiCard(
        tag: '累计返佣 COMMISSION',
        icon: Icons.payments_outlined,
        iconColor: Mc.muted,
        badge: const McBadge('USDT结算', color: Mc.muted),
        value: '\$${Fmt.num_(s['total'])}',
        subLabel: '今日返佣',
        subValue: '+\$${Fmt.num_(s['today'])}',
        subValueColor: Mc.up,
        footerLabel: '结算方式',
        footerValue: '每期自动结算',
        footerValueColor: Mc.up,
      ),
      _KpiCard(
        tag: '预期收益 EXPECTED PNL',
        icon: Icons.trending_up,
        iconColor: Mc.up,
        badge: const McBadge('理财订单', color: Mc.bull),
        value: '+\$${Fmt.num_(profit)}',
        valueColor: Mc.up,
        subLabel: '全部订单预期收益合计 (本金×日化×期限)',
        footerLabel: '订单总数',
        footerValue: '${orders.length} 笔',
      ),
      _KpiCard(
        tag: '在投产品 ACTIVE',
        icon: Icons.savings_outlined,
        iconColor: Mc.cobaltSoft,
        value: '${active.length}',
        valueSuffix: '笔计息中',
        valueColor: Mc.cobaltSoft,
        subLabel: '在投本金',
        subValue: '\$${Fmt.num_(principal)}',
        footerLabel: '可选产品',
        footerValue: '$productCount 款上架中',
        footerValueColor: Mc.amber,
      ),
    ]);
  }

  // ---------- 分类 / 过滤 tab ----------
  Widget _buildProductTabs() {
    final n = (_products.data ?? const []).length;
    return _SegTabs(
      options: [
        ('all', '全部 ($n)'),
        ('short', '短周期'),
        ('long', '中长期'),
        ('vip', 'VIP专享'),
      ],
      value: _productTab,
      onChanged: (k) => setState(() => _productTab = k),
    );
  }

  Widget _buildOrderTabs() {
    final all = _orderList();
    final activeN = all.where(_isActive).length;
    return _SegTabs(
      options: [
        ('all', '全部 (${all.length})'),
        ('active', '计息中 ($activeN)'),
        ('done', '已完成 (${all.length - activeN})'),
      ],
      value: _orderTab,
      onChanged: (k) => setState(() => _orderTab = k),
    );
  }

  Widget _buildLogTabs() {
    return _SegTabs(
      options: const [('all', '全部'), ('principal', '本金'), ('income', '收益')],
      value: _logTab,
      onChanged: (k) {
        setState(() => _logTab = k);
        _loadLogs();
      },
    );
  }

  // ---------- 理财产品卡网格 ----------
  Widget _buildProducts() {
    return _listBody(
      _products,
      empty: '暂无上架产品',
      retry: _loadProducts,
      builder: (list) {
        final items = _filteredProducts(list).whereType<Map>().toList();
        if (items.isEmpty) {
          return const SizedBox(
              height: 80, child: McEmpty('该分类下暂无产品'));
        }
        // 窄屏自动降列: 每张卡最小 320 宽, 1~3 列。
        return LayoutBuilder(builder: (context, c) {
          final cols = math.max(1, math.min(3, c.maxWidth ~/ 320));
          final rows = <Widget>[];
          for (var i = 0; i < items.length; i += cols) {
            final end = math.min(i + cols, items.length);
            rows.add(McRow(children: [
              for (final p in items.sublist(i, end))
                _ProductCard(product: p, onBuy: () => _openBuy(p)),
              for (var k = end - i; k < cols; k++) const SizedBox.shrink(),
            ]));
            if (end < items.length) rows.add(const SizedBox(height: 16));
          }
          return Column(children: rows);
        });
      },
    );
  }

  // ---------- 我的订单 ----------
  Widget _buildOrders() {
    return McCard(
      padding: EdgeInsets.zero,
      child: _listBody(
        _orders,
        empty: '暂无订单',
        retry: _loadOrders,
        builder: (list) {
          final shown = _orderTab == 'active'
              ? list.where((o) => o is Map && _isActive(o)).toList()
              : _orderTab == 'done'
                  ? list.where((o) => o is Map && !_isActive(o)).toList()
                  : list;
          if (shown.isEmpty) {
            return const SizedBox(
                height: 80, child: McEmpty('该状态下暂无订单'));
          }
          return Column(children: [
            _headRow(const [
              _Th('产品名称', flex: 3),
              _Th('本金', flex: 2, align: TextAlign.right),
              _Th('日化', flex: 2, align: TextAlign.right),
              _Th('预期收益', flex: 2, align: TextAlign.right),
              _Th('起息日', flex: 2, align: TextAlign.center),
              _Th('到期日', flex: 2, align: TextAlign.center),
              _Th('状态', flex: 2, align: TextAlign.center),
            ]),
            for (final o in shown)
              if (o is Map)
                _HoverRow(cells: [
                  _cell(
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(o['product_name']?.toString() ?? '#${o['product_id']}',
                            style: Mc.body(13, w: FontWeight.w600)),
                        Text('订单 #${o['id']}',
                            style: Mc.mono(10, color: Mc.muted)),
                      ]),
                      flex: 3),
                  _cell(Text('${Fmt.num_(o['amount'])} USDT',
                      textAlign: TextAlign.right, style: Mc.mono(12)), flex: 2),
                  _cell(Text(_dailyRate(o),
                      textAlign: TextAlign.right, style: Mc.mono(12)), flex: 2),
                  _cell(Text('+\$${Fmt.num_(_expected(o))}',
                      textAlign: TextAlign.right,
                      style: Mc.mono(12, w: FontWeight.w600, color: Mc.up)), flex: 2),
                  _cell(Text(_date(o['effective_at']),
                      textAlign: TextAlign.center,
                      style: Mc.mono(11, color: Mc.muted)), flex: 2),
                  _cell(Text(_date(o['expires_at']),
                      textAlign: TextAlign.center,
                      style: Mc.mono(11, color: Mc.muted)), flex: 2),
                  _cell(Center(child: _statusBadge(o['status']?.toString())), flex: 2),
                ]),
          ]);
        },
      ),
    );
  }

  Widget _statusBadge(String? s) {
    if (s == 'effective') return const McBadge('计息中', color: Mc.bull);
    if (s == 'settled' || s == 'expired' || s == 'finished') {
      return const McBadge('已完成', color: Mc.muted);
    }
    return McBadge(s ?? '--', color: Mc.amber);
  }

  // ---------- 资金明细 ----------
  Widget _buildLogs() {
    return McCard(
      padding: EdgeInsets.zero,
      child: _listBody(
        _logs,
        empty: '暂无资金明细',
        retry: _loadLogs,
        builder: (list) => Column(children: [
          _headRow(const [
            _Th('时间', flex: 3),
            _Th('账户', flex: 2),
            _Th('类型', flex: 2),
            _Th('金额', flex: 2, align: TextAlign.right),
            _Th('变动后余额', flex: 2, align: TextAlign.right),
          ]),
          for (final g in list)
            if (g is Map)
              _HoverRow(cells: [
                _cell(Text(_time16(g['created_at']),
                    style: Mc.mono(11, color: Mc.muted)), flex: 3),
                _cell(Text(_accountName(g['account']?.toString()),
                    style: Mc.body(12, color: Mc.muted)), flex: 2),
                _cell(Text(_logType[g['change_type']] ?? g['change_type']?.toString() ?? '--',
                    style: Mc.body(12)), flex: 2),
                _cell(Text(_signed(g['amount']),
                    textAlign: TextAlign.right,
                    style: Mc.mono(12,
                        w: FontWeight.w600,
                        color: (Fmt.toNum(g['amount']) ?? 0) >= 0 ? Mc.up : Mc.down)), flex: 2),
                _cell(Text('\$${Fmt.num_(g['balance_after'])}',
                    textAlign: TextAlign.right,
                    style: Mc.mono(12, color: Mc.muted)), flex: 2),
              ]),
        ]),
      ),
    );
  }

  static String _accountName(String? a) =>
      a == 'principal' ? '本金' : a == 'income' ? '收益' : (a ?? '--');

  static String _signed(dynamic v) {
    final n = Fmt.toNum(v);
    if (n == null) return '--';
    return '${n >= 0 ? '+' : ''}\$${Fmt.num_(n)}';
  }

  // ---------- 区块三态骨架 ----------
  Widget _listBody(
    _Block<List<dynamic>> b, {
    required String empty,
    required VoidCallback retry,
    required Widget Function(List<dynamic>) builder,
  }) {
    if (b.loading) {
      return const SizedBox(height: 140, child: McLoading());
    }
    if (b.error != null) {
      return SizedBox(height: 140, child: McError(b.error!, onRetry: retry));
    }
    final list = b.data ?? const [];
    if (list.isEmpty) {
      return SizedBox(height: 100, child: McEmpty(empty));
    }
    return builder(list);
  }

  Widget _headRow(List<_Th> ths) => Container(
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Mc.hairline))),
        child: Row(children: [
          for (final t in ths)
            Expanded(flex: t.flex, child: McTh(t.text, align: t.align)),
        ]),
      );

  Widget _cell(Widget child, {int flex = 1}) => Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: child,
        ),
      );
}

/// 表头描述。
class _Th {
  const _Th(this.text, {this.flex = 1, this.align = TextAlign.left});
  final String text;
  final int flex;
  final TextAlign align;
}

/// 区块加载状态。
class _Block<T> {
  bool loading = true;
  String? error;
  T? data;
  void begin() {
    loading = true;
    error = null;
  }
}

/// 计息方式文案映射 (与 Vue 版一致)。
const _kMethod = {
  'daily': '每日返息',
  'period_7d': '7天一返',
  'period_30d': '30天一返',
  'period_1h': '每小时返',
  'expiry': '到期还本付息',
  'maturity': '到期还本付息',
};

/// 分段过滤 tab: surface 底 + hairline 描边, 选中项 cardHigh 高亮。
class _SegTabs extends StatelessWidget {
  const _SegTabs({
    required this.options,
    required this.value,
    required this.onChanged,
  });
  final List<(String, String)> options;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Mc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Mc.hairline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final o in options) _seg(o.$1, o.$2),
      ]),
    );
  }

  Widget _seg(String key, String label) {
    final sel = key == value;
    return InkWell(
      onTap: () => onChanged(key),
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: sel ? Mc.cardHigh : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: Mc.mono(11,
                w: sel ? FontWeight.w600 : FontWeight.w500,
                color: sel ? Mc.ink : Mc.muted)),
      ),
    );
  }
}

/// KPI 统计卡: 图标 + mono 标签 + 右侧徽标 + 大数字 + 子行 + Hairline 页脚。
class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.tag,
    required this.icon,
    required this.iconColor,
    this.badge,
    required this.value,
    this.valueSuffix,
    this.valueColor = Mc.ink,
    required this.subLabel,
    this.subValue,
    this.subValueColor,
    required this.footerLabel,
    required this.footerValue,
    this.footerValueColor = Mc.ink,
  });
  final String tag;
  final IconData icon;
  final Color iconColor;
  final Widget? badge;
  final String value;
  final String? valueSuffix;
  final Color valueColor;
  final String subLabel;
  final String? subValue;
  final Color? subValueColor;
  final String footerLabel;
  final String footerValue;
  final Color footerValueColor;

  @override
  Widget build(BuildContext context) {
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 6),
          Expanded(child: McTag(tag)),
          ?badge,
        ]),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Mc.mono(26, w: FontWeight.w600, color: valueColor)),
            ),
            if (valueSuffix != null) ...[
              const SizedBox(width: 6),
              Text(valueSuffix!, style: Mc.body(12, color: Mc.muted)),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Row(children: [
          Flexible(
            child: Text(subLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Mc.body(11, color: Mc.muted)),
          ),
          if (subValue != null) ...[
            const SizedBox(width: 8),
            Text(subValue!,
                style: Mc.mono(11,
                    w: FontWeight.w600, color: subValueColor ?? Mc.ink)),
          ],
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.only(top: 10),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Mc.hairline))),
          child: Row(children: [
            Text(footerLabel, style: Mc.body(11, color: Mc.muted)),
            const Spacer(),
            Text(footerValue,
                style: Mc.mono(11,
                    w: FontWeight.w600, color: footerValueColor)),
          ]),
        ),
      ]),
    );
  }
}

/// 产品卡: 徽标行 + 名称 + APY 大数字区 + 明细行 + 立即申购。
class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onBuy});
  final Map product;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final method = _kMethod[p['return_method']] ?? '稳健增利';
    final methodDetail =
        _kMethod[p['return_method']] ?? p['return_method']?.toString() ?? '--';
    final isVip = (Fmt.toNum(p['vip_level_req']) ?? 0) > 0;
    final sub = (p['name_en'] ?? p['description'])?.toString() ?? '';
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          McBadge(method, color: Mc.cobaltSoft),
          McBadge('${p['duration_days'] ?? '--'}天定期', color: Mc.muted),
          if (isVip) const McBadge('VIP专享', color: Mc.amber),
        ]),
        const SizedBox(height: 10),
        Text(p['name']?.toString() ?? '#${p['id']}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Mc.display(15)),
        if (sub.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Mc.mono(10, color: Mc.muted)),
        ],
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Mc.canvas,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Mc.hairline),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const McTag('参考年化 (APY)'),
            const SizedBox(height: 6),
            Text(_AssetsPageState._annual(p),
                style: Mc.mono(26, w: FontWeight.w700, color: Mc.up)),
            const SizedBox(height: 6),
            Row(children: [
              Text('日化收益 ', style: Mc.mono(10, color: Mc.muted)),
              Text(
                  '${_AssetsPageState._ratePct(p['base_daily_rate']).toStringAsFixed(2)}%',
                  style: Mc.mono(10, w: FontWeight.w600)),
              const Spacer(),
              Text('USDT 标价', style: Mc.mono(10, color: Mc.muted)),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        _kvRow('投资期限', '${p['duration_days'] ?? '--'} 天 (锁定)'),
        _kvRow('起投门槛', '${Fmt.num_(p['min_amount'], dp: 0)} USDT'),
        _kvRow('单笔上限', '${Fmt.num_(p['max_amount'], dp: 0)} USDT'),
        _kvRow('计息方式', methodDetail),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: McButton('立即申购',
              icon: Icons.add_shopping_cart, height: 36, onPressed: onBuy),
        ),
      ]),
    );
  }
}

/// 产品卡明细行: 标签 + 值。
Widget _kvRow(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Text(label, style: Mc.body(11, color: Mc.muted)),
        const Spacer(),
        Text(value, style: Mc.mono(11)),
      ]),
    );

/// 弹窗骨架: 圆角 12 + Hairline 描边 McCard, 标题栏 + 关闭。
Widget _dialogShell(
    BuildContext context, String title, IconData icon, List<Widget> children) {
  return Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: McCard(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Icon(icon, size: 18, color: Mc.cobaltSoft),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: Mc.display(16))),
            InkWell(
              onTap: () => Navigator.of(context).pop(),
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 18, color: Mc.muted),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Container(
              decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Mc.hairline)))),
          const SizedBox(height: 14),
          ...children,
        ]),
      ),
    ),
  );
}

/// 弹窗内信息行: 标签 + 值。
Widget _infoRow(String label, Widget value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Text(label, style: Mc.body(12, color: Mc.muted)),
        const Spacer(),
        DefaultTextStyle(style: Mc.mono(12), child: value),
      ]),
    );

/// 弹窗内红字错误条。
Widget _errBar(String err) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Mc.bear.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Mc.bear.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline, size: 15, color: Mc.bear),
        const SizedBox(width: 6),
        Expanded(child: Text(err, style: Mc.body(12, color: Mc.bear))),
      ]),
    );

/// 弹窗内琥珀色警告条 (邀请关系预检提示)。
Widget _warnBar(String msg) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Mc.amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Mc.amber.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.warning_amber_rounded, size: 15, color: Mc.amber),
        const SizedBox(width: 6),
        Expanded(child: Text(msg, style: Mc.body(12, color: Mc.amber))),
      ]),
    );

/// 申购对话框: 产品信息 + 金额输入 + 预期收益试算 + 邀请关系预检 + createOrder。
class _BuyDialog extends StatefulWidget {
  const _BuyDialog({
    required this.product,
    required this.principalBalance,
    required this.incomeBalance,
    required this.onDone,
  });
  final Map product;
  final dynamic principalBalance;
  final dynamic incomeBalance;
  final VoidCallback onDone;

  @override
  State<_BuyDialog> createState() => _BuyDialogState();
}

class _BuyDialogState extends State<_BuyDialog> {
  final _ctrl = TextEditingController();
  late final String _idemKey =
      'buy-${DateTime.now().microsecondsSinceEpoch}';
  String _err = '';
  bool _submitting = false;
  bool _inviteChecked = false;
  bool _inviteWarn = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double get _amount => double.tryParse(_ctrl.text.trim()) ?? 0;

  double get _expectedIncome =>
      _amount *
      _AssetsPageState._rateFrac(widget.product['base_daily_rate']) *
      (Fmt.toNum(widget.product['duration_days']) ?? 0);

  String? _validate() {
    if (_ctrl.text.trim().isEmpty || _amount <= 0) return '请输入有效的申购金额';
    final min = Fmt.toNum(widget.product['min_amount']);
    final max = Fmt.toNum(widget.product['max_amount']);
    if (min != null && _amount < min) {
      return '单笔起投 ${Fmt.num_(min, dp: 0)} USDT';
    }
    if (max != null && max > 0 && _amount > max) {
      return '单笔上限 ${Fmt.num_(max, dp: 0)} USDT';
    }
    return null;
  }

  Future<void> _confirm() async {
    final v = _validate();
    if (v != null) {
      setState(() => _err = v);
      return;
    }
    // 提交前预检邀请关系 (接口失败不阻塞, 与 Vue 版一致)。
    if (!_inviteChecked) {
      _inviteChecked = true;
      try {
        final inv = await ApiClient.I.inviteMe();
        if (inv is Map) {
          final bound = inv['bound'] is bool
              ? inv['bound'] as bool
              : inv['inviter_id'] != null;
          final canBind = inv['canBind'] ?? inv['can_bind'];
          if (!bound && canBind == true) {
            if (mounted) setState(() => _inviteWarn = true);
            return; // 等用户确认"继续购买"
          }
        }
      } catch (_) {}
    }
    setState(() {
      _submitting = true;
      _err = '';
    });
    try {
      await ApiClient.I.createOrder({
        'product_id': widget.product['id'],
        'amount': _amount.toString(),
        'idempotency_key': _idemKey,
      });
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onDone();
    } catch (e) {
      if (mounted) {
        setState(() => _err =
            e is ApiException ? e.message : '申购失败, 请稍后重试');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final method =
        _kMethod[p['return_method']] ?? p['return_method']?.toString() ?? '--';
    return _dialogShell(context,
        '申购 ${p['name']?.toString() ?? '#${p['id']}'}', Icons.add_shopping_cart, [
      _infoRow('日化 / 年化', Text(
          '${_AssetsPageState._ratePct(p['base_daily_rate']).toStringAsFixed(2)}% / ${_AssetsPageState._annual(p)}',
          style: Mc.mono(12, w: FontWeight.w600, color: Mc.up))),
      _infoRow('期限 / 计息方式', Text('${p['duration_days'] ?? '--'} 天 · $method')),
      _infoRow('限额', Text(
          '${Fmt.num_(p['min_amount'], dp: 0)} ~ ${Fmt.num_(p['max_amount'], dp: 0)} USDT')),
      _infoRow('充值账户可用', Text('\$${Fmt.num_(widget.principalBalance)}')),
      _infoRow('理财账户可用', Text('\$${Fmt.num_(widget.incomeBalance)}',
          style: Mc.mono(12, color: Mc.up))),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: Text('申购金额 (USDT)', style: Mc.body(12, color: Mc.muted)),
      ),
      const SizedBox(height: 6),
      McInput(
        controller: _ctrl,
        hint: '起投 ${Fmt.num_(p['min_amount'], dp: 0)} USDT',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onSubmitted: (_) => _confirm(),
      ),
      const SizedBox(height: 10),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Mc.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Mc.hairline),
        ),
        child: Row(children: [
          Text('预期收益', style: Mc.body(12, color: Mc.muted)),
          const Spacer(),
          Text('+\$${Fmt.num_(_expectedIncome)}',
              style: Mc.mono(14, w: FontWeight.w600, color: Mc.up)),
        ]),
      ),
      if (_inviteWarn)
        _warnBar('未绑定邀请关系, 继续购买将失去补绑资格。点击"继续购买"表示确认。'),
      if (_err.isNotEmpty) _errBar(_err),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        McButton('取消',
            kind: McBtnKind.ghost,
            height: 36,
            onPressed: _submitting ? null : () => Navigator.of(context).pop()),
        const SizedBox(width: 10),
        McButton(
            _submitting ? '提交中' : _inviteWarn ? '继续购买' : '确认申购',
            height: 36, busy: _submitting, onPressed: _confirm),
      ]),
    ]);
  }
}

/// 收益转本金对话框: convertQuote 试算 (防抖) + convert 提交。
class _ConvertDialog extends StatefulWidget {
  const _ConvertDialog({required this.incomeBalance, required this.onDone});
  final dynamic incomeBalance;
  final VoidCallback onDone;

  @override
  State<_ConvertDialog> createState() => _ConvertDialogState();
}

class _ConvertDialogState extends State<_ConvertDialog> {
  final _ctrl = TextEditingController();
  late final String _idemKey =
      'cv-${DateTime.now().microsecondsSinceEpoch}';
  String _err = '';
  bool _submitting = false;
  bool _quoting = false;
  Map<String, dynamic>? _quote;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  double get _amount => double.tryParse(_ctrl.text.trim()) ?? 0;

  void _onAmountChanged() {
    _timer?.cancel();
    setState(() {
      _quote = null;
      _err = '';
    });
    if (_ctrl.text.trim().isEmpty || _amount <= 0) return;
    _timer = Timer(const Duration(milliseconds: 400), _fetchQuote);
  }

  Future<void> _fetchQuote() async {
    setState(() => _quoting = true);
    try {
      final q = await ApiClient.I.convertQuote({'amount': _ctrl.text.trim()});
      if (!mounted) return;
      setState(() =>
          _quote = q is Map ? Map<String, dynamic>.from(q) : null);
    } catch (e) {
      if (mounted) {
        setState(() =>
            _err = e is ApiException ? e.message : '报价失败');
      }
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  Future<void> _confirm() async {
    if (_ctrl.text.trim().isEmpty || _amount <= 0) {
      setState(() => _err = '请输入有效的转化金额');
      return;
    }
    if (_amount > (Fmt.toNum(widget.incomeBalance) ?? 0)) {
      setState(() => _err = '超出理财账户可用余额');
      return;
    }
    setState(() {
      _submitting = true;
      _err = '';
    });
    try {
      await ApiClient.I
          .convert({'amount': _ctrl.text.trim(), 'idempotency_key': _idemKey});
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onDone();
    } catch (e) {
      if (mounted) {
        setState(() => _err =
            e is ApiException ? e.message : '转化失败, 请稍后重试');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _quote;
    return _dialogShell(context, '收益转本金', Icons.currency_exchange, [
      _infoRow('理财账户可用', Text('\$${Fmt.num_(widget.incomeBalance)}',
          style: Mc.mono(12, w: FontWeight.w600, color: Mc.up))),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: Text('转化金额 (USDT)', style: Mc.body(12, color: Mc.muted)),
      ),
      const SizedBox(height: 6),
      McInput(
        controller: _ctrl,
        hint: '请输入转化金额',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onSubmitted: (_) => _confirm(),
      ),
      const SizedBox(height: 10),
      if (_quoting)
        Row(children: [
          const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Mc.cobaltSoft)),
          const SizedBox(width: 8),
          Text('报价计算中', style: Mc.body(12, color: Mc.muted)),
        ])
      else if (q != null)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Mc.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Mc.hairline),
          ),
          child: Column(children: [
            _infoRow(
                '服务费 (${_AssetsPageState._ratePct(q['rate']).toStringAsFixed(2)}%)',
                Text('-\$${Fmt.num_(q['service_fee'])}',
                    style: Mc.mono(12, color: Mc.down))),
            _infoRow('实际到账本金', Text('+\$${Fmt.num_(q['arrive_amount'])}',
                style: Mc.mono(12, w: FontWeight.w600, color: Mc.up))),
            _infoRow('单笔下限',
                Text('${Fmt.num_(q['min_amount'])} USDT')),
          ]),
        ),
      if (_err.isNotEmpty) _errBar(_err),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        McButton('取消',
            kind: McBtnKind.ghost,
            height: 36,
            onPressed: _submitting ? null : () => Navigator.of(context).pop()),
        const SizedBox(width: 10),
        McButton(_submitting ? '提交中' : '确认转化',
            height: 36, busy: _submitting, onPressed: _confirm),
      ]),
    ]);
  }
}

/// 双账户余额卡: McTag 标签 + 可选徽标 + 大数字 + 处理中 + 来源 + 操作按钮。
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.tag,
    required this.balance,
    required this.pending,
    required this.source,
    required this.valueColor,
    required this.actions,
    this.badge,
  });
  final String tag;
  final dynamic balance;
  final dynamic pending;
  final String source;
  final Color valueColor;
  final List<Widget> actions;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final pendingN = Fmt.toNum(pending) ?? 0;
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          McTag(tag),
          const Spacer(),
          ?badge,
        ]),
        const SizedBox(height: 10),
        Text('\$${Fmt.num_(balance)}',
            style: Mc.mono(26, w: FontWeight.w600, color: valueColor)),
        const SizedBox(height: 4),
        Row(children: [
          Text('提现处理中', style: Mc.body(11, color: Mc.muted)),
          const SizedBox(width: 8),
          Text('\$${Fmt.num_(pending)}',
              style: Mc.mono(11,
                  w: FontWeight.w600,
                  color: pendingN > 0 ? Mc.amber : Mc.muted)),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.only(top: 10),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Mc.hairline))),
          child: Row(children: [
            Expanded(
                child: Text(source,
                    style: Mc.body(11, color: Mc.muted),
                    overflow: TextOverflow.ellipsis)),
            for (final a in actions) ...[const SizedBox(width: 8), a],
          ]),
        ),
      ]),
    );
  }
}

/// 表格数据行: Hairline 底部分隔, 悬停 Mc.cardHigh (禁斑马纹)。
class _HoverRow extends StatefulWidget {
  const _HoverRow({required this.cells});
  final List<Widget> cells;
  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: _hover ? Mc.cardHigh : Colors.transparent,
            border:
                const Border(bottom: BorderSide(color: Mc.hairline, width: 0.6)),
          ),
          child: Row(children: widget.cells),
        ),
      );
}

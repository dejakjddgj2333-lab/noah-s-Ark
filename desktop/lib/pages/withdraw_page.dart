import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/kit.dart';

/// 提现页: 账户余额选择 + 网络选择 + 地址/金额表单 + 费用试算 + 提现记录。
/// 镜像 web-terminal/src/views/Withdraw.vue。
class WithdrawPage extends StatefulWidget {
  const WithdrawPage({super.key});
  @override
  State<WithdrawPage> createState() => _WithdrawPageState();
}

class _WithdrawPageState extends State<WithdrawPage> {
  static const _accounts = [
    ('principal', '本金账户', Icons.account_balance_wallet_outlined),
    ('income', '收益账户', Icons.trending_up),
  ];
  static final _amountRe = RegExp(r'^\d+(\.\d{1,2})?$');

  String _account = 'principal';
  Map<String, dynamic> _balances = const {};
  bool _balLoading = true;
  bool _balError = false;

  List<dynamic> _networks = const [];
  String _network = '';
  bool _netLoading = true;
  bool _netError = false;

  final _addrCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  Map<String, dynamic>? _quote;
  bool _quoteLoading = false;
  Timer? _quoteTimer;

  List<dynamic> _records = const [];
  bool _recLoading = true;
  bool _recError = false;

  bool _submitting = false;
  String _error = '';
  String _ok = '';
  bool _bootLoading = true;

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_onAmountChanged);
    _addrCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _quoteTimer?.cancel();
    _addrCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  // ---------- 金额校验 ----------
  bool get _amountOk =>
      _amountRe.hasMatch(_amountCtrl.text) &&
      (double.tryParse(_amountCtrl.text) ?? 0) > 0;

  String get _amountHint {
    final v = _amountCtrl.text;
    if (v.isEmpty) return '';
    if (!_amountRe.hasMatch(v)) return '金额最多两位小数';
    if ((double.tryParse(v) ?? 0) <= 0) return '金额需大于 0';
    return '';
  }

  bool get _canSubmit =>
      _amountOk && _addrCtrl.text.trim().isNotEmpty && _network.isNotEmpty;

  static String _accountLabel(String? k) =>
      k == 'principal' ? '本金账户' : k == 'income' ? '收益账户' : (k ?? '--');

  // ---------- 加载 ----------
  Future<void> _load() async {
    await Future.wait([_loadBalances(), _loadNetworks(), _loadRecords()]);
    if (mounted) setState(() => _bootLoading = false);
  }

  Future<void> _loadBalances() async {
    if (mounted) {
      setState(() {
        _balLoading = true;
        _balError = false;
      });
    }
    try {
      final d = await ApiClient.I.depositAccount();
      _balances = d is Map ? Map<String, dynamic>.from(d) : const {};
    } catch (_) {
      _balError = true;
    }
    if (mounted) setState(() => _balLoading = false);
  }

  Future<void> _loadNetworks() async {
    if (mounted) {
      setState(() {
        _netLoading = true;
        _netError = false;
      });
    }
    try {
      final d = await ApiClient.I.withdrawNetworks();
      _networks = d is Map && d['networks'] is List
          ? d['networks'] as List
          : const [];
      if (_network.isEmpty && _networks.isNotEmpty) {
        final first = _networks.first;
        if (first is Map) _network = first['network']?.toString() ?? '';
      }
    } catch (_) {
      _networks = const [];
      _netError = true;
    }
    if (mounted) setState(() => _netLoading = false);
  }

  Future<void> _loadRecords() async {
    if (mounted) {
      setState(() {
        _recLoading = true;
        _recError = false;
      });
    }
    try {
      final d = await ApiClient.I.withdrawalRecords();
      _records = d is List ? d : const [];
    } catch (_) {
      _recError = _records.isEmpty;
    }
    if (mounted) setState(() => _recLoading = false);
  }

  // ---------- 费用试算 (500ms 防抖) ----------
  void _onAmountChanged() {
    if (!mounted) return;
    setState(() {});
    _scheduleQuote();
  }

  void _scheduleQuote() {
    _quote = null;
    _quoteTimer?.cancel();
    if (!_amountOk || _network.isEmpty) {
      if (mounted) setState(() => _quoteLoading = false);
      return;
    }
    _quoteTimer = Timer(const Duration(milliseconds: 500), _fetchQuote);
  }

  Future<void> _fetchQuote() async {
    if (!_amountOk || _network.isEmpty) return;
    if (mounted) setState(() => _quoteLoading = true);
    try {
      final d = await ApiClient.I.withdrawQuote({
        'account': _account,
        'amount': _amountCtrl.text,
        'network': _network,
      });
      _quote = d is Map ? Map<String, dynamic>.from(d) : null;
    } catch (_) {
      _quote = null;
    }
    if (mounted) setState(() => _quoteLoading = false);
  }

  // ---------- 提交 ----------
  Future<void> _submit() async {
    setState(() {
      _error = '';
      _ok = '';
    });
    final address = _addrCtrl.text.trim();
    if (address.isEmpty) {
      setState(() => _error = '请输入提现地址');
      return;
    }
    if (!_amountOk) {
      setState(
          () => _error = _amountHint.isNotEmpty ? _amountHint : '请输入有效金额');
      return;
    }
    // 二次确认对话框
    final confirmed = await _confirmDialog(address);
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      // 提交前复核一次 quote, 防止费率变动
      final q = await ApiClient.I.withdrawQuote({
        'account': _account,
        'amount': _amountCtrl.text,
        'network': _network,
      });
      final qMap = q is Map ? Map<String, dynamic>.from(q) : null;
      if (qMap != null &&
          _quote != null &&
          Fmt.toNum(qMap['arrive_amount']) !=
              Fmt.toNum(_quote!['arrive_amount'])) {
        _quote = qMap;
        setState(() => _error = '费用已变动, 请确认后重新提交');
        return;
      }
      _quote = qMap ?? _quote;
      await ApiClient.I.withdraw({
        'account': _account,
        'network': _network,
        'address': address,
        'amount': _amountCtrl.text,
        'idempotency_key': _idemKey(),
      });
      _addrCtrl.clear();
      _amountCtrl.clear();
      _quote = null;
      if (mounted) setState(() => _ok = '提现申请已提交, 等待审核');
      _loadRecords();
      _loadBalances();
    } catch (e) {
      if (mounted) {
        setState(
            () => _error = e is ApiException ? e.message : '提现失败');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<bool?> _confirmDialog(String address) {
    final q = _quote;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Mc.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Mc.cardRadius),
          side: const BorderSide(color: Mc.hairline),
        ),
        title: Text('确认提现', style: Mc.display(16)),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _confirmRow('提现账户', _accountLabel(_account)),
            _confirmRow('网络', _network.toUpperCase()),
            _confirmRow('提现地址', address, mono: true),
            _confirmRow('提现金额', '${Fmt.num_(_amountCtrl.text)} USDT'),
            if (q != null) ...[
              const Divider(height: 20, color: Mc.hairline),
              _confirmRow('实际到账', '${Fmt.num_(q['arrive_amount'])} USDT',
                  valueColor: Mc.up),
            ],
            const SizedBox(height: 10),
            Text('提现由人工审核打款, 请确认地址无误, 提交后不可撤销。',
                style: Mc.body(11, color: Mc.muted)),
          ]),
        ),
        actions: [
          McButton('取消',
              kind: McBtnKind.ghost,
              height: 34,
              onPressed: () => Navigator.of(ctx).pop(false)),
          McButton('确认提现',
              height: 34, onPressed: () => Navigator.of(ctx).pop(true)),
        ],
      ),
    );
  }

  Widget _confirmRow(String label, String value,
          {bool mono = false, Color? valueColor}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 72,
              child: Text(label, style: Mc.body(12, color: Mc.muted))),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style: mono
                    ? Mc.mono(11, color: valueColor ?? Mc.ink)
                    : Mc.mono(12,
                        w: FontWeight.w600, color: valueColor ?? Mc.ink)),
          ),
        ]),
      );

  static String _idemKey() {
    final r = Random();
    String hex(int n) =>
        List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${hex(8)}-${hex(4)}-${hex(4)}-${hex(4)}-${hex(12)}';
  }

  // ---------- 工具 ----------
  static String _time16(dynamic v) {
    final t = Fmt.parseServerTime(v);
    if (t == null) return '--';
    String p(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${p(t.month)}-${p(t.day)} ${p(t.hour)}:${p(t.minute)}';
  }

  static String _cut(dynamic v) {
    if (v == null) return '--';
    final s = v.toString();
    if (s.isEmpty) return '--';
    if (s.length <= 16) return s;
    return '${s.substring(0, 8)}…${s.substring(s.length - 6)}';
  }

  static Widget _statusBadge(String? s) {
    switch (s) {
      case 'pending':
        return const McBadge('审核中', color: Mc.amber);
      case 'approved':
        return const McBadge('已打款', color: Mc.bull);
      case 'rejected':
        return const McBadge('已拒绝', color: Mc.bear);
      default:
        return McBadge(s?.isNotEmpty == true ? s! : '--', color: Mc.muted);
    }
  }

  // ---------- 布局 ----------
  @override
  Widget build(BuildContext context) {
    if (_bootLoading) return const McLoading(label: '数据加载中');
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildAccounts(),
            const SizedBox(height: 20),
            _buildForm(),
            const SizedBox(height: 20),
            _buildRecordsCard(),
          ]),
        ),
      ),
    );
  }

  // ---------- 账户选择 ----------
  Widget _buildAccounts() {
    if (_balLoading) {
      return const McCard(
          child: SizedBox(height: 110, child: McLoading(label: '余额加载中')));
    }
    if (_balError) {
      return McCard(
          child: SizedBox(
              height: 110,
              child: McError('余额加载失败', onRetry: _loadBalances)));
    }
    return McRow(children: [
      for (final a in _accounts) _acctCard(a.$1, a.$2, a.$3),
    ]);
  }

  Widget _acctCard(String key, String label, IconData icon) {
    final sel = _account == key;
    final bal = _balances['${key}_balance'];
    final pend = Fmt.toNum(_balances['${key}_pending']) ?? 0;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          if (_account == key) return;
          setState(() => _account = key);
          _scheduleQuote();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(Mc.cardPadding),
          decoration: BoxDecoration(
            color: Mc.card,
            borderRadius: BorderRadius.circular(Mc.cardRadius),
            border: Border.all(
                color: sel ? Mc.cobalt : Mc.hairline, width: sel ? 1.2 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon,
                  size: 16, color: sel ? Mc.cobaltSoft : Mc.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text('$label ${key.toUpperCase()}',
                    style: Mc.tag(color: sel ? Mc.cobaltSoft : Mc.muted)),
              ),
              if (sel) const McBadge('已选择', color: Mc.cobaltSoft),
            ]),
            const SizedBox(height: 12),
            Text('\$${Fmt.num_(bal)}',
                style: Mc.mono(24, w: FontWeight.w700)),
            const SizedBox(height: 4),
            Row(children: [
              Text('提现冻结中', style: Mc.body(11, color: Mc.muted)),
              const SizedBox(width: 8),
              Text('\$${Fmt.num_(pend)}',
                  style: Mc.mono(11,
                      w: FontWeight.w600,
                      color: pend > 0 ? Mc.amber : Mc.muted)),
            ]),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.only(top: 8),
              decoration: const BoxDecoration(
                  border: Border(
                      top: BorderSide(color: Mc.hairline, width: 0.6))),
              child: Row(children: [
                Text('提现来源', style: Mc.body(11, color: Mc.muted)),
                const Spacer(),
                Text(label, style: Mc.body(11, w: FontWeight.w600)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  // ---------- 提现表单 ----------
  Widget _buildForm() {
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('提现', style: Mc.display(16)),
          const SizedBox(width: 10),
          McTag('WITHDRAW · USDT 人工审核打款'),
        ]),
        const SizedBox(height: 16),
        const McTag('提现网络'),
        const SizedBox(height: 8),
        _buildNetworks(),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const McTag('提现地址'),
              const SizedBox(height: 6),
              McInput(
                controller: _addrCtrl,
                hint: '收款地址',
                prefix: Icons.wallet,
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const McTag('提现金额 (USDT)'),
              const SizedBox(height: 6),
              McInput(
                controller: _amountCtrl,
                hint: '0.00',
                prefix: Icons.payments_outlined,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
              ),
              if (_amountHint.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(_amountHint, style: Mc.mono(10, color: Mc.bear)),
              ],
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        _buildQuote(),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 10),
          _msgRow(Icons.error_outline, _error, Mc.bear),
        ] else if (_ok.isNotEmpty) ...[
          const SizedBox(height: 10),
          _msgRow(Icons.check_circle_outline, _ok, Mc.bull),
        ],
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: McButton(_submitting ? '提交中' : '确认提现',
              busy: _submitting,
              height: 44,
              onPressed: _canSubmit ? _submit : null),
        ),
      ]),
    );
  }

  Widget _buildNetworks() {
    if (_netLoading) {
      return const SizedBox(
          height: 64, child: McLoading(label: '网络加载中'));
    }
    if (_netError || _networks.isEmpty) {
      return SizedBox(
        height: 48,
        child: _netError
            ? McError('网络列表加载失败', onRetry: _loadNetworks)
            : const McEmpty('暂无可提现网络'),
      );
    }
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 640 ? 4 : 2;
      const gap = 16.0;
      final tiles = [
        for (final n in _networks)
          if (n is Map) _netTile(Map<String, dynamic>.from(n)),
      ];
      final span = 12 ~/ cols;
      final rows = <Widget>[];
      for (var i = 0; i < tiles.length; i += cols) {
        final end = i + cols > tiles.length ? tiles.length : i + cols;
        rows.add(McRow(
          gap: gap,
          spans: List.filled(cols, span),
          children: [
            ...tiles.sublist(i, end),
            // 不足一行补空位, 保持与上方行栅格对齐
            for (var k = end - i; k < cols; k++) const SizedBox(),
          ],
        ));
      }
      return Column(children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: gap),
          rows[i],
        ],
      ]);
    });
  }

  Widget _netTile(Map<String, dynamic> n) {
    final key = n['network']?.toString() ?? '';
    final sel = _network == key;
    final rate = Fmt.toNum(n['income_service_rate']);
    return InkWell(
      onTap: () {
        if (_network == key) return;
        setState(() => _network = key);
        _scheduleQuote();
      },
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: sel ? Mc.cobalt.withValues(alpha: 0.10) : Mc.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: sel ? Mc.cobalt : Mc.hairline, width: sel ? 1.2 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((n['label']?.toString().isNotEmpty == true)
              ? n['label'].toString()
              : key.toUpperCase(),
              style: Mc.mono(12,
                  w: FontWeight.w600,
                  color: sel ? Mc.cobaltSoft : Mc.ink)),
          const SizedBox(height: 3),
          Text('网络费 ${Fmt.num_(n['network_fee'])} USDT',
              style: Mc.mono(10, color: Mc.muted)),
          if (rate != null && _account == 'income')
            Text('服务费率 ${(rate * 100).toStringAsFixed(2)}%',
                style: Mc.mono(10, color: Mc.muted)),
        ]),
      ),
    );
  }

  Widget _buildQuote() {
    if (_quoteLoading) {
      return Text('费用试算中…', style: Mc.mono(11, color: Mc.muted));
    }
    final q = _quote;
    if (q == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Mc.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Mc.hairline),
      ),
      child: Column(children: [
        _quoteRow('服务费', '${Fmt.num_(q['service_fee'])} USDT'),
        const SizedBox(height: 6),
        _quoteRow('网络费', '${Fmt.num_(q['network_fee'])} USDT'),
        const SizedBox(height: 6),
        _quoteRow('总扣减', '-${Fmt.num_(q['total_deduction'])} USDT',
            valueColor: Mc.down),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          height: 0.6,
          color: Mc.hairline,
        ),
        _quoteRow('实际到账', '${Fmt.num_(q['arrive_amount'])} USDT',
            valueColor: Mc.up, strong: true),
      ]),
    );
  }

  Widget _quoteRow(String label, String value,
          {Color? valueColor, bool strong = false}) =>
      Row(children: [
        Text(label, style: Mc.body(12, color: Mc.muted)),
        const Spacer(),
        Text(value,
            textAlign: TextAlign.right,
            style: Mc.mono(strong ? 13 : 12,
                w: strong ? FontWeight.w700 : FontWeight.w500,
                color: valueColor ?? Mc.ink)),
      ]);

  Widget _msgRow(IconData icon, String text, Color color) => Row(children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Flexible(child: Text(text, style: Mc.mono(11, color: color))),
      ]);

  // ---------- 提现记录 ----------
  Widget _buildRecordsCard() {
    return McCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 12, 12),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Mc.hairline))),
          child: Row(children: [
            const Expanded(
                child: McSection('提现记录', tag: 'WITHDRAWAL HISTORY')),
            McButton('刷新',
                kind: McBtnKind.ghost,
                icon: Icons.refresh,
                height: 30,
                onPressed: _loadRecords),
          ]),
        ),
        _recordsBody(),
      ]),
    );
  }

  Widget _recordsBody() {
    if (_recLoading) {
      return const SizedBox(height: 140, child: McLoading());
    }
    if (_recError) {
      return SizedBox(
          height: 140,
          child: McError('提现记录加载失败', onRetry: _loadRecords));
    }
    if (_records.isEmpty) {
      return const SizedBox(height: 100, child: McEmpty('暂无提现记录'));
    }
    return Column(children: [
      _headRow(const [
        _Th('时间', flex: 3),
        _Th('账户', flex: 2, align: TextAlign.center),
        _Th('网络', flex: 2, align: TextAlign.center),
        _Th('金额', flex: 3, align: TextAlign.right),
        _Th('实际到账', flex: 3, align: TextAlign.right),
        _Th('状态', flex: 2, align: TextAlign.center),
        _Th('交易哈希', flex: 3, align: TextAlign.right),
      ]),
      for (final r in _records)
        if (r is Map) _recordRow(Map<String, dynamic>.from(r)),
    ]);
  }

  Widget _recordRow(Map<String, dynamic> r) {
    final net = r['network']?.toString() ?? '';
    final txid = r['txid']?.toString() ?? '';
    return _HoverRow(cells: [
      _cell(
          Text(_time16(r['created_at'] ?? r['requested_at']),
              style: Mc.mono(11, color: Mc.muted)),
          flex: 3),
      _cell(
          Text(_accountLabel(r['account']?.toString()),
              textAlign: TextAlign.center,
              style: Mc.body(11, color: Mc.muted)),
          flex: 2),
      _cell(Center(child: McBadge(net.toUpperCase())), flex: 2),
      _cell(
          Text('${Fmt.num_(r['amount'])} USDT',
              textAlign: TextAlign.right,
              style: Mc.mono(12, w: FontWeight.w600)),
          flex: 3),
      _cell(
          Text('${Fmt.num_(r['arrive_amount'])} USDT',
              textAlign: TextAlign.right,
              style: Mc.mono(12, w: FontWeight.w600, color: Mc.up)),
          flex: 3),
      _cell(Center(child: _statusBadge(r['status']?.toString())), flex: 2),
      _cell(
          Tooltip(
            message: txid,
            child: Text(_cut(txid),
                textAlign: TextAlign.right,
                style: Mc.mono(11, color: Mc.muted)),
          ),
          flex: 3),
    ]);
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

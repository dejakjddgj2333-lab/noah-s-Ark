import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../services/api.dart';
import '../services/finance_api.dart';

/// 资金页 (V0.7 Phase 7.7): 双账户余额/处理中 + 资金明细 / 收益结算 / 佣金 / 提现记录 / 等级变动.
class FundsPage extends StatefulWidget {
  const FundsPage({super.key});

  @override
  State<FundsPage> createState() => _FundsPageState();
}

class _FundsPageState extends State<FundsPage> with SingleTickerProviderStateMixin {
  late final TabController _tab;

  Map<String, dynamic>? _account;
  List<dynamic> _logs = [];
  List<dynamic> _settlements = [];
  List<dynamic> _commissions = [];
  List<dynamic> _withdrawals = [];
  List<dynamic> _levelLogs = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        FinanceApi.account(),
        FinanceApi.balanceLogs(),
        FinanceApi.settlements(),
        FinanceApi.commissions(),
        FinanceApi.withdrawals(),
        FinanceApi.levelLogs(),
      ]);
      if (!mounted) return;
      setState(() {
        _account = results[0] as Map<String, dynamic>;
        _logs = results[1] as List<dynamic>;
        _settlements = results[2] as List<dynamic>;
        _commissions = results[3] as List<dynamic>;
        _withdrawals = results[4] as List<dynamic>;
        _levelLogs = results[5] as List<dynamic>;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = tr('net_error_retry'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: McColors.surface,
      appBar: AppBar(
        backgroundColor: McColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: McColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(tr('funds_title'), style: McText.display(size: 16, weight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: McColors.primarySoft,
          labelColor: McColors.primarySoft,
          unselectedLabelColor: McColors.onSurfaceVariant,
          labelStyle: McText.sans(size: 12, weight: FontWeight.w600),
          tabs: [
            Tab(text: tr('funds_tab_detail')),
            Tab(text: tr('funds_tab_settle')),
            Tab(text: tr('funds_tab_commission')),
            Tab(text: tr('funds_tab_withdraw')),
            Tab(text: tr('funds_tab_level')),
          ],
        ),
      ),
      body: Column(
        children: [
          _accountHeader(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: _errorBox(_error!),
            ),
          Expanded(
            child: _busy && _logs.isEmpty
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : TabBarView(
                    controller: _tab,
                    children: [
                      _logList(),
                      _settlementList(),
                      _commissionList(),
                      _withdrawalList(),
                      _levelLogList(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _accountHeader() {
    final pBal = FinanceApi.d(_account?['principal_balance']);
    final iBal = FinanceApi.d(_account?['income_balance']);
    final pPend = FinanceApi.d(_account?['principal_pending']);
    final iPend = FinanceApi.d(_account?['income_pending']);
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: McColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: McColors.surfaceContainerHigh),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('funds_principal'), style: McText.sans(size: 11, color: McColors.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(pBal.toStringAsFixed(2), style: McText.mono(size: 18, weight: FontWeight.w700)),
                if (pPend > 0)
                  Text(tr('funds_pending').replaceAll('{n}', '$pPend'), style: McText.sans(size: 10, color: McColors.goldBright)),
              ],
            ),
          ),
          Container(width: 1, height: 36, color: McColors.outlineVariant),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('funds_income'), style: McText.sans(size: 11, color: McColors.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(iBal.toStringAsFixed(2),
                    style: McText.mono(size: 18, weight: FontWeight.w700, color: McColors.tertiary)),
                if (iPend > 0)
                  Text(tr('funds_pending').replaceAll('{n}', '$iPend'), style: McText.sans(size: 10, color: McColors.goldBright)),
                const SizedBox(height: 2),
                // 收益→本金转化入口 (收服务费, 报价确认后执行)
                GestureDetector(
                  onTap: () => _openConvert(iBal),
                  child: Text('转本金 →',
                      style: McText.sans(size: 11, color: McColors.goldBright, weight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18, color: McColors.onSurfaceVariant),
            onPressed: _busy ? null : _load,
          ),
        ],
      ),
    );
  }

  // ── 收益→本金转化 (报价确认后执行, 收服务费) ──
  Future<void> _openConvert(double incomeBal) async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: McColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ConvertSheet(incomeBal: incomeBal),
    );
    if (done == true) _load();
  }

  // ── 资金明细 ──
  Widget _logList() {
    if (_logs.isEmpty) return _empty(tr('funds_empty_detail'));
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      itemCount: _logs.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: McColors.outlineVariant),
      itemBuilder: (_, i) {
        final l = _logs[i];
        final amt = FinanceApi.d(l['amount']);
        final isPrincipal = l['account'] == 'principal';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(FinLabels.changeType(l['change_type']),
                        style: McText.sans(size: 13, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      '${isPrincipal ? tr('funds_principal_short') : tr('funds_income_short')} · ${tr('funds_balance')} ${l['balance_after']} · ${FinanceApi.time(l['created_at'])}',
                      style: McText.sans(size: 11, color: McColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Text(
                '${amt >= 0 ? '+' : ''}${amt.toStringAsFixed(2)}',
                style: McText.mono(
                  size: 14,
                  weight: FontWeight.w700,
                  color: amt >= 0 ? McColors.bull : McColors.bear,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── 收益结算 ──
  Widget _settlementList() {
    if (_settlements.isEmpty) return _empty(tr('funds_empty_settle'));
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      itemCount: _settlements.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: McColors.outlineVariant),
      itemBuilder: (_, i) {
        final s = _settlements[i];
        final principal = FinanceApi.d(s['principal_amount']);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('funds_order_period').replaceAll('{order}', '${s['order_id']}').replaceAll('{period}', '${s['period_no']}'),
                        style: McText.sans(size: 13, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(FinanceApi.time(s['created_at']),
                        style: McText.sans(size: 11, color: McColors.onSurfaceVariant)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('+${FinanceApi.d(s['income_amount']).toStringAsFixed(2)}',
                      style: McText.mono(size: 14, weight: FontWeight.w700, color: McColors.bull)),
                  if (principal > 0)
                    Text(tr('funds_principal_return').replaceAll('{n}', principal.toStringAsFixed(2)),
                        style: McText.mono(size: 11, color: McColors.goldBright)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ── 佣金 ──
  Widget _commissionList() {
    if (_commissions.isEmpty) return _empty(tr('funds_empty_commission'));
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      itemCount: _commissions.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: McColors.outlineVariant),
      itemBuilder: (_, i) {
        final c = _commissions[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('funds_gen_order').replaceAll('{gen}', '${c['gen']}').replaceAll('{order}', '${c['order_id']}'),
                        style: McText.sans(size: 13, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      tr('funds_commission_meta')
                          .replaceAll('{base}', '${FinanceApi.d(c['base_amount'])}')
                          .replaceAll('{rate}', FinanceApi.pct(c['rate']))
                          .replaceAll('{level}', '${c['receiver_team_level']}')
                          .replaceAll('{time}', FinanceApi.time(c['created_at'])),
                      style: McText.sans(size: 11, color: McColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Text('+${FinanceApi.d(c['amount']).toStringAsFixed(2)}',
                  style: McText.mono(size: 14, weight: FontWeight.w700, color: McColors.goldBright)),
            ],
          ),
        );
      },
    );
  }

  // ── 提现记录 ──
  Widget _withdrawalList() {
    if (_withdrawals.isEmpty) return _empty(tr('funds_empty_withdraw'));
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      itemCount: _withdrawals.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: McColors.outlineVariant),
      itemBuilder: (_, i) {
        final w = _withdrawals[i];
        final status = w['status']?.toString() ?? '';
        final color = status == 'approved'
            ? McColors.bull
            : status == 'rejected'
                ? McColors.bear
                : McColors.goldBright;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${w['account'] == 'income' ? tr('funds_income_short') : tr('funds_principal_short')} · ${w['amount']} USDT → ${w['arrive_amount']}',
                      style: McText.sans(size: 13, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${tr('funds_fee_line').replaceAll('{service}', '${w['service_fee']}').replaceAll('{network_fee}', '${w['network_fee']}')} · ${FinanceApi.time(w['created_at'])}'
                      '${w['txid'] != null ? ' · txid ${w['txid']}' : ''}'
                      '${w['remark'] != null ? ' · ${w['remark']}' : ''}',
                      style: McText.sans(size: 11, color: McColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Text(
                FinLabels.withdrawStatus[status] ?? status,
                style: McText.sans(size: 12, weight: FontWeight.w600, color: color),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── 等级变动 ──
  Widget _levelLogList() {
    if (_levelLogs.isEmpty) return _empty(tr('funds_empty_level'));
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      itemCount: _levelLogs.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: McColors.outlineVariant),
      itemBuilder: (_, i) {
        final l = _levelLogs[i];
        final isVip = l['kind'] == 'vip';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (isVip ? McColors.primaryContainer : McColors.tertiary)
                      .withValues(alpha: 0.15),
                ),
                child: Center(
                  child: Text(
                    '${l['level']}',
                    style: McText.display(
                      size: 14,
                      weight: FontWeight.w700,
                      color: isVip ? McColors.primarySoft : McColors.tertiary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isVip ? tr('funds_vip_level') : tr('funds_team_level'),
                        style: McText.sans(size: 13, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      '${l['source'] == 'purchase' ? tr('funds_src_purchase') : tr('funds_src_settle')}'
                      '${l['holding'] != null ? ' · ${tr('funds_holding')} ${l['holding']}' : ''}'
                      '${l['member_count'] != null ? ' · ${l['member_count']} ${tr('funds_people')}' : ''}'
                      ' · ${FinanceApi.time(l['created_at'])}',
                      style: McText.sans(size: 11, color: McColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _empty(String text) {
    return Center(child: Text(text, style: McText.sans(color: McColors.onSurfaceVariant)));
  }

  Widget _errorBox(String msg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: McColors.bear.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: McColors.bear.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: McColors.bear),
          const SizedBox(width: 8),
          Expanded(child: Text(msg, style: McText.sans(size: 12, color: McColors.bear))),
        ],
      ),
    );
  }
}

/// 收益→本金转化弹层: 输入金额 → 报价确认 → 执行 (服务端重算, 费用确认后不追加).
class _ConvertSheet extends StatefulWidget {
  const _ConvertSheet({required this.incomeBal});
  final double incomeBal;

  @override
  State<_ConvertSheet> createState() => _ConvertSheetState();
}

class _ConvertSheetState extends State<_ConvertSheet> {
  final _amountCtrl = TextEditingController();
  // 幂等键: 弹层打开即生成, 网络超时重试/重复点击服务端只扣一次
  final _idemKey = const Uuid().v4();
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _quote;

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(() {
      if (_error != null || _quote != null) {
        setState(() { _error = null; _quote = null; });
      }
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadQuote() async {
    final amount = _amountCtrl.text.trim();
    if (amount.isEmpty || (double.tryParse(amount) ?? 0) <= 0) {
      setState(() => _error = '请输入有效金额');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final q = await FinanceApi.convertQuote(amount);
      if (mounted) setState(() => _quote = q);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '网络错误, 请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    try {
      final q = await FinanceApi.convert(_amountCtrl.text.trim(),
          idempotencyKey: _idemKey);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          '转化成功: 服务费 ${q['service_fee']}, 到账本金 ${q['arrive_amount']}',
          style: McText.sans(size: 13),
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: McColors.surfaceContainerHighest,
      ));
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _quote = null; });
    } catch (_) {
      if (mounted) setState(() { _error = '网络错误, 请稍后重试'; _quote = null; });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _quote;
    return Padding(
      padding: EdgeInsets.only(
        left: 18, right: 18, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('收益转本金', style: McText.display(size: 17, weight: FontWeight.w700)),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20, color: McColors.onSurfaceVariant),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          Text(
            '收益余额 ${widget.incomeBal.toStringAsFixed(2)} USDT',
            style: McText.sans(size: 12, color: McColors.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Text('转化金额 (USDT)', style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
          const SizedBox(height: 6),
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: McText.mono(size: 16),
            decoration: InputDecoration(
              hintText: '最低 50',
              hintStyle: McText.mono(size: 14, color: McColors.onSurfaceVariant),
              filled: true,
              fillColor: McColors.surfaceContainerHigh.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              suffixText: 'USDT',
              suffixStyle: McText.sans(size: 12, color: McColors.onSurfaceVariant),
              errorText: _error,
              errorStyle: McText.sans(size: 12, color: McColors.bear),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: McColors.bear),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: McColors.bear),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '转化收取服务费 (默认 3%), 从转化金额内扣除; 内部转化不走链, 不收网络费。',
            style: McText.sans(size: 11, color: McColors.onSurfaceVariant, height: 1.5),
          ),
          if (q != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: McColors.surfaceContainerHigh.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _quoteRow('转化金额', '${q['amount']}'),
                  _quoteRow('服务费 (${(FinanceApi.d(q['rate']) * 100).toStringAsFixed(0)}%)', '${q['service_fee']}'),
                  const Divider(height: 12, color: McColors.outlineVariant),
                  _quoteRow('实际到账本金', '${q['arrive_amount']}', strong: true),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: McColors.primaryContainer,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _busy ? null : (q == null ? _loadQuote : _submit),
              child: _busy
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: McColors.onPrimaryContainer),
                    )
                  : Text(q == null ? '获取报价' : '确认转化',
                      style: McText.display(size: 14, weight: FontWeight.w700, color: McColors.onPrimaryContainer)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quoteRow(String label, String value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
          Text(value, style: McText.mono(size: strong ? 15 : 13,
              weight: strong ? FontWeight.w700 : FontWeight.w500,
              color: strong ? McColors.goldBright : McColors.onSurface)),
        ],
      ),
    );
  }
}

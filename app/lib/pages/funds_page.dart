import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../services/api.dart';
import '../services/finance_api.dart';
import '../widgets/convert_sheet.dart';

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
  // 资金明细账户筛选: 本金/收益各自独立计余额, 混排时余额列跳跃易误读
  String _logAcc = 'all';

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

  // ── 收益→本金转化 (公共弹层, 资产总览页同入口) ──
  Future<void> _openConvert(double incomeBal) async {
    final done = await showConvertSheet(context, incomeBal);
    if (done) _load();
  }

  // ── 资金明细 ──
  Widget _logList() {
    final logs = _logAcc == 'all'
        ? _logs
        : _logs.where((l) => l['account'] == _logAcc).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: Row(
            children: [
              for (final (key, label) in [
                ('all', tr('comm_filter_all')),
                ('principal', tr('funds_principal_short')),
                ('income', tr('funds_income_short')),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label, style: McText.sans(size: 11)),
                    selected: _logAcc == key,
                    onSelected: (_) => setState(() => _logAcc = key),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: logs.isEmpty
              ? _empty(tr('funds_empty_detail'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                  itemCount: logs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: McColors.outlineVariant),
                  itemBuilder: (_, i) {
                    final l = logs[i];
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
                            amt == 0 ? '0.00' : '${amt > 0 ? '+' : ''}${amt.toStringAsFixed(2)}',
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
                ),
        ),
      ],
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

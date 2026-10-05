import 'package:flutter/material.dart';

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
      if (mounted) setState(() => _error = '网络错误, 请稍后重试');
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
        title: Text('资金明细', style: McText.display(size: 16, weight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: McColors.primarySoft,
          labelColor: McColors.primarySoft,
          unselectedLabelColor: McColors.onSurfaceVariant,
          labelStyle: McText.sans(size: 12, weight: FontWeight.w600),
          tabs: const [
            Tab(text: '资金明细'),
            Tab(text: '收益结算'),
            Tab(text: '佣金'),
            Tab(text: '提现记录'),
            Tab(text: '等级变动'),
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
                Text('本金账户', style: McText.sans(size: 11, color: McColors.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(pBal.toStringAsFixed(2), style: McText.mono(size: 18, weight: FontWeight.w700)),
                if (pPend > 0)
                  Text('提现处理中 $pPend', style: McText.sans(size: 10, color: McColors.goldBright)),
              ],
            ),
          ),
          Container(width: 1, height: 36, color: McColors.outlineVariant),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('收益账户', style: McText.sans(size: 11, color: McColors.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(iBal.toStringAsFixed(2),
                    style: McText.mono(size: 18, weight: FontWeight.w700, color: McColors.tertiary)),
                if (iPend > 0)
                  Text('提现处理中 $iPend', style: McText.sans(size: 10, color: McColors.goldBright)),
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

  // ── 资金明细 ──
  Widget _logList() {
    if (_logs.isEmpty) return _empty('暂无资金明细');
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
                      '${isPrincipal ? '本金' : '收益'} · 余额 ${l['balance_after']} · ${FinanceApi.time(l['created_at'])}',
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
    if (_settlements.isEmpty) return _empty('暂无收益结算');
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
                    Text('订单 #${s['order_id']} · 第 ${s['period_no']} 期',
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
                    Text('返本 +${principal.toStringAsFixed(2)}',
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
    if (_commissions.isEmpty) return _empty('暂无佣金, 去邀请好友组建团队吧');
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
                    Text('${c['gen']} 代下线 · 订单 #${c['order_id']}',
                        style: McText.sans(size: 13, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      '基数 ${FinanceApi.d(c['base_amount'])} · 比例 ${FinanceApi.pct(c['rate'])} · 结算时团队 ${c['receiver_team_level']} 级 · ${FinanceApi.time(c['created_at'])}',
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
    if (_withdrawals.isEmpty) return _empty('暂无提现记录');
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
                      '${w['account'] == 'income' ? '收益' : '本金'} · ${w['amount']} USDT → ${w['arrive_amount']}',
                      style: McText.sans(size: 13, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '服务费 ${w['service_fee']} + 网络费 ${w['network_fee']} · ${FinanceApi.time(w['created_at'])}'
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
    if (_levelLogs.isEmpty) return _empty('暂无等级变动记录');
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
                    Text(isVip ? 'VIP 等级' : '团队等级',
                        style: McText.sans(size: 13, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      '${l['source'] == 'purchase' ? '购买' : '到期结算'}'
                      '${l['holding'] != null ? ' · 持仓 ${l['holding']}' : ''}'
                      '${l['member_count'] != null ? ' · ${l['member_count']} 人' : ''}'
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

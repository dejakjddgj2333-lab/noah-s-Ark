import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/api.dart';
import '../services/finance_api.dart';

/// 我的订单页 (V0.7 Phase 7.6): 产品/金额/状态/锁定 VIP 与加成/结算安排/到期时间.
class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  List<dynamic> _items = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final items = await FinanceApi.orders();
      if (mounted) setState(() => _items = items);
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
    final active = _items.where((o) => o['status'] == 'effective').toList();
    final done = _items.where((o) => o['status'] != 'effective').toList();

    return Scaffold(
      backgroundColor: McColors.surface,
      appBar: AppBar(
        backgroundColor: McColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: McColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('我的订单', style: McText.display(size: 16, weight: FontWeight.w700)),
      ),
      body: _busy && _items.isEmpty
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : RefreshIndicator(
              color: McColors.primarySoft,
              backgroundColor: McColors.surfaceContainer,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
                children: [
                  if (_error != null) ...[
                    _errorBox(_error!),
                    const SizedBox(height: 12),
                  ],
                  if (!_busy && _items.isEmpty && _error == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Center(
                        child: Text('暂无订单, 去理财产品页看看吧',
                            style: McText.sans(color: McColors.onSurfaceVariant)),
                      ),
                    ),
                  if (active.isNotEmpty) ...[
                    _section('生效中 (${active.length})'),
                    for (final o in active) _orderCard(o),
                  ],
                  if (done.isNotEmpty) ...[
                    _section('已完成 (${done.length})'),
                    for (final o in done) _orderCard(o),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _section(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 0, 8),
      child: Text(text, style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
    );
  }

  Widget _orderCard(dynamic o) {
    final status = o['status']?.toString() ?? '';
    final active = status == 'effective';
    final actualRate = o['actual_daily_rate'];
    final vipLv = o['vip_level'];
    final bonus = o['lock_bonus_rate'];
    final income = active && actualRate != null
        ? FinanceApi.d(o['amount']) * FinanceApi.d(actualRate) * FinanceApi.d(o['duration_days'])
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: McColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: McColors.surfaceContainerHigh),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${o['product_name']}',
                    style: McText.display(size: 14, weight: FontWeight.w600)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (active ? McColors.tertiary : McColors.onSurfaceVariant)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  FinLabels.orderStatus[status] ?? status,
                  style: McText.sans(
                    size: 11,
                    color: active ? McColors.tertiary : McColors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${o['amount']} USDT', style: McText.mono(size: 15, weight: FontWeight.w700)),
                    Text('订单金额', style: McText.sans(size: 11, color: McColors.onSurfaceVariant)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      actualRate == null ? '-' : '${(FinanceApi.d(actualRate) * 100).toStringAsFixed(3)}%',
                      style: McText.mono(size: 15, weight: FontWeight.w700, color: McColors.goldBright),
                    ),
                    Text('实际日收益率 (含VIP加成)', style: McText.sans(size: 11, color: McColors.onSurfaceVariant)),
                  ],
                ),
              ),
              if (income != null)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('≈${income.toStringAsFixed(2)}',
                          style: McText.mono(size: 15, weight: FontWeight.w700, color: McColors.tertiary)),
                      Text('预期总收益', style: McText.sans(size: 11, color: McColors.onSurfaceVariant)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(FinLabels.returnMethods[o['return_method']] ?? '${o['return_method']}'),
              _chip('周期 ${o['duration_days']} 天'),
              if (vipLv != null) ...[
                _chip('下单时 VIP$vipLv'),
                _chip('锁定加成 +${(FinanceApi.d(bonus) * 100).toStringAsFixed(0)}%'),
              ],
              _chip('规则 v${o['rule_version']}'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text('生效 ${FinanceApi.time(o['effective_at'])}',
                    style: McText.mono(size: 11, color: McColors.onSurfaceVariant)),
              ),
              Expanded(
                child: Text('到期 ${FinanceApi.time(o['expires_at'])}',
                    style: McText.mono(size: 11, color: McColors.onSurfaceVariant)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: McText.sans(size: 11, color: McColors.onSurfaceVariant)),
    );
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

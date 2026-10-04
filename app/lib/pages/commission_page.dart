import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/api.dart';
import '../services/finance_api.dart';

/// 分佣页 (V0.7 第四/八节): 累计佣金 / 团队等级与三代返佣比例 / 佣金明细.
/// 明细字段: 来源代数与下级、关联订单与结算期、基数、比例、金额、应结算时间、实际入账时间.
class CommissionPage extends StatefulWidget {
  const CommissionPage({super.key});

  @override
  State<CommissionPage> createState() => _CommissionPageState();
}

class _CommissionPageState extends State<CommissionPage> {
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _team;
  List<dynamic>? _records;
  bool _busy = false;
  String? _error;
  int _genFilter = 0; // 0 全部, 1/2/3 代数

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
      final results = await Future.wait([
        FinanceApi.commissionSummary(),
        FinanceApi.teamMe(),
        FinanceApi.commissions(),
      ]);
      if (mounted) {
        setState(() {
          _summary = results[0] as Map<String, dynamic>;
          _team = results[1] as Map<String, dynamic>;
          _records = results[2] as List<dynamic>;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '网络错误, 请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _fmtTime(String? iso) {
    if (iso == null || iso.isEmpty) return '-';
    return iso.replaceAll('T', ' ').substring(0, iso.length >= 16 ? 16 : iso.length);
  }

  String _pct(dynamic rate) =>
      '${(FinanceApi.d(rate) * 100).toStringAsFixed(2)}%';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: McColors.surface,
      appBar: AppBar(
        backgroundColor: McColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: McColors.onSurface),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('邀请返佣', style: McText.display(size: 16, weight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20, color: McColors.onSurfaceVariant),
            onPressed: _busy ? null : _load,
          ),
        ],
      ),
      body: _busy && _summary == null
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
                  _summaryCard(),
                  const SizedBox(height: 12),
                  _teamCard(),
                  const SizedBox(height: 12),
                  _recordsCard(),
                ],
              ),
            ),
    );
  }

  // ---- 汇总卡: 累计佣金 + 今日 + 去提现/去邀请 ----
  Widget _summaryCard() {
    final total = FinanceApi.d(_summary?['total']);
    final today = FinanceApi.d(_summary?['today']);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B2A6B), Color(0xFF0B1026)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('累计佣金 (USDT)',
              style: McText.sans(size: 12, color: Colors.white.withValues(alpha: 0.8))),
          const SizedBox(height: 6),
          Text(total.toStringAsFixed(2),
              style: McText.mono(size: 32, weight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 4),
          Text('今日 +${today.toStringAsFixed(2)}',
              style: McText.mono(size: 12, color: McColors.tertiary)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _actionBtn(
                  icon: Icons.account_balance_wallet,
                  label: '去提现',
                  primary: true,
                  onTap: () => Navigator.of(context).pushNamed('/withdraw'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionBtn(
                  icon: Icons.person_add_alt,
                  label: '邀请好友',
                  primary: false,
                  onTap: () => Navigator.of(context).pushNamed('/invite'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required bool primary,
    required VoidCallback onTap,
  }) {
    return Material(
      color: primary ? McColors.primaryContainer : Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(label,
                  style: McText.sans(size: 13, weight: FontWeight.w700, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  // ---- 团队等级卡: 等级 + 三代比例 + 升级差额 + 入口 ----
  Widget _teamCard() {
    final lv = _team?['team_level'] as int? ?? 0;
    final members = _team?['member_count'] as int? ?? 0;
    final holding = FinanceApi.d(_team?['total_holding']);
    final nextLv = _team?['next_level'] as int?;
    return GestureDetector(
      onTap: () => Navigator.of(context).pushNamed('/team'),
      child: Container(
        padding: const EdgeInsets.all(16),
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
                const Icon(Icons.groups, size: 18, color: McColors.tertiary),
                const SizedBox(width: 8),
                Text('我的团队等级', style: McText.sans(size: 14, weight: FontWeight.w700)),
                const Spacer(),
                Text('团队 $lv 级',
                    style: McText.display(size: 14, weight: FontWeight.w700, color: McColors.tertiary)),
                const Icon(Icons.chevron_right, size: 16, color: McColors.onSurfaceVariant),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final (label, key) in [('一代', 'gen1_rate'), ('二代', 'gen2_rate'), ('三代', 'gen3_rate')])
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: McColors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _team?[key] == null ? '—' : _pct(_team![key]),
                            style: McText.mono(size: 14, weight: FontWeight.w700, color: McColors.primarySoft),
                          ),
                          Text('$label返佣',
                              style: McText.sans(size: 10, color: McColors.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '三代有效成员 $members 人 · 团队持仓 ${holding.toStringAsFixed(2)} USDT'
              '${nextLv != null ? ' · 距 ${nextLv} 级还差 ${_team?['next_member_gap'] ?? 0} 人 / ${FinanceApi.d(_team?['next_holding_gap']).toStringAsFixed(0)} USDT' : ' · 已达最高等级'}',
              style: McText.sans(size: 11, color: McColors.onSurfaceVariant, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 佣金明细 ----
  Widget _recordsCard() {
    final all = _records ?? const [];
    final list = _genFilter == 0
        ? all
        : all.where((r) => r is Map && r['gen'] == _genFilter).toList();
    return Container(
      padding: const EdgeInsets.all(16),
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
              Text('佣金明细', style: McText.sans(size: 14, weight: FontWeight.w700)),
              const Spacer(),
              Text('共 ${all.length} 笔',
                  style: McText.sans(size: 11, color: McColors.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (i, label) in [(0, '全部'), (1, '一代'), (2, '二代'), (3, '三代')]) ...[
                  GestureDetector(
                    onTap: () => setState(() => _genFilter = i),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: _genFilter == i
                            ? McColors.primaryContainer
                            : McColors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        label,
                        style: McText.sans(
                          size: 12,
                          weight: _genFilter == i ? FontWeight.w700 : FontWeight.w500,
                          color: _genFilter == i
                              ? McColors.onPrimaryContainer
                              : McColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('暂无佣金记录, 邀请好友购买产品后按结算收益返佣',
                    style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
              ),
            )
          else
            for (var i = 0; i < list.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: McColors.outlineVariant),
              _recordItem(list[i] as Map<String, dynamic>),
            ],
        ],
      ),
    );
  }

  Widget _recordItem(Map<String, dynamic> r) {
    const genLabels = {1: '一代', 2: '二代', 3: '三代'};
    final gen = r['gen'] as int? ?? 0;
    final buyer = (r['buyer_username'] ?? '用户#${r['buyer_id']}').toString();
    final base = FinanceApi.d(r['base_amount']);
    final rate = FinanceApi.d(r['rate']);
    final amount = FinanceApi.d(r['amount']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: McColors.primaryContainer.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text('${gen}代',
                  style: McText.sans(size: 11, weight: FontWeight.w700, color: McColors.primarySoft)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text('来自 $buyer',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: McText.sans(size: 13, weight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: McColors.tertiary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('${genLabels[gen] ?? "$gen代"}返佣',
                          style: McText.sans(size: 10, weight: FontWeight.w600, color: McColors.tertiary)),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '订单#${r['order_id']} 第${r['period_no'] ?? '-'}期 · 基数 ${base.toStringAsFixed(2)} × ${_pct(rate)}',
                  style: McText.mono(size: 11, color: McColors.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(
                  '应结算 ${_fmtTime(r['settle_at']?.toString())} · 入账 ${_fmtTime(r['created_at']?.toString())}',
                  style: McText.sans(size: 10, color: McColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('+${amount.toStringAsFixed(2)}',
                  style: McText.mono(size: 14, weight: FontWeight.w700, color: McColors.tertiary)),
              Text('已入账', style: McText.sans(size: 10, color: McColors.onSurfaceVariant)),
            ],
          ),
        ],
      ),
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

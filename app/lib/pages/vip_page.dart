import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../services/api.dart';
import '../services/finance_api.dart';

/// 个人 VIP 页 (V0.7 Phase 7.3): 有效持仓 / 当前等级 / 加成 / 距下一级差额 + 等级表.
class VipPage extends StatefulWidget {
  const VipPage({super.key});

  @override
  State<VipPage> createState() => _VipPageState();
}

/// 文档第三节 VIP 阈值/加成表 (等级, 有效持仓门槛, 收益加成).
const _kVipTable = [
  (0, 0.0, 0.0),
  (1, 1000.0, 0.05),
  (2, 3000.0, 0.06),
  (3, 5000.0, 0.07),
  (4, 10000.0, 0.08),
  (5, 20000.0, 0.09),
  (6, 40000.0, 0.12),
  (7, 70000.0, 0.15),
  (8, 100000.0, 0.18),
  (9, 150000.0, 0.21),
  (10, 200000.0, 0.24),
];

class _VipPageState extends State<VipPage> {
  Map<String, dynamic>? _info;
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
      final info = await FinanceApi.vipMe();
      if (mounted) setState(() => _info = info);
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
    final lv = _info?['vip_level'] as int? ?? 0;
    final holding = FinanceApi.d(_info?['effective_holding']);
    final bonus = FinanceApi.d(_info?['bonus_rate']);
    final gap = _info?['gap_to_next'];
    final gapVal = gap == null ? null : FinanceApi.d(gap);
    final nextLv = _info?['next_level'] as int?;

    return Scaffold(
      backgroundColor: McColors.surface,
      appBar: AppBar(
        backgroundColor: McColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: McColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(tr('vip_title'), style: McText.display(size: 16, weight: FontWeight.w700)),
      ),
      body: _busy && _info == null
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
                  // 当前等级卡
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2E5CFF), Color(0xFF1B3BA8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('VIP$lv',
                                style: McText.display(size: 34, weight: FontWeight.w700, color: Colors.white)),
                            const SizedBox(width: 12),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(tr('vip_bonus').replaceAll('{n}', (bonus * 100).toStringAsFixed(0)),
                                  style: McText.sans(size: 13, color: Colors.white.withValues(alpha: 0.9))),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(holding.toStringAsFixed(2),
                                      style: McText.mono(size: 18, weight: FontWeight.w700, color: Colors.white)),
                                  Text(tr('vip_holding'),
                                      style: McText.sans(size: 11, color: Colors.white.withValues(alpha: 0.8))),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    gapVal == null ? tr('vip_max_level') : '${gapVal.toStringAsFixed(0)} USDT',
                                    style: McText.mono(size: 18, weight: FontWeight.w700, color: Colors.white),
                                  ),
                                  Text(
                                    gapVal == null ? tr('vip_max_congrats') : tr('vip_to_next').replaceAll('{n}', '$nextLv'),
                                    style: McText.sans(size: 11, color: Colors.white.withValues(alpha: 0.8)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (gapVal != null && nextLv != null) ...[
                          const SizedBox(height: 14),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: (holding / (holding + gapVal)).clamp(0.0, 1.0),
                              minHeight: 6,
                              backgroundColor: Colors.white.withValues(alpha: 0.2),
                              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF2CA50)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(tr('vip_rules_title'),
                      style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: McColors.surfaceContainer,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: McColors.surfaceContainerHigh),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < _kVipTable.length; i++) ...[
                          if (i > 0)
                            const Divider(height: 1, color: McColors.outlineVariant),
                          _vipRow(_kVipTable[i], lv),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr('vip_note'),
                    style: McText.sans(size: 11, color: McColors.onSurfaceVariant, height: 1.6),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _vipRow((int, double, double) row, int current) {
    final (lv, threshold, bonus) = row;
    final isCurrent = lv == current;
    return Container(
      color: isCurrent ? McColors.primaryContainer.withValues(alpha: 0.18) : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text('VIP$lv',
                style: McText.display(
                  size: 13,
                  weight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                  color: isCurrent ? McColors.primarySoft : McColors.onSurface,
                )),
          ),
          Expanded(
            child: Text(
              lv == 0 ? tr('vip_any_holding') : tr('vip_holding_ge').replaceAll('{n}', threshold.toStringAsFixed(0)),
              style: McText.sans(size: 12, color: McColors.onSurfaceVariant),
            ),
          ),
          Text(
            lv == 0 ? tr('vip_no_bonus') : tr('vip_bonus_pct').replaceAll('{n}', (bonus * 100).toStringAsFixed(0)),
            style: McText.mono(
              size: 12,
              weight: isCurrent ? FontWeight.w700 : FontWeight.w400,
              color: isCurrent ? McColors.goldBright : McColors.onSurfaceVariant,
            ),
          ),
          if (isCurrent) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: McColors.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(tr('vip_current'), style: McText.sans(size: 10, color: McColors.primarySoft)),
            ),
          ],
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

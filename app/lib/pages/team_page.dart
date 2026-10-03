import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/api.dart';
import '../services/finance_api.dart';

/// 我的团队页 (V0.7 Phase 7.4): 三代有效人数 / 有效持仓 / 团队等级 / 各级返佣比例 / 升级差额.
class TeamPage extends StatefulWidget {
  const TeamPage({super.key});

  @override
  State<TeamPage> createState() => _TeamPageState();
}

/// 文档第四节团队等级表 (等级, 有效人数≥, 有效持仓≥, 一代/二代/三代比例).
/// 0 级仅一代 5%; 1 级一/二代; 2 级起三代; 比例 0 表示无资格, 不越级转移.
const _kTeamTable = [
  (0, 0, 0, 5.0, 0.0, 0.0),
  (1, 5, 6000, 5.0, 3.0, 0.0),
  (2, 10, 12000, 5.0, 3.0, 2.0),
  (3, 20, 24000, 5.2, 3.1, 2.1),
  (4, 40, 48000, 5.6, 3.3, 2.3),
  (5, 70, 84000, 6.2, 3.6, 2.6),
  (6, 120, 144000, 7.0, 4.0, 3.0),
  (7, 200, 240000, 8.0, 4.5, 3.5),
  (8, 350, 420000, 9.2, 5.1, 4.1),
  (9, 600, 720000, 10.6, 5.8, 4.8),
  (10, 1000, 1200000, 12.2, 6.6, 5.6),
];

class _TeamPageState extends State<TeamPage> {
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
      final info = await FinanceApi.teamMe();
      if (mounted) setState(() => _info = info);
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
    final lv = _info?['team_level'] as int? ?? 0;
    final members = _info?['member_count'] as int? ?? 0;
    final holding = FinanceApi.d(_info?['total_holding']);
    final g1 = _info?['gen1_rate'];
    final g2 = _info?['gen2_rate'];
    final g3 = _info?['gen3_rate'];
    final nextLv = _info?['next_level'] as int?;
    final memberGap = _info?['next_member_gap'] as int?;
    final holdingGap = _info?['next_holding_gap'];

    return Scaffold(
      backgroundColor: McColors.surface,
      appBar: AppBar(
        backgroundColor: McColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: McColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('我的团队', style: McText.display(size: 16, weight: FontWeight.w700)),
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
                  // 当前团队等级卡
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0E5E4E), Color(0xFF08382F)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('$lv 级',
                                style: McText.display(size: 32, weight: FontWeight.w700, color: Colors.white)),
                            const SizedBox(width: 10),
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text('团队等级',
                                  style: McText.sans(size: 12, color: Colors.white.withValues(alpha: 0.85))),
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
                                  Text('$members 人',
                                      style: McText.mono(size: 18, weight: FontWeight.w700, color: Colors.white)),
                                  Text('三代内有效成员',
                                      style: McText.sans(size: 11, color: Colors.white.withValues(alpha: 0.8))),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(holding.toStringAsFixed(2),
                                      style: McText.mono(size: 18, weight: FontWeight.w700, color: Colors.white)),
                                  Text('团队有效持仓 (USDT)',
                                      style: McText.sans(size: 11, color: Colors.white.withValues(alpha: 0.8))),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            for (final (label, v) in [('一代', g1), ('二代', g2), ('三代', g3)]) ...[
                              Expanded(
                                child: Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        v == null ? '—' : '${(FinanceApi.d(v) * 100).toStringAsFixed(1)}%',
                                        style: McText.display(size: 15, weight: FontWeight.w700, color: Colors.white),
                                      ),
                                      Text('$label返佣', style: McText.sans(size: 10, color: Colors.white.withValues(alpha: 0.8))),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (nextLv != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            '距 $nextLv 级: 还差 ${memberGap ?? 0} 名有效成员、${FinanceApi.d(holdingGap).toStringAsFixed(0)} USDT 团队持仓 (人数与金额需同时达标)',
                            style: McText.sans(size: 11, color: Colors.white.withValues(alpha: 0.85), height: 1.5),
                          ),
                        ] else ...[
                          const SizedBox(height: 12),
                          Text('已达最高团队等级',
                              style: McText.sans(size: 11, color: Colors.white.withValues(alpha: 0.85))),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('团队等级规则 (人数与持仓同时达标取最高级)', style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: McColors.surfaceContainer,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: McColors.surfaceContainerHigh),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < _kTeamTable.length; i++) ...[
                          if (i > 0)
                            const Divider(height: 1, color: McColors.outlineVariant),
                          _teamRow(_kTeamTable[i], lv),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '说明: 仅统计下级第一、二、三代; 有效成员 = 同一成员当前全部有效产品合计 ≥300 USDT 计 1 人 (多笔合并), 不足 300 不计人数但金额计入团队总额; 返佣 = 下线每期结算收益 × 对应比例, 按结算时点您的团队等级取值; 0 级仅一代 5%, 无资格份额不发放、不越级转移。',
                    style: McText.sans(size: 11, color: McColors.onSurfaceVariant, height: 1.6),
                  ),
                ],
              ),
            ),
  }

  Widget _teamRow((int, int, int, double, double, double) row, int current) {
    final (lv, members, holding, g1, g2, g3) = row;
    final isCurrent = lv == current;
    String rate(double v) => v <= 0 ? '—' : '${v.toStringAsFixed(1)}%';
    return Container(
      color: isCurrent ? McColors.tertiary.withValues(alpha: 0.12) : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text('$lv级',
                style: McText.display(
                  size: 13,
                  weight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                  color: isCurrent ? McColors.tertiary : McColors.onSurface,
                )),
          ),
          Expanded(
            flex: 3,
            child: Text('$members 人 / ≥$holding',
                style: McText.mono(size: 11, color: McColors.onSurfaceVariant)),
          ),
          Expanded(
            flex: 3,
            child: Text('${rate(g1)} / ${rate(g2)} / ${rate(g3)}',
                textAlign: TextAlign.right,
                style: McText.mono(
                  size: 11,
                  weight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                  color: isCurrent ? McColors.goldBright : McColors.onSurfaceVariant,
                )),
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

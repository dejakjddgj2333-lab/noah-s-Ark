import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../services/feature_flag.dart';

/// 理财 — bottom-nav tab (FINANCE_ENABLED 编译期开启时出现, 位于第 3 位).
/// 仅承载理财中心功能直达; 合伙人分佣看板仍留在「我的」页.
/// Content body only: scrollable, h-pad 14, top 16, bottom 32.
class FinancePage extends StatelessWidget {
  const FinancePage({super.key});

  static const cobalt = Color(0xFF2E5CFF);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 32),
      children: [
        _financeCenterCard(context),
      ],
    );
  }

  // ---- 理财中心 (功能直达, 独立卡片) ----
  Widget _financeCenterCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: McColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: McColors.surfaceContainerHigh),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('assets_finance_center'),
            style: McText.display(size: 16, weight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          ListenableBuilder(
            listenable: FeatureFlag.instance,
            builder: (context, _) {
              final walletOn = FeatureFlag.instance.walletEnabled;
              final items = [
                ('/products', Icons.savings_outlined, tr('assets_products')),
                ('/vip', Icons.workspace_premium_outlined, tr('assets_my_vip')),
                ('/team', Icons.groups_outlined, tr('assets_my_team')),
                ('/orders', Icons.receipt_long_outlined, tr('assets_my_orders')),
                ('/funds', Icons.account_balance_wallet_outlined, tr('assets_fund_details')),
                // 提现入口随钱包开关显隐
                if (walletOn)
                  ('/withdraw', Icons.outbox_outlined, tr('assets_withdraw_short')),
              ];
              return GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                padding: EdgeInsets.zero, // 否则 primary 滚动视图自动吃状态栏 inset, 标题下出现大空隙
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.5,
                children: [
                  for (final (route, icon, label) in items)
                    Material(
                      color: McColors.surfaceContainerHigh.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => Navigator.pushNamed(context, route),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(icon, size: 22, color: McColors.primarySoft),
                            const SizedBox(height: 6),
                            Text(
                              label,
                              style: McText.sans(size: 12, weight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

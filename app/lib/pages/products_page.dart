import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../services/api.dart';
import '../services/finance_api.dart';
import '../services/invite_api.dart';

/// 产品列表/详情/购买 (V0.7 Phase 7.5 + 7.2).
/// 7.2 首购提示: 未绑定上级且仍可补绑的用户, 首次购买前弹窗告知
/// "本人或任意层级下级购买成功后将无法补填邀请码".
class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
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
      final items = await FinanceApi.products();
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = tr('net_error_retry'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openDetail(dynamic p) async {
    final bought = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: McColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _PurchaseSheet(product: p),
    );
    if (bought == true) _load();
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
        title: Text(tr('prod_title'), style: McText.display(size: 16, weight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        color: McColors.primarySoft,
        backgroundColor: McColors.surfaceContainer,
        onRefresh: _load,
        child: _busy && _items.isEmpty
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : ListView(
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
                        child: Text(tr('prod_empty'), style: McText.sans(color: McColors.onSurfaceVariant)),
                      ),
                    ),
                  for (final p in _items) ...[
                    _productCard(p),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
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

  Widget _productCard(dynamic p) {
    final rate = FinanceApi.d(p['base_daily_rate']);
    final totalPct = rate * FinanceApi.d(p['duration_days']) * 100;
    return Material(
      color: McColors.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDetail(p),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: McColors.surfaceContainerHigh),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${p['name']}',
                      style: McText.display(size: 15, weight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: McColors.tertiary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      FinLabels.returnMethods[p['return_method']] ?? '${p['return_method']}',
                      style: McText.sans(size: 11, color: McColors.tertiary),
                    ),
                  ),
                ],
              ),
              if (p['description'] != null) ...[
                const SizedBox(height: 6),
                Text('${p['description']}', style: McText.sans(size: 12, color: McColors.onSurfaceVariant),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${(rate * 100).toStringAsFixed(2)}%',
                          style: McText.display(size: 22, weight: FontWeight.w700, color: McColors.goldBright),
                        ),
                        Text(tr('prod_base_daily'), style: McText.sans(size: 11, color: McColors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${p['duration_days']} ${tr('prod_days')}',
                            style: McText.display(size: 16, weight: FontWeight.w600)),
                        Text(tr('prod_period'), style: McText.sans(size: 11, color: McColors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${totalPct.toStringAsFixed(1)}%',
                            style: McText.display(size: 16, weight: FontWeight.w600, color: McColors.tertiary)),
                        Text(tr('prod_total_return'), style: McText.sans(size: 11, color: McColors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.payments_outlined, size: 13, color: McColors.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${p['min_amount']} ~ ${p['max_amount']} USDT',
                      style: McText.mono(size: 12, color: McColors.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (p['vip_level_req'] != null)
                    _reqChip('VIP${p['vip_level_req']}')
                  else
                    _reqChip(tr('prod_no_vip')),
                  const SizedBox(width: 6),
                  if (p['team_level_req'] != null)
                    _reqChip(tr('prod_team_req').replaceAll('{n}', '${p['team_level_req']}'))
                  else
                    _reqChip(tr('prod_no_team')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reqChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: McText.mono(size: 10, color: McColors.onSurfaceVariant)),
    );
  }
}

/// 购买弹层: 详情 + 金额输入 + 7.2 首购提示 + 提交.
class _PurchaseSheet extends StatefulWidget {
  const _PurchaseSheet({required this.product});

  final dynamic product;

  @override
  State<_PurchaseSheet> createState() => _PurchaseSheetState();
}

class _PurchaseSheetState extends State<_PurchaseSheet> {
  final _amountCtrl = TextEditingController();
  bool _busy = false;

  dynamic get _p => widget.product;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = _amountCtrl.text.trim();
    if (amount.isEmpty || (double.tryParse(amount) ?? 0) <= 0) {
      _toast(tr('prod_err_amount'));
      return;
    }
    setState(() => _busy = true);
    try {
      // 7.2: 购买前检查补绑资格, 仍可补绑的用户先提示资格将永久失效
      try {
        final inv = await InviteApi.me();
        if (!inv.bound && inv.canBind && mounted) {
          final go = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: McColors.surfaceContainer,
              title: Text(tr('prod_prebuy_title'), style: McText.display(size: 15, weight: FontWeight.w700)),
              content: Text(
                tr('prod_prebuy_body'),
                style: McText.sans(size: 13, height: 1.5),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(tr('prod_go_bind'), style: McText.sans(color: McColors.onSurfaceVariant)),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(tr('prod_continue_buy'), style: McText.sans(color: McColors.goldBright, weight: FontWeight.w600)),
                ),
              ],
            ),
          );
          if (go != true) {
            setState(() => _busy = false);
            return;
          }
        }
      } on ApiException {
        // 邀请信息拉取失败不阻塞购买
      }

      await FinanceApi.buy(_p['id'] as int, amount);
      if (!mounted) return;
      _toast(tr('prod_buy_success'));
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    } catch (_) {
      if (mounted) _toast(tr('net_error_retry'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: McText.sans(size: 13)),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: McColors.surfaceContainerHighest,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rate = FinanceApi.d(_p['base_daily_rate']);
    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${_p['name']}', style: McText.display(size: 17, weight: FontWeight.w700),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20, color: McColors.onSurfaceVariant),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            tr('prod_detail_line')
                .replaceAll('{rate}', (rate * 100).toStringAsFixed(2))
                .replaceAll('{days}', '${_p['duration_days']}')
                .replaceAll('{method}', FinLabels.returnMethods[_p['return_method']] ?? '${_p['return_method']}'),
            style: McText.sans(size: 12, color: McColors.onSurfaceVariant),
          ),
          Text(
            tr('prod_range_line')
                .replaceAll('{min}', '${_p['min_amount']}')
                .replaceAll('{max}', '${_p['max_amount']}')
                .replaceAll('{vip}', _p['vip_level_req'] != null ? tr('prod_need_vip').replaceAll('{n}', '${_p['vip_level_req']}') : '')
                .replaceAll('{team}', _p['team_level_req'] != null ? tr('prod_need_team').replaceAll('{n}', '${_p['team_level_req']}') : ''),
            style: McText.sans(size: 12, color: McColors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Text(tr('prod_amount'), style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
          const SizedBox(height: 6),
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: McText.mono(size: 16),
            decoration: InputDecoration(
              hintText: '${_p['min_amount']} ~ ${_p['max_amount']}',
              hintStyle: McText.mono(size: 14, color: McColors.onSurfaceVariant),
              filled: true,
              fillColor: McColors.surfaceContainerHigh.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              suffixText: 'USDT',
              suffixStyle: McText.sans(size: 12, color: McColors.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr('prod_note'),
            style: McText.sans(size: 11, color: McColors.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: McColors.primaryContainer,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: McColors.onPrimaryContainer),
                    )
                  : Text(tr('prod_confirm_buy'), style: McText.display(size: 14, weight: FontWeight.w700, color: McColors.onPrimaryContainer)),
            ),
          ),
        ],
      ),
    );
  }
}

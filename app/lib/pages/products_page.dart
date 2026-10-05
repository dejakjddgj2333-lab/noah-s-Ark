import 'package:flutter/material.dart';

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
      if (mounted) setState(() => _error = '网络错误, 请稍后重试');
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
        title: Text('理财产品', style: McText.display(size: 16, weight: FontWeight.w700)),
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
                        child: Text('暂无上架产品', style: McText.sans(color: McColors.onSurfaceVariant)),
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
                        Text('基础日收益率', style: McText.sans(size: 11, color: McColors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${p['duration_days']} 天',
                            style: McText.display(size: 16, weight: FontWeight.w600)),
                        Text('产品周期', style: McText.sans(size: 11, color: McColors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${totalPct.toStringAsFixed(1)}%',
                            style: McText.display(size: 16, weight: FontWeight.w600, color: McColors.tertiary)),
                        Text('基础总收益', style: McText.sans(size: 11, color: McColors.onSurfaceVariant)),
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
                    _reqChip('不限 VIP'),
                  const SizedBox(width: 6),
                  if (p['team_level_req'] != null)
                    _reqChip('团队 ${p['team_level_req']} 级')
                  else
                    _reqChip('不限团队'),
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
  String? _amountError;

  dynamic get _p => widget.product;

  @override
  void initState() {
    super.initState();
    // 输入即清除错误提示
    _amountCtrl.addListener(() {
      if (_amountError != null) setState(() => _amountError = null);
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = _amountCtrl.text.trim();
    if (amount.isEmpty || (double.tryParse(amount) ?? 0) <= 0) {
      // 购买弹层是覆盖在 Scaffold 上的 modal, SnackBar 会被遮住看不见,
      // 故校验错误直接在弹层内红字展示
      setState(() => _amountError = '请输入有效金额');
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
              title: Text('购买前提示', style: McText.display(size: 15, weight: FontWeight.w700)),
              content: Text(
                '您还未绑定邀请码。本人或任意层级下级购买成功后, 将无法补填邀请码绑定上级, 该资格永久失效。',
                style: McText.sans(size: 13, height: 1.5),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text('先去绑定', style: McText.sans(color: McColors.onSurfaceVariant)),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text('继续购买', style: McText.sans(color: McColors.goldBright, weight: FontWeight.w600)),
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
      // 成功后先弹提示再关弹层: SnackBar 挂在页面 Scaffold 上, 弹层关闭后可见
      _toast('购买成功, 订单已生效');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      // 服务端错误 (余额不足/超范围/等级不够等) 也在弹层内联展示, 不被 modal 遮住
      if (mounted) setState(() => _amountError = e.message);
    } catch (_) {
      if (mounted) setState(() => _amountError = '网络错误, 请稍后重试');
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
            '日收益率 ${(rate * 100).toStringAsFixed(2)}% · 周期 ${_p['duration_days']} 天 · '
            '${FinLabels.returnMethods[_p['return_method']] ?? _p['return_method']}',
            style: McText.sans(size: 12, color: McColors.onSurfaceVariant),
          ),
          Text(
            '金额范围 ${_p['min_amount']} ~ ${_p['max_amount']} USDT'
            '${_p['vip_level_req'] != null ? ' · 需 VIP${_p['vip_level_req']}' : ''}'
            '${_p['team_level_req'] != null ? ' · 需团队 ${_p['team_level_req']} 级' : ''}',
            style: McText.sans(size: 12, color: McColors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Text('购买金额 (USDT)', style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
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
              errorText: _amountError,  // 校验失败在输入框内联红字展示
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
            '从本金账户扣款, 扣款成功订单即生效; 下单时按当前 VIP 等级锁定收益加成, 到期自动返还本金。',
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
                  : Text('确认购买', style: McText.display(size: 14, weight: FontWeight.w700, color: McColors.onPrimaryContainer)),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../core/theme.dart';
import '../services/api.dart';
import '../services/finance_api.dart';

/// 收益→本金转化弹层 (公共组件): 资产总览页与资金明细页共用同一入口.
/// 输入金额 → 报价确认 → 执行 (服务端重算, 费用确认后不追加).
/// 幂等键弹层打开即生成, 网络超时重试/重复点击服务端只扣一次.
Future<bool> showConvertSheet(BuildContext context, double incomeBal) async {
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: McColors.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => ConvertSheet(incomeBal: incomeBal),
  );
  return done == true;
}

class ConvertSheet extends StatefulWidget {
  const ConvertSheet({super.key, required this.incomeBal});
  final double incomeBal;

  @override
  State<ConvertSheet> createState() => _ConvertSheetState();
}

class _ConvertSheetState extends State<ConvertSheet> {
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

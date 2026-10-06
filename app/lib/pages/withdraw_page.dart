import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../services/api.dart';
import '../services/finance_api.dart';

/// 提现页 (V0.7 Phase 7.8): 账户选择 / 网络选择 / 金额 / 地址 / 实时费用报价 → 确认提交.
/// 规则: 收益账户 ≥50 USDT + 3% 服务费; 本金账户无门槛无服务费;
/// 费用从申请金额内扣 (实际到账 = 金额 - 服务费 - 网络费), 各网络网络费不同.
class WithdrawPage extends StatefulWidget {
  const WithdrawPage({super.key});

  @override
  State<WithdrawPage> createState() => _WithdrawPageState();
}

class _WithdrawPageState extends State<WithdrawPage> {
  String _account = 'income';
  String _network = 'trc20';
  List<dynamic> _networks = const [];
  final _amountCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();
  Map<String, dynamic>? _quote;
  Map<String, dynamic>? _acct;
  bool _busy = false;
  bool _quoting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAccount();
    _loadNetworks();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _addrCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAccount() async {
    try {
      final a = await FinanceApi.account();
      if (mounted) setState(() => _acct = a);
    } on ApiException catch (_) {
      // 头部加载失败不阻塞
    }
  }

  Future<void> _loadNetworks() async {
    try {
      final list = await FinanceApi.withdrawNetworks();
      if (mounted && list.isNotEmpty) setState(() => _networks = list);
    } catch (_) {
      // 失败回退内置四网络
    }
  }

  String get _networkLabel {
    for (final n in _networks) {
      if (n is Map && n['network'] == _network) return (n['label'] ?? _network).toString();
    }
    return _network.toUpperCase();
  }

  bool get _isEvm => _network != 'trc20';

  Future<void> _doQuote() async {
    final amount = _amountCtrl.text.trim();
    if (amount.isEmpty || (double.tryParse(amount) ?? 0) <= 0) {
      setState(() => _quote = null);
      return;
    }
    setState(() => _quoting = true);
    try {
      final q = await FinanceApi.withdrawQuote(account: _account, amount: amount, network: _network);
      if (mounted) setState(() => _quote = q);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _quote = null);
        _toast(e.message);
      }
    } catch (_) {
      if (mounted) setState(() => _quote = null);
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  Future<void> _submit() async {
    final amount = _amountCtrl.text.trim();
    final addr = _addrCtrl.text.trim();
    if (amount.isEmpty || (double.tryParse(amount) ?? 0) <= 0) {
      _toast(tr('wd_err_amount'));
      return;
    }
    if (addr.isEmpty) {
      _toast(tr('wd_err_addr').replaceAll('{network}', _networkLabel));
      return;
    }
    // 提交前以服务端报价二次确认 (报价接口无需登录, 提交时服务端重算为准)
    Map<String, dynamic>? q = _quote;
    if (q == null) {
      try {
        q = await FinanceApi.withdrawQuote(account: _account, amount: amount, network: _network);
      } on ApiException catch (e) {
        _toast(e.message);
        return;
      }
    }
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: McColors.surfaceContainer,
        title: Text(tr('wd_confirm_title'), style: McText.display(size: 15, weight: FontWeight.w700)),
        content: Text(
          '${tr(_account == 'income' ? 'wd_acct_income' : 'wd_acct_principal')}${tr('wd_confirm_line1').replaceAll('{amount}', '${q!['amount']}').replaceAll('{network}', _networkLabel)}\n'
          '${tr('wd_confirm_line2').replaceAll('{service}', '${q['service_fee']}').replaceAll('{network_fee}', '${q['network_fee']}')}\n'
          '${tr('wd_confirm_line3').replaceAll('{arrive}', '${q['arrive_amount']}')}\n'
          '${tr('wd_confirm_addr')} ${addr.length > 20 ? '${addr.substring(0, 12)}...${addr.substring(addr.length - 8)}' : addr}',
          style: McText.mono(size: 12, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('cancel'), style: McText.sans(color: McColors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('wd_confirm_submit'), style: McText.sans(color: McColors.goldBright, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await FinanceApi.withdrawCreate({
        'account': _account,
        'network': _network,
        'address': addr,
        'amount': amount,
      });
      if (!mounted) return;
      _toast(tr('wd_submitted'));
      _amountCtrl.clear();
      _addrCtrl.clear();
      setState(() => _quote = null);
      _loadAccount();
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
    final pBal = FinanceApi.d(_acct?['principal_balance']);
    final iBal = FinanceApi.d(_acct?['income_balance']);
    final avail = _account == 'income' ? iBal : pBal;

    return Scaffold(
      backgroundColor: McColors.surface,
      appBar: AppBar(
        backgroundColor: McColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: McColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(tr('wd_title'), style: McText.display(size: 16, weight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
        children: [
          if (_error != null) ...[
            _errorBox(_error!),
            const SizedBox(height: 12),
          ],
          // 账户选择
          Row(
            children: [
              for (final (key, label, bal, color) in [
                ('income', tr('wd_acct_income_full'), iBal, McColors.tertiary),
                ('principal', tr('wd_acct_principal_full'), pBal, McColors.primarySoft),
              ])
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _account = key;
                      _quote = null;
                    }),
                    child: Container(
                      margin: EdgeInsets.only(right: key == 'income' ? 6 : 0, left: key == 'principal' ? 6 : 0),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _account == key
                            ? color.withValues(alpha: 0.14)
                            : McColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _account == key ? color : McColors.surfaceContainerHigh,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
                          const SizedBox(height: 4),
                          Text(bal.toStringAsFixed(2),
                              style: McText.mono(size: 16, weight: FontWeight.w700, color: color)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _account == 'income'
                ? tr('wd_income_rule')
                : tr('wd_principal_rule'),
            style: McText.sans(size: 11, color: McColors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          // 网络选择
          Text(tr('wd_network'), style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final n in (_networks.isNotEmpty
                  ? _networks
                  : [
                      {'network': 'trc20', 'label': tr('wd_net_trc20')},
                      {'network': 'erc20', 'label': tr('wd_net_erc20')},
                      {'network': 'bep20', 'label': tr('wd_net_bep20')},
                      {'network': 'arbitrum', 'label': tr('wd_net_arb')},
                    ]))
                GestureDetector(
                  onTap: () => setState(() {
                    _network = (n['network'] ?? 'trc20').toString();
                    _quote = null;
                    _doQuote();
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _network == n['network']
                          ? McColors.primaryContainer.withValues(alpha: 0.18)
                          : McColors.surfaceContainer,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _network == n['network']
                            ? McColors.primarySoft
                            : McColors.surfaceContainerHigh,
                      ),
                    ),
                    child: Text(
                      (n['label'] ?? '').toString(),
                      style: McText.sans(
                        size: 12,
                        weight: _network == n['network'] ? FontWeight.w700 : FontWeight.w400,
                        color: _network == n['network'] ? McColors.primarySoft : McColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // 金额
          Text(tr('wd_amount'), style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
          const SizedBox(height: 6),
          TextField(
            controller: _amountCtrl,
            onChanged: (_) => _doQuote(),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: McText.mono(size: 16),
            decoration: InputDecoration(
              hintText: tr('wd_available').replaceAll('{n}', avail.toStringAsFixed(2)),
              hintStyle: McText.mono(size: 13, color: McColors.onSurfaceVariant),
              filled: true,
              fillColor: McColors.surfaceContainerHigh.withValues(alpha: 0.5),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              suffix: GestureDetector(
                onTap: () {
                  _amountCtrl.text = avail > 0 ? avail.toStringAsFixed(2) : '';
                  _doQuote();
                },
                child: Text(tr('wd_all'), style: McText.sans(size: 12, color: McColors.primarySoft, weight: FontWeight.w600)),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // 地址
          Text(tr('wd_addr_label').replaceAll('{network}', _networkLabel), style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
          const SizedBox(height: 6),
          TextField(
            controller: _addrCtrl,
            style: McText.mono(size: 13),
            decoration: InputDecoration(
              hintText: _isEvm ? tr('wd_addr_hint_evm') : tr('wd_addr_hint_tron'),
              hintStyle: McText.mono(size: 13, color: McColors.onSurfaceVariant),
              filled: true,
              fillColor: McColors.surfaceContainerHigh.withValues(alpha: 0.5),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),
          // 报价
          if (_quoting)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_quote != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: McColors.surfaceContainer,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: McColors.surfaceContainerHigh),
              ),
              child: Column(
                children: [
                  _quoteRow(tr('wd_quote_amount'), '${_quote!['amount']}'),
                  _quoteRow(tr('wd_quote_service'), '-${_quote!['service_fee']}'),
                  _quoteRow(tr('wd_quote_network').replaceAll('{network}', _networkLabel), '-${_quote!['network_fee']}'),
                  const Divider(height: 14, color: McColors.outlineVariant),
                  _quoteRow(tr('wd_quote_arrive'), '${_quote!['arrive_amount']}', highlight: true),
                ],
              ),
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
                  : Text(tr('wd_submit'), style: McText.display(size: 14, weight: FontWeight.w700, color: McColors.onPrimaryContainer)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            tr('wd_note'),
            style: McText.sans(size: 11, color: McColors.onSurfaceVariant, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _quoteRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: McText.sans(size: 12, color: McColors.onSurfaceVariant))),
          Text(
            '$value USDT',
            style: McText.mono(
              size: highlight ? 15 : 12,
              weight: highlight ? FontWeight.w700 : FontWeight.w400,
              color: highlight ? McColors.goldBright : McColors.onSurface,
            ),
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

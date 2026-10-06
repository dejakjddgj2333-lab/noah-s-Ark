import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:reown_sign/reown_sign.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/api.dart';
import '../services/finance_api.dart';
import '../services/wallet_service.dart';

/// 连接钱包支付 (WalletConnect v2).
/// 流程: 连接 → 输入金额 → prepare-transfer → 钱包签名/发送 → claim 入账.
/// trc20 走 tron_signTransaction (可能需后端 broadcast);
/// erc20/bep20/arbitrum 走 eth_sendTransaction (钱包直接广播, 返回哈希).
/// 任一环节失败都降级提示手动转账 + txid 补单.
class WalletConnectPage extends StatefulWidget {
  const WalletConnectPage({super.key});

  @override
  State<WalletConnectPage> createState() => _WalletConnectPageState();
}

enum _Phase { idle, connecting, connected, paying, done }

class _WalletConnectPageState extends State<WalletConnectPage> {
  _Phase _phase = _Phase.idle;
  String _network = 'trc20'; // 充值页带入
  String? _address; // 已连接钱包地址
  String? _wcUri; // 连接中展示的 wc: uri
  final _amountCtrl = TextEditingController();
  String _status = '';
  String? _error;
  bool _argsRead = false;

  bool get _isEvm => WalletService.isEvm(_network);
  String get _networkLabel => switch (_network) {
        'erc20' => 'ERC20',
        'bep20' => 'BEP20',
        'arbitrum' => 'Arbitrum',
        _ => 'TRC20',
      };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsRead) return;
    _argsRead = true;
    final arg = ModalRoute.of(context)?.settings.arguments?.toString();
    if (arg != null &&
        (arg == 'trc20' || WalletService.isEvm(arg))) {
      _network = arg;
    }
    _restore();
  }

  Future<void> _restore() async {
    final addr = await WalletService.connectedAddress(_network);
    if (addr != null && mounted) {
      setState(() {
        _address = addr;
        _phase = _Phase.connected;
      });
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  // ---------- 连接 ----------

  Future<void> _connect() async {
    setState(() {
      _phase = _Phase.connecting;
      _error = null;
      _status = tr('wc_generating');
    });
    try {
      final (uri, sessionFuture) = await WalletService.connect(_network);
      if (!mounted) return;
      setState(() {
        _wcUri = uri?.toString();
        _status = tr('wc_waiting');
      });
      final SessionData session = await sessionFuture.timeout(
        const Duration(minutes: 2),
      );
      final ns = _isEvm ? 'eip155' : 'tron';
      final accs = session.namespaces[ns]?.accounts ?? const [];
      if (!mounted) return;
      if (accs.isEmpty) {
        setState(() {
          _phase = _Phase.idle;
          _error = tr('wc_no_account').replaceAll('{network}', _networkLabel);
        });
        return;
      }
      setState(() {
        _address = accs.first.split(':').last;
        _phase = _Phase.connected;
        _wcUri = null;
        _status = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _wcUri = null;
        _error = tr('wc_connect_failed');
      });
    }
  }

  /// 拉起指定钱包 App (wc uri 深链).
  Future<void> _openWallet(String scheme) async {
    final uri = _wcUri;
    if (uri == null) return;
    final link = '$scheme${Uri.encodeComponent(uri)}';
    try {
      await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
    } catch (_) {
      _toast(tr('wc_no_wallet'));
    }
  }

  // ---------- 支付 ----------

  Future<void> _pay() async {
    final amountText = _amountCtrl.text.trim();
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      _toast(tr('wc_err_amount'));
      return;
    }
    final owner = _address;
    if (owner == null) return;
    setState(() {
      _phase = _Phase.paying;
      _error = null;
      _status = tr('wc_building');
    });
    try {
      // 1. 后端构造未签名交易
      final prep = await FinanceApi.prepareDepositTransfer(
        ownerAddress: owner,
        amount: amountText,
        network: _network,
      );
      if (!mounted) return;

      String txid = '';
      if (_isEvm) {
        // EVM: 钱包签名并广播, 直接返回交易哈希
        setState(() => _status = tr('wc_confirm_send'));
        txid = await WalletService.sendEvmTransaction(
          network: _network,
          transaction: prep['transaction'] as Map<String, dynamic>,
        );
      } else {
        setState(() => _status = tr('wc_confirm_sign'));
        // 2. 钱包签名 (部分钱包签名后直接广播)
        final result = await WalletService.signTransaction(
          ownerAddress: owner,
          unsignedTx: prep['transaction'] as Map<String, dynamic>,
        );

        // 3. 结果分两类: 已广播 (带 txid) / 仅签名 (需后端广播)
        if (result is Map) {
          final r = result.cast<String, dynamic>();
          txid = (r['txid'] ?? r['transaction']?['txID'] ?? '').toString();
          if (txid.isEmpty) {
            if (!mounted) return;
            setState(() => _status = tr('wc_broadcasting'));
            txid = await FinanceApi.broadcastDeposit(r);
          }
        }
      }
      if (txid.isEmpty) throw StateError(tr('wc_no_result'));

      // 4. 核销入账
      if (!mounted) return;
      setState(() => _status = tr('wc_claiming'));
      final rec = await FinanceApi.claimDeposit(txid, network: _network);
      if (!mounted) return;
      final st = rec['status']?.toString();
      setState(() {
        _phase = _Phase.done;
        _status = st == 'credited'
            ? tr('wc_pay_success')
            : tr('wc_pay_onchain').replaceAll('{txid}', txid);
      });
    } on ApiException catch (e) {
      _payFail(e.message);
    } catch (e) {
      _payFail(e is StateError
          ? e.message
          : tr('wc_pay_failed'));
    }
  }

  void _payFail(String msg) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.connected;
      _error = msg;
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: McColors.surface,
      appBar: AppBar(
        backgroundColor: McColors.surface,
        title: Text(tr('wc_title'), style: McText.sans(size: 16, weight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!WalletService.available) _unavailableCard(),
          if (WalletService.available) ...[
            if (_phase == _Phase.idle || _phase == _Phase.connecting)
              _connectCard(),
            if (_phase == _Phase.connected ||
                _phase == _Phase.paying ||
                _phase == _Phase.done)
              _payCard(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            _errorBar(_error!),
          ],
        ],
      ),
    );
  }

  Widget _unavailableCard() {
    return McCard(
      color: McColors.surfaceContainer,
      borderColor: Colors.transparent,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Icon(Icons.account_balance_wallet_outlined,
              size: 40, color: McColors.outline),
          const SizedBox(height: 12),
          Text(
            tr('wc_unavailable_title'),
            style: McText.sans(size: 15, weight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            tr('wc_unavailable_body'),
            style: McText.sans(
                size: 12, color: McColors.onSurfaceVariant, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _connectCard() {
    final connecting = _phase == _Phase.connecting;
    return McCard(
      color: McColors.surfaceContainer,
      borderColor: Colors.transparent,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            tr('wc_supported'),
            style: McText.sans(size: 12, color: McColors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (!connecting)
            _primaryBtn(tr('wc_connect'), Icons.link, _connect)
          else ...[
            if (_wcUri != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(data: _wcUri!, size: 180),
              ),
            const SizedBox(height: 12),
            Text(_status,
                style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _walletBtn('Trust', () => _openWallet('trust://wc?uri=')),
                _walletBtn('SafePal', () => _openWallet('safepal://wc?uri=')),
                _walletBtn(tr('wc_copy_link'), () {
                  Clipboard.setData(ClipboardData(text: _wcUri ?? ''));
                  _toast(tr('wc_link_copied'));
                }),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _payCard() {
    final paying = _phase == _Phase.paying;
    final done = _phase == _Phase.done;
    return McCard(
      color: McColors.surfaceContainer,
      borderColor: Colors.transparent,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet,
                  size: 16, color: McColors.tertiary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _address ?? '',
                  style: McText.mono(size: 12, color: McColors.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              InkWell(
                onTap: () async {
                  await WalletService.disconnect();
                  if (mounted) {
                    setState(() {
                      _phase = _Phase.idle;
                      _address = null;
                    });
                  }
                },
                child: Text(tr('wc_disconnect'),
                    style: McText.sans(size: 12, color: McColors.bear)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!done) ...[
            TextField(
              controller: _amountCtrl,
              enabled: !paying,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: McText.mono(size: 16),
              decoration: InputDecoration(
                labelText: tr('wc_amount_label'),
                hintText: tr('wc_amount_hint'),
                border: const OutlineInputBorder(),
                suffixText: 'USDT',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr('wc_transfer_note').replaceAll('{network}', _networkLabel),
              style: McText.sans(size: 12, color: McColors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (paying)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(_status,
                        style: McText.sans(
                            size: 12, color: McColors.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              )
              else
                _primaryBtn(tr('wc_confirm_pay'), Icons.payments_outlined, _pay),
          ] else ...[
            Row(
              children: [
                const Icon(Icons.check_circle,
                    size: 28, color: McColors.tertiary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _status,
                    style: McText.sans(size: 13, height: 1.4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _primaryBtn(tr('wc_done'), Icons.done, () => Navigator.pop(context)),
          ],
        ],
      ),
    );
  }

  Widget _primaryBtn(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 44),
        decoration: BoxDecoration(
          color: McColors.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: McColors.onPrimaryContainer),
            const SizedBox(width: 6),
            Text(
              label,
              style: McText.sans(
                size: 14,
                weight: FontWeight.w600,
                color: McColors.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _walletBtn(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: McColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: McText.sans(size: 12, weight: FontWeight.w500)),
      ),
    );
  }

  Widget _errorBar(String msg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: McColors.bear.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: McColors.bear),
          const SizedBox(width: 8),
          Expanded(
            child: Text(msg,
                style: McText.sans(size: 12, color: McColors.bear, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

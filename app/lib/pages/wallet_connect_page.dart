import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:reown_sign/reown_sign.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/api.dart';
import '../services/finance_api.dart';
import '../services/wallet_service.dart';

/// 连接钱包支付 (WalletConnect v2 / TRON).
/// 流程: 连接 → 输入金额 → prepare-transfer → 钱包签名 → broadcast → claim 入账.
/// 任一环节失败都降级提示手动转账 + txid 补单.
class WalletConnectPage extends StatefulWidget {
  const WalletConnectPage({super.key});

  @override
  State<WalletConnectPage> createState() => _WalletConnectPageState();
}

enum _Phase { idle, connecting, connected, paying, done }

class _WalletConnectPageState extends State<WalletConnectPage> {
  _Phase _phase = _Phase.idle;
  String? _address; // 已连接钱包地址
  String? _wcUri; // 连接中展示的 wc: uri
  final _amountCtrl = TextEditingController();
  String _status = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final addr = await WalletService.connectedAddress();
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
      _status = '生成连接中...';
    });
    try {
      final (uri, sessionFuture) = await WalletService.connect();
      if (!mounted) return;
      setState(() {
        _wcUri = uri?.toString();
        _status = '等待钱包确认连接...';
      });
      final SessionData session = await sessionFuture.timeout(
        const Duration(minutes: 2),
      );
      final accs = session.namespaces['tron']?.accounts ?? const [];
      if (!mounted) return;
      if (accs.isEmpty) {
        setState(() {
          _phase = _Phase.idle;
          _error = '钱包未提供 TRON 账户, 请换 Trust/SafePal 重试';
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
        _error = '连接失败或被取消, 可重试或手动转账后 txid 补单';
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
      _toast('未安装对应钱包, 可用二维码扫码连接');
    }
  }

  // ---------- 支付 ----------

  Future<void> _pay() async {
    final amountText = _amountCtrl.text.trim();
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      _toast('输入有效金额');
      return;
    }
    final owner = _address;
    if (owner == null) return;
    setState(() {
      _phase = _Phase.paying;
      _error = null;
      _status = '构造交易中...';
    });
    try {
      // 1. 后端构造未签名交易
      final prep = await FinanceApi.prepareDepositTransfer(
        ownerAddress: owner,
        amount: amountText,
      );
      if (!mounted) return;
      setState(() => _status = '请在钱包中确认签名...');

      // 2. 钱包签名 (部分钱包签名后直接广播)
      final result = await WalletService.signTransaction(
        ownerAddress: owner,
        unsignedTx: prep['transaction'] as Map<String, dynamic>,
      );

      // 3. 结果分两类: 已广播 (带 txid) / 仅签名 (需后端广播)
      String txid = '';
      if (result is Map) {
        final r = result.cast<String, dynamic>();
        txid = (r['txid'] ?? r['transaction']?['txID'] ?? '').toString();
        if (txid.isEmpty) {
          if (!mounted) return;
          setState(() => _status = '广播交易中...');
          txid = await FinanceApi.broadcastDeposit(r);
        }
      }
      if (txid.isEmpty) throw StateError('钱包未返回交易结果');

      // 4. 核销入账
      if (!mounted) return;
      setState(() => _status = '核销入账中...');
      final rec = await FinanceApi.claimDeposit(txid);
      if (!mounted) return;
      final st = rec['status']?.toString();
      setState(() {
        _phase = _Phase.done;
        _status = st == 'credited'
            ? '支付成功, 已入账本金账户'
            : '支付已上链, 区块确认后自动入账 ($txid)';
      });
    } on ApiException catch (e) {
      _payFail(e.message);
    } catch (e) {
      _payFail(e is StateError
          ? e.message
          : '钱包未确认或网络错误; 若已扣款请用 txid 补单');
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
        title: Text('连接钱包支付', style: McText.sans(size: 16, weight: FontWeight.w600)),
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
            '钱包连接未启用',
            style: McText.sans(size: 15, weight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            '当前版本未配置 WalletConnect, 请返回充值页复制地址手动转账; 转账后可用 txid 补单自动入账。',
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
            '支持 Trust Wallet / SafePal / Binance Web3 等',
            style: McText.sans(size: 12, color: McColors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (!connecting)
            _primaryBtn('连接钱包', Icons.link, _connect)
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
                _walletBtn('复制链接', () {
                  Clipboard.setData(ClipboardData(text: _wcUri ?? ''));
                  _toast('连接链接已复制, 粘贴到钱包的 WalletConnect');
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
                child: Text('断开',
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
              decoration: const InputDecoration(
                labelText: '充值金额 (USDT)',
                hintText: '最小 10',
                border: OutlineInputBorder(),
                suffixText: 'USDT',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '将从您的钱包向专属充值地址转账 USDT-TRC20, 12 确认后入账',
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
                _primaryBtn('确认支付', Icons.payments_outlined, _pay),
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
            _primaryBtn('完成', Icons.done, () => Navigator.pop(context)),
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

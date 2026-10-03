import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/api.dart';
import '../services/finance_api.dart';

/// 钱包矩阵: 用户在每条链上的专属充值地址一览 + 各链累计充值.
/// 数据: GET /api/deposit/address?network=x (首次自动分配) + /records 聚合.
class WalletMatrixPage extends StatefulWidget {
  const WalletMatrixPage({super.key});

  @override
  State<WalletMatrixPage> createState() => _WalletMatrixPageState();
}

class _WalletMatrixPageState extends State<WalletMatrixPage> {
  /// 网络元数据: (标签, 链名).
  static const _meta = {
    'trc20': ('TRC20', 'Tron 主网'),
    'erc20': ('ERC20', 'Ethereum'),
    'bep20': ('BEP20', 'BNB Chain'),
    'arbitrum': ('Arbitrum', 'Arbitrum One'),
  };

  /// network → 专属地址 (null=加载中/失败占位 '').
  final Map<String, String?> _addresses = {};
  Map<String, double> _totals = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        for (final n in _meta.keys) FinanceApi.depositAddress(network: n),
        FinanceApi.depositRecords(),
      ]);
      if (!mounted) return;
      final records = results.last as List<dynamic>;
      final totals = <String, double>{};
      for (final r in records) {
        final m = r as Map<String, dynamic>;
        if (m['status']?.toString() != 'credited') continue;
        final n = m['network']?.toString() ?? 'trc20';
        totals[n] = (totals[n] ?? 0) + FinanceApi.d(m['amount']);
      }
      setState(() {
        for (var i = 0; i < _meta.length; i++) {
          final m = results[i] as Map<String, dynamic>;
          _addresses[_meta.keys.elementAt(i)] = m['address']?.toString();
        }
        _totals = totals;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('网络错误, 下拉重试');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _copy(String network) {
    final addr = _addresses[network];
    if (addr == null || addr.isEmpty) return;
    Clipboard.setData(ClipboardData(text: addr));
    _toast('${_meta[network]!.$1} 地址已复制');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: McColors.surface,
      appBar: AppBar(
        backgroundColor: McColors.surface,
        title: Text('钱包矩阵',
            style: McText.sans(size: 16, weight: FontWeight.w600)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(
              '每条链一个专属充值地址, 长期有效; 向该地址转 USDT 自动入账本金账户。',
              style: McText.sans(
                  size: 12, color: McColors.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 16),
            if (_loading && _addresses.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              for (final e in _meta.entries) ...[
                _NetworkAddrCard(
                  label: e.value.$1,
                  chain: e.value.$2,
                  address: _addresses[e.key],
                  total: _totals[e.key] ?? 0,
                  onCopy: () => _copy(e.key),
                  onDeposit: () => Navigator.pushNamed(context, '/deposit',
                      arguments: e.key),
                ),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }
}

class _NetworkAddrCard extends StatelessWidget {
  const _NetworkAddrCard({
    required this.label,
    required this.chain,
    required this.address,
    required this.total,
    required this.onCopy,
    required this.onDeposit,
  });

  final String label;
  final String chain;
  final String? address;
  final double total;
  final VoidCallback onCopy;
  final VoidCallback onDeposit;

  @override
  Widget build(BuildContext context) {
    return McCard(
      color: McColors.surfaceContainer,
      borderColor: Colors.transparent,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              McPill(label, color: McColors.primary, fontSize: 12, bold: false),
              const SizedBox(width: 8),
              Text(chain,
                  style: McText.sans(
                      size: 12, color: McColors.onSurfaceVariant)),
              const Spacer(),
              Text(
                '累计充值 ${total.toStringAsFixed(2)} USDT',
                style: McText.sans(size: 12, color: McColors.tertiary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: McColors.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(6),
            ),
            child: address == null
                ? Text('加载中...',
                    style: McText.sans(
                        size: 12, color: McColors.onSurfaceVariant))
                : SelectableText(
                    address!,
                    style: McText.mono(
                        size: 12, color: McColors.onSurface, height: 1.4),
                  ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _miniBtn('复制地址', Icons.content_copy, onCopy),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _miniBtn('去充值', Icons.input_outlined, onDeposit,
                    primary: true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniBtn(String text, IconData icon, VoidCallback onTap,
      {bool primary = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 38),
        decoration: BoxDecoration(
          color: primary
              ? McColors.primaryContainer
              : McColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: primary
                    ? McColors.onPrimaryContainer
                    : McColors.onSurface),
            const SizedBox(width: 6),
            Text(
              text,
              style: McText.sans(
                size: 12,
                weight: FontWeight.w600,
                color:
                    primary ? McColors.onPrimaryContainer : McColors.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

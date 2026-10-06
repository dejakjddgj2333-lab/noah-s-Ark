import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/api.dart';
import '../services/finance_api.dart';

/// 链上充值 (USDT-TRC20). 地址/记录全部来自后端:
/// GET /api/deposit/address | /records, POST /api/deposit/claim 补单.
/// 需求文档 V0.7 第六节: 网络一致性提示 / 错币提示 / min 10 / 12 确认.
class DepositPage extends StatefulWidget {
  const DepositPage({super.key});

  @override
  State<DepositPage> createState() => _DepositPageState();
}

class _DepositPageState extends State<DepositPage> {
  String _network = 'trc20'; // trc20|erc20|bep20|arbitrum
  String? _address;
  int _requiredConf = 12;
  double _minDeposit = 10;
  double _principalBalance = 0;
  List<dynamic> _records = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _argsRead = false;

  /// 钱包矩阵跳入时带初始网络.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsRead) return;
    _argsRead = true;
    final arg = ModalRoute.of(context)?.settings.arguments?.toString();
    if (arg != null && networkMeta.containsKey(arg) && arg != _network) {
      setState(() => _network = arg);
      _load();
    }
  }

  /// 切网络重拉地址+记录 (余额不依赖网络, 一并刷新).
  void _switchNetwork(String network) {
    if (network == _network) return;
    setState(() => _network = network);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        FinanceApi.depositAddress(network: _network),
        FinanceApi.depositRecords(),
        FinanceApi.account(),
      ]);
      if (!mounted) return;
      final addr = results[0] as Map<String, dynamic>;
      setState(() {
        _address = addr['address']?.toString();
        _requiredConf = _toInt(addr['required_confirmations'], 12);
        _minDeposit = FinanceApi.d(addr['min_deposit']);
        _records = results[1] as List<dynamic>;
        _principalBalance =
            FinanceApi.d((results[2] as Map)['principal_balance']);
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = tr('net_error_retry');
      });
    }
  }

  static int _toInt(dynamic v, int fallback) =>
      int.tryParse(v?.toString() ?? '') ?? fallback;

  /// 网络展示元数据: (标签, 链名 key, 速度说明 key). 显示时 tr().
  static const networkMeta = {
    'trc20': ('TRC20', 'dep_chain_tron', 'dep_speed_fast'),
    'erc20': ('ERC20', 'dep_chain_eth', 'dep_speed_slow'),
    'bep20': ('BEP20', 'dep_chain_bnb', 'dep_speed_fast'),
    'arbitrum': ('Arbitrum', 'dep_chain_arb', 'dep_speed_fast'),
  };

  String get _networkLabel => networkMeta[_network]?.$1 ?? _network;

  void _copyAddress() {
    final addr = _address;
    if (addr == null) return;
    Clipboard.setData(ClipboardData(text: addr));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr('dep_addr_copied'))));
  }

  /// 规则说明弹窗 (文档第六节口径).
  void _showRules() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: McColors.surfaceContainer,
        title: Text(tr('dep_rules_title'), style: McText.sans(size: 16, weight: FontWeight.w600)),
        content: Text(
          '${tr('dep_rules_1').replaceAll('{network}', _networkLabel)}\n\n'
          '${tr('dep_rules_2').replaceAll('{min}', _minDeposit.toStringAsFixed(0))}\n\n'
          '${tr('dep_rules_3').replaceAll('{conf}', '$_requiredConf')}\n\n'
          '${tr('dep_rules_4')}',
          style: McText.sans(size: 13, color: McColors.onSurfaceVariant, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('dep_got_it')),
          ),
        ],
      ),
    );
  }

  /// txid 补单弹窗.
  void _showClaim() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: McColors.surfaceContainer,
        title: Text(tr('dep_claim_title'), style: McText.sans(size: 16, weight: FontWeight.w600)),
        content: TextField(
          controller: ctrl,
          style: McText.mono(size: 12),
          decoration: InputDecoration(
            hintText: tr('dep_claim_hint'),
            border: const OutlineInputBorder(),
          ),
          maxLines: 2,
          minLines: 1,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _doClaim(ctrl.text.trim());
            },
            child: Text(tr('dep_claim_submit')),
          ),
        ],
      ),
    );
  }

  Future<void> _doClaim(String txid) async {
    if (txid.isEmpty) return;
    try {
      final rec = await FinanceApi.claimDeposit(txid, network: _network);
      if (!mounted) return;
      final status = rec['status']?.toString() ?? '';
      final msg = switch (status) {
        'credited' => tr('dep_claim_credited'),
        'confirming' => tr('dep_claim_confirming')
            .replaceAll('{conf}', '${rec['confirmations']}')
            .replaceAll('{req}', '${rec['required_confirmations']}'),
        'unmatched' => tr('dep_claim_unmatched'),
        _ => tr('dep_claim_submitted').replaceAll('{status}', status),
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
      _load(); // 刷新记录
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('net_error_retry'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: McColors.surface,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: _DepositAppBar(onRules: _showRules),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
          children: [
            const _SecurityBar(),
            const SizedBox(height: 20),
            _AssetCard(balance: _principalBalance),
            const SizedBox(height: 20),
            _NetworkCard(
              minDeposit: _minDeposit,
              requiredConf: _requiredConf,
              network: _network,
              onSelect: _switchNetwork,
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _ErrorCard(message: _error!, onRetry: _load)
            else
              _QrCard(
                address: _address ?? '',
                networkLabel: _networkLabel,
                onCopy: _copyAddress,
              ),
            const SizedBox(height: 20),
            const _RadarBar(),
            const SizedBox(height: 20),
            _RecordsCard(records: _records),
            const SizedBox(height: 16),
            _FooterActions(
              onClaim: _showClaim,
              onWalletPay: () => Navigator.pushNamed(
                context,
                '/wallet-connect',
                arguments: _network,
              ),
              network: _network,
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom app bar: back + title(WEB3) + 规则说明.
class _DepositAppBar extends StatelessWidget {
  const _DepositAppBar({required this.onRules});

  final VoidCallback onRules;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: McColors.surface.withValues(alpha: 0.85),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 1)),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                InkWell(
                  onTap: () => Navigator.maybePop(context),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: McColors.surfaceContainerHigh.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_back,
                        size: 18, color: McColors.onSurface),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          tr('dep_title'),
                          style: McText.sans(
                            size: 16,
                            weight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const McPill('WEB3',
                          color: McColors.primary, fontSize: 12, bold: false),
                    ],
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: onRules,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: McColors.surfaceContainerHigh.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.help_outline,
                            size: 16, color: McColors.primary),
                        const SizedBox(width: 4),
                        Text(tr('dep_rules'),
                            style: McText.sans(
                                size: 12, weight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 1. Security bar: 链上自动入账说明 (不写未证实的审计宣传).
class _SecurityBar extends StatelessWidget {
  const _SecurityBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: McColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user, size: 16, color: McColors.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              tr('dep_security_note'),
              style: McText.sans(size: 12, color: McColors.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// 2. Asset card: 仅 USDT + 真实本金余额.
class _AssetCard extends StatelessWidget {
  const _AssetCard({required this.balance});

  final double balance;

  @override
  Widget build(BuildContext context) {
    return McCard(
      color: McColors.surfaceContainer,
      borderColor: Colors.transparent,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                tr('dep_asset_title'),
                style: McText.sans(
                  size: 12,
                  weight: FontWeight.w500,
                  color: McColors.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
              Row(
                children: [
                  Text(tr('dep_principal_balance'),
                      style: McText.sans(
                          size: 12, color: McColors.onSurfaceVariant)),
                  const SizedBox(width: 6),
                  Text(
                    '${balance.toStringAsFixed(2)} USDT',
                    style: McText.sans(
                        size: 13, weight: FontWeight.w600, color: McColors.onSurface),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: McColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF26A17B).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    '₮',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF26A17B),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'USDT',
                            style: McText.sans(
                                size: 18,
                                weight: FontWeight.w600,
                                letterSpacing: -0.2),
                          ),
                          const SizedBox(width: 6),
                          const McChip('Tether USD'),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tr('dep_asset_sub'),
                        style: McText.sans(
                            size: 12, color: McColors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 3. Network card: 四网可选 (trc20/erc20/bep20/arbitrum).
class _NetworkCard extends StatelessWidget {
  const _NetworkCard({
    required this.minDeposit,
    required this.requiredConf,
    required this.network,
    required this.onSelect,
  });

  final double minDeposit;
  final int requiredConf;
  final String network;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return McCard(
      color: McColors.surfaceContainer,
      borderColor: Colors.transparent,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                tr('dep_network_title'),
                style: McText.sans(
                  size: 12,
                  weight: FontWeight.w500,
                  color: McColors.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.info_outline, size: 14, color: McColors.outline),
            ],
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            padding: EdgeInsets.zero, // 防 primary 滚动视图自动吃状态栏 inset
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.0,
            children: [
              for (final e in _DepositPageState.networkMeta.entries)
                _NetworkTile(
                  name: e.value.$1,
                  tag: e.key == 'trc20' ? tr('dep_recommended') : null,
                  tagColor: McColors.tertiary,
                  chain: tr(e.value.$2),
                  speed: tr(e.value.$3),
                  speedColor: e.key == 'erc20'
                      ? McColors.onSurfaceVariant
                      : McColors.primary,
                  selected: network == e.key,
                  onTap: () => onSelect(e.key),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Params strip (真值)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: McColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                _param(
                    tr('dep_eta'),
                    tr(_DepositPageState.networkMeta[network]?.$3 ??
                        'dep_speed_fast'),
                    McColors.onSurface),
                _param(tr('dep_min_deposit'), '${minDeposit.toStringAsFixed(0)} USDT',
                    McColors.onSurface),
                _param(tr('dep_confirmations'),
                    tr('dep_conf_blocks').replaceAll('{n}', '$requiredConf'),
                    McColors.tertiary),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _param(String label, String value, Color valueColor) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(
            value,
            style: McText.sans(
                size: 12, weight: FontWeight.w600, color: valueColor),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _NetworkTile extends StatelessWidget {
  const _NetworkTile({
    required this.name,
    required this.chain,
    required this.speed,
    required this.speedColor,
    this.tag,
    this.tagColor = McColors.tertiary,
    this.selected = false,
    this.onTap,
  });

  final String name;
  final String? tag;
  final Color tagColor;
  final String chain;
  final String speed;
  final Color speedColor;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected
              ? McColors.primaryContainer.withValues(alpha: 0.2)
              : McColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: selected
              ? Border.all(color: McColors.primaryContainer.withValues(alpha: 0.5))
              : null,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: McColors.primaryContainer.withValues(alpha: 0.18),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: McText.sans(
                            size: 15,
                            weight: selected ? FontWeight.w700 : FontWeight.w500,
                            letterSpacing: -0.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (tag != null) ...[
                        const SizedBox(width: 6),
                        McPill(tag!, color: tagColor, fontSize: 12, bold: false),
                      ],
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle,
                      size: 18, color: McColors.primary),
              ],
            ),
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: selected
                        ? McColors.primaryContainer.withValues(alpha: 0.2)
                        : McColors.surfaceContainerHighest.withValues(alpha: 0.3),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(chain,
                        style: McText.sans(
                            size: 12, color: McColors.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Text(
                    speed,
                    style: McText.sans(
                        size: 12, weight: FontWeight.w600, color: speedColor),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 4. QR + 地址卡 (真二维码, 复制可用).
class _QrCard extends StatelessWidget {
  const _QrCard({
    required this.address,
    required this.networkLabel,
    required this.onCopy,
  });

  final String address;
  final String networkLabel;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 16)],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    tr('dep_receive_addr'),
                    style: McText.sans(
                      size: 12,
                      weight: FontWeight.w500,
                      color: McColors.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  McPill(networkLabel,
                      color: McColors.primary, fontSize: 12, bold: false),
                ],
              ),
              Row(
                children: [
                  const McGlowDot(color: McColors.tertiary, size: 8),
                  const SizedBox(width: 6),
                  Text(
                    tr('dep_long_term'),
                    style: McText.sans(
                        size: 12, weight: FontWeight.w500, color: McColors.tertiary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 4))
              ],
            ),
            child: QrImageView(
              data: address,
              version: QrVersions.auto,
              size: 160,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square, color: Color(0xFF0B0E14)),
              dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF0B0E14)),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.touch_app, size: 15, color: McColors.primary),
              const SizedBox(width: 4),
              Text(
                tr('dep_scan_hint'),
                style: McText.sans(size: 12, color: McColors.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Address block
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: McColors.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Text('$networkLabel ${tr('dep_receive_suffix')}',
                        style: McText.sans(
                            size: 12, color: McColors.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: McColors.surfaceContainerHighest.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectableText(
                    address,
                    style: McText.mono(
                      size: 12,
                      weight: FontWeight.w500,
                      color: McColors.onSurface,
                      letterSpacing: 0.5,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Copy button
          InkWell(
            onTap: onCopy,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              decoration: BoxDecoration(
                color: McColors.primaryContainer,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: McColors.primaryContainer.withValues(alpha: 0.35),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.content_copy,
                      size: 18, color: McColors.onPrimaryContainer),
                  const SizedBox(width: 6),
                  Text(
                    tr('dep_copy_addr'),
                    style: McText.sans(
                      size: 12,
                      weight: FontWeight.w600,
                      color: McColors.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Warning (文档第六节: 网络一致 + 仅 USDT)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: McColors.error.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.info_outline,
                      size: 15, color: McColors.error),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: McText.sans(
                          size: 12,
                          color: const Color(0xFFFFDAD6),
                          height: 1.4),
                      children: [
                        TextSpan(text: tr('dep_warn_prefix')),
                        TextSpan(
                          text: networkLabel,
                          style: McText.sans(
                              size: 12,
                              weight: FontWeight.w600,
                              color: McColors.error),
                        ),
                        TextSpan(text: tr('dep_warn_suffix')),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 5. 监听状态条 (真实口径: 30s 轮询 + 12 确认).
class _RadarBar extends StatelessWidget {
  const _RadarBar();

  @override
  Widget build(BuildContext context) {
    return McCard(
      color: McColors.surfaceContainer,
      borderColor: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: McColors.tertiary.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.radar, size: 16, color: McColors.tertiary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('dep_radar_title'),
                  style: McText.sans(size: 13, weight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  tr('dep_radar_sub'),
                  style: McText.sans(size: 12, color: McColors.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.sensors, size: 18, color: McColors.outline),
        ],
      ),
    );
  }
}

/// 6. 充值记录 (真数据).
class _RecordsCard extends StatelessWidget {
  const _RecordsCard({required this.records});

  final List<dynamic> records;

  @override
  Widget build(BuildContext context) {
    return McCard(
      color: McColors.surfaceContainer,
      borderColor: Colors.transparent,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    tr('dep_recent_records'),
                    style: McText.sans(
                      size: 12,
                      weight: FontWeight.w500,
                      color: McColors.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                    decoration: BoxDecoration(
                      color: McColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('${records.length}',
                        style: McText.mono(size: 12, color: McColors.onSurface)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (records.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                tr('dep_no_records'),
                style: McText.sans(size: 12, color: McColors.onSurfaceVariant),
              ),
            )
          else
            ...[
              for (final r in records.take(10)) ...[
                _RecordTile(record: r as Map<String, dynamic>),
                const SizedBox(height: 8),
              ],
            ],
        ],
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});

  final Map<String, dynamic> record;

  static String _shortTxid(String txid) =>
      txid.length > 12 ? '${txid.substring(0, 6)}...${txid.substring(txid.length - 4)}' : txid;

  @override
  Widget build(BuildContext context) {
    final amount = FinanceApi.d(record['amount']);
    final txid = record['txid']?.toString() ?? '';
    final status = record['status']?.toString() ?? '';
    final conf = int.tryParse(record['confirmations']?.toString() ?? '') ?? 0;
    final reqConf =
        int.tryParse(record['required_confirmations']?.toString() ?? '') ?? 12;
    final time = FinanceApi.time(record['block_time']);

    final (label, color, sub) = switch (status) {
      'credited' => (
          tr('dep_status_credited'),
          McColors.tertiary,
          tr('dep_conf_only').replaceAll('{n}', '$reqConf')
        ),
      'confirming' => (
          tr('dep_status_confirming'),
          McColors.goldBright,
          tr('dep_conf_progress').replaceAll('{c}', '$conf').replaceAll('{r}', '$reqConf')
        ),
      'unmatched' => (
          tr('dep_status_unmatched'),
          McColors.bear,
          tr('dep_below_min')
        ),
      _ => (status, McColors.outline, ''),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: McColors.tertiary.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.call_received,
                      size: 16, color: McColors.tertiary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '+${amount.toStringAsFixed(2)} USDT',
                            style: McText.sans(
                                size: 14, weight: FontWeight.w600),
                          ),
                          const SizedBox(width: 6),
                          McChip(
                              _DepositPageState.networkMeta[record['network']]
                                      ?.$1 ??
                                  (record['network']?.toString().toUpperCase() ??
                                      ''),
                              color: McColors.onSurfaceVariant),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('$time · TXID: ${_shortTxid(txid)}',
                          style: McText.sans(
                              size: 12, color: McColors.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  label,
                  style: McText.sans(
                      size: 12, weight: FontWeight.w600, color: color),
                ),
              ),
              const SizedBox(height: 2),
              Text(sub,
                  style: McText.sans(size: 12, color: McColors.outline)),
            ],
          ),
        ],
      ),
    );
  }
}

/// 底部: 钱包支付 + txid 补单 + tronscan 链接.
class _FooterActions extends StatelessWidget {
  const _FooterActions({
    required this.onClaim,
    required this.onWalletPay,
    required this.network,
  });

  final VoidCallback onClaim;
  final VoidCallback onWalletPay;
  final String network;

  static const _explorers = {
    'trc20': 'https://tronscan.org',
    'erc20': 'https://etherscan.io',
    'bep20': 'https://bscscan.com',
    'arbitrum': 'https://arbiscan.io',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onWalletPay,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            decoration: BoxDecoration(
              color: McColors.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: McColors.primaryContainer.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.account_balance_wallet_outlined,
                    size: 18, color: McColors.primary),
                const SizedBox(width: 6),
                Text(
                  tr('dep_wallet_pay'),
                  style: McText.sans(
                    size: 12,
                    weight: FontWeight.w600,
                    color: McColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            InkWell(
              onTap: onClaim,
              child: Text(
                tr('dep_claim_link'),
                style: McText.sans(
                  size: 12,
                  weight: FontWeight.w500,
                  color: McColors.primary,
                ),
              ),
            ),
            const SizedBox(width: 16),
            InkWell(
              onTap: () => launchUrl(
                  Uri.parse(_explorers[network] ?? 'https://tronscan.org'),
                  mode: LaunchMode.externalApplication),
              child: Text(
                tr('dep_explorer'),
                style: McText.sans(
                  size: 12,
                  weight: FontWeight.w500,
                  color: McColors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return McCard(
      color: McColors.surfaceContainer,
      borderColor: Colors.transparent,
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(message,
              style: McText.sans(size: 13, color: McColors.onSurfaceVariant),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: Text(tr('news_retry'))),
        ],
      ),
    );
  }
}

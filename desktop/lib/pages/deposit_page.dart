import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/kit.dart';

/// 充值页: 网络选择 + 充值地址(复制) + 自助补单 + 充值记录。
/// 镜像 web-terminal/src/views/Deposit.vue。
class DepositPage extends StatefulWidget {
  const DepositPage({super.key});
  @override
  State<DepositPage> createState() => _DepositPageState();
}

class _DepositPageState extends State<DepositPage> {
  static const _networks = ['trc20', 'erc20', 'bep20', 'arbitrum'];
  static const _netLabel = {
    'trc20': 'TRC20 · Tron',
    'erc20': 'ERC20 · Ethereum',
    'bep20': 'BEP20 · BSC',
    'arbitrum': 'Arbitrum One',
  };
  static const _netBadge = {
    'trc20': 'TRON',
    'erc20': 'ETH',
    'bep20': 'BSC',
    'arbitrum': 'ARB',
  };

  String _network = 'trc20';
  Map<String, dynamic>? _addr;
  bool _addrLoading = false;

  List<dynamic> _records = const [];
  bool _recLoading = true;
  bool _recError = false;
  bool _bootLoading = true;

  final _txidCtrl = TextEditingController();
  bool _claiming = false;
  String _claimError = '';
  String _claimOk = '';

  bool _copied = false;
  Timer? _copyTimer;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    // 30s 轮询充值记录
    _pollTimer = Timer.periodic(
        const Duration(seconds: 30), (_) => _loadRecords(quiet: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _copyTimer?.cancel();
    _txidCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await Future.wait([_loadAddress(), _loadRecords()]);
    if (mounted) setState(() => _bootLoading = false);
  }

  Future<void> _loadAddress() async {
    setState(() {
      _addrLoading = true;
      _addr = null;
    });
    try {
      final d = await ApiClient.I.depositAddress(_network);
      _addr = d is Map ? Map<String, dynamic>.from(d) : null;
    } catch (_) {
      _addr = null;
    }
    if (mounted) setState(() => _addrLoading = false);
  }

  Future<void> _loadRecords({bool quiet = false}) async {
    if (!quiet && mounted) {
      setState(() {
        _recLoading = true;
        _recError = false;
      });
    }
    try {
      final d = await ApiClient.I.depositRecords();
      _records = d is List ? d : const [];
      if (mounted) {
        setState(() {
          _recLoading = false;
          _recError = false;
        });
      }
    } catch (_) {
      // 静默, 保留旧数据; 仅首次非静默加载标记错误
      if (mounted && !quiet) {
        setState(() {
          _recLoading = false;
          _recError = _records.isEmpty;
        });
      }
    }
  }

  void _switchNet(String n) {
    if (_network == n) return;
    setState(() {
      _network = n;
      _copied = false;
    });
    _loadAddress();
  }

  Future<void> _copyAddr() async {
    final a = _addr?['address']?.toString();
    if (a == null || a.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: a));
    if (!mounted) return;
    setState(() => _copied = true);
    _copyTimer?.cancel();
    _copyTimer =
        Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Mc.cardHigh,
      behavior: SnackBarBehavior.floating,
      width: 260,
      content: Text('充值地址已复制', style: Mc.body(12)),
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _submitClaim() async {
    setState(() {
      _claimError = '';
      _claimOk = '';
    });
    final txid = _txidCtrl.text.trim();
    if (txid.isEmpty) {
      setState(() => _claimError = '请输入链上交易哈希 (txid)');
      return;
    }
    setState(() => _claiming = true);
    try {
      await ApiClient.I.depositClaim(txid, _network);
      _txidCtrl.clear();
      if (mounted) setState(() => _claimOk = '补单已提交, 等待后台核对入账');
      _loadRecords(quiet: true);
    } catch (e) {
      if (mounted) {
        setState(() =>
            _claimError = e is ApiException ? e.message : '补单失败');
      }
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  // ---------- 工具 ----------
  static String _time16(dynamic v) {
    final t = Fmt.parseServerTime(v);
    if (t == null) return '--';
    String p(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${p(t.month)}-${p(t.day)} ${p(t.hour)}:${p(t.minute)}';
  }

  static String _cut(dynamic v) {
    if (v == null) return '--';
    final s = v.toString();
    if (s.length <= 16) return s;
    return '${s.substring(0, 8)}…${s.substring(s.length - 6)}';
  }

  static Widget _statusBadge(String? s) {
    switch (s) {
      case 'confirming':
        return const McBadge('确认中', color: Mc.amber);
      case 'credited':
        return const McBadge('已入账', color: Mc.bull);
      case 'unmatched':
        return const McBadge('无法匹配', color: Mc.bear);
      default:
        return McBadge(s?.isNotEmpty == true ? s! : '--', color: Mc.muted);
    }
  }

  // ---------- 布局 ----------
  @override
  Widget build(BuildContext context) {
    if (_bootLoading) return const McLoading(label: '数据加载中');
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildAddressCard(),
            const SizedBox(height: 20),
            _buildClaimCard(),
            const SizedBox(height: 20),
            _buildRecordsCard(),
          ]),
        ),
      ),
    );
  }

  // ---------- 充值地址卡 ----------
  Widget _buildAddressCard() {
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
            child: McSection('充值', tag: 'DEPOSIT · USDT 选择网络后向地址转账'),
          ),
          _netTabs(),
        ]),
        const SizedBox(height: 16),
        if (_addrLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: McLoading(label: '地址获取中'),
          )
        else if (_addr != null) ...[
          _addressBox(),
          const SizedBox(height: 12),
          _infoTiles(),
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text('该网络暂不支持充值, 请切换其他网络',
                  style: Mc.mono(12, color: Mc.muted)),
            ),
          ),
      ]),
    );
  }

  Widget _netTabs() => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Mc.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Mc.hairline),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final n in _networks) _netTab(n),
        ]),
      );

  Widget _netTab(String n) {
    final sel = _network == n;
    return InkWell(
      onTap: () => _switchNet(n),
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: sel ? Mc.cardHigh : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(n.toUpperCase(),
            style: Mc.mono(11,
                w: sel ? FontWeight.w700 : FontWeight.w500,
                color: sel ? Mc.ink : Mc.muted)),
      ),
    );
  }

  Widget _addressBox() {
    final a = _addr!['address']?.toString() ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Mc.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Mc.hairline),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            McTag('充值地址 · ${_netLabel[_network] ?? _network}'),
            const SizedBox(height: 6),
            SelectableText(a,
                style: Mc.mono(14, w: FontWeight.w600)),
          ]),
        ),
        const SizedBox(width: 12),
        McButton(_copied ? '已复制' : '复制地址',
            kind: McBtnKind.ghost,
            icon: _copied ? Icons.check : Icons.copy,
            height: 34,
            onPressed: _copyAddr),
      ]),
    );
  }

  Widget _infoTiles() {
    return McRow(gap: 16, children: [
      _infoTile('最小充值额', value: '${Fmt.num_(_addr!['min_deposit'])} USDT'),
      _infoTile('所需确认数',
          value: '${_addr!['required_confirmations'] ?? '--'} 个区块'),
      _infoTile('入账说明', note: '低于最小额度将无法入账', noteColor: Mc.amber),
    ]);
  }

  Widget _infoTile(String label, {String? value, String? note, Color? noteColor}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Mc.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Mc.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        McTag(label),
        const SizedBox(height: 6),
        if (value != null)
          Text(value, style: Mc.mono(14, w: FontWeight.w600))
        else
          Row(children: [
            Icon(Icons.info_outline, size: 13, color: noteColor ?? Mc.muted),
            const SizedBox(width: 4),
            Flexible(
              child: Text(note ?? '--',
                  style: Mc.mono(11, color: noteColor ?? Mc.muted)),
            ),
          ]),
      ]),
    );
  }

  // ---------- 自助补单 ----------
  Widget _buildClaimCard() {
    return McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.restore, size: 17, color: Mc.cobaltSoft),
          const SizedBox(width: 8),
          Text('链上已转未到账? 自助补单',
              style: Mc.body(14, w: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        Text('若链上转账已成功但长时间未入账, 请填写交易哈希 (txid) 提交补单, 系统将自动核对。',
            style: Mc.body(12, color: Mc.muted)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: McInput(
              controller: _txidCtrl,
              hint: '输入 txid (交易哈希)',
              prefix: Icons.tag,
              onSubmitted: (_) => _submitClaim(),
            ),
          ),
          const SizedBox(width: 10),
          McButton(_claiming ? '提交中' : '提交补单',
              busy: _claiming, height: 40, onPressed: _submitClaim),
        ]),
        if (_claimError.isNotEmpty) ...[
          const SizedBox(height: 8),
          _msgRow(Icons.error_outline, _claimError, Mc.bear),
        ] else if (_claimOk.isNotEmpty) ...[
          const SizedBox(height: 8),
          _msgRow(Icons.check_circle_outline, _claimOk, Mc.bull),
        ],
      ]),
    );
  }

  Widget _msgRow(IconData icon, String text, Color color) => Row(children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Flexible(child: Text(text, style: Mc.mono(11, color: color))),
      ]);

  // ---------- 充值记录 ----------
  Widget _buildRecordsCard() {
    return McCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 12, 12),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Mc.hairline))),
          child: Row(children: [
            const Expanded(child: McSection('充值记录', tag: 'DEPOSIT HISTORY')),
            McButton('刷新',
                kind: McBtnKind.ghost,
                icon: Icons.refresh,
                height: 30,
                onPressed: () => _loadRecords()),
          ]),
        ),
        _recordsBody(),
      ]),
    );
  }

  Widget _recordsBody() {
    if (_recLoading) {
      return const SizedBox(height: 140, child: McLoading());
    }
    if (_recError) {
      return SizedBox(
          height: 140,
          child: McError('充值记录加载失败', onRetry: () => _loadRecords()));
    }
    if (_records.isEmpty) {
      return const SizedBox(height: 100, child: McEmpty('暂无充值记录'));
    }
    return Column(children: [
      _headRow(const [
        _Th('时间', flex: 3),
        _Th('网络', flex: 2, align: TextAlign.center),
        _Th('金额', flex: 3, align: TextAlign.right),
        _Th('确认数', flex: 2, align: TextAlign.center),
        _Th('状态', flex: 2, align: TextAlign.center),
        _Th('交易哈希', flex: 3, align: TextAlign.right),
      ]),
      for (final r in _records)
        if (r is Map) _recordRow(Map<String, dynamic>.from(r)),
    ]);
  }

  Widget _recordRow(Map<String, dynamic> r) {
    final net = r['network']?.toString() ?? '';
    final txid = r['txid']?.toString() ?? '';
    return _HoverRow(cells: [
      _cell(
          Text(_time16(r['block_time'] ?? r['credited_at']),
              style: Mc.mono(11, color: Mc.muted)),
          flex: 3),
      _cell(
          Center(child: McBadge(_netBadge[net] ?? net.toUpperCase())),
          flex: 2),
      _cell(
          Text('${Fmt.num_(r['amount'])} USDT',
              textAlign: TextAlign.right,
              style: Mc.mono(12, w: FontWeight.w600)),
          flex: 3),
      _cell(
          Text(
              '${r['confirmations'] ?? 0}/${r['required_confirmations'] ?? '--'}',
              textAlign: TextAlign.center,
              style: Mc.mono(11, color: Mc.muted)),
          flex: 2),
      _cell(Center(child: _statusBadge(r['status']?.toString())), flex: 2),
      _cell(
          Tooltip(
            message: txid,
            child: Text(_cut(txid),
                textAlign: TextAlign.right,
                style: Mc.mono(11, color: Mc.muted)),
          ),
          flex: 3),
    ]);
  }

  Widget _headRow(List<_Th> ths) => Container(
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Mc.hairline))),
        child: Row(children: [
          for (final t in ths)
            Expanded(flex: t.flex, child: McTh(t.text, align: t.align)),
        ]),
      );

  Widget _cell(Widget child, {int flex = 1}) => Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: child,
        ),
      );
}

/// 表头描述。
class _Th {
  const _Th(this.text, {this.flex = 1, this.align = TextAlign.left});
  final String text;
  final int flex;
  final TextAlign align;
}

/// 表格数据行: Hairline 底部分隔, 悬停 Mc.cardHigh (禁斑马纹)。
class _HoverRow extends StatefulWidget {
  const _HoverRow({required this.cells});
  final List<Widget> cells;
  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: _hover ? Mc.cardHigh : Colors.transparent,
            border:
                const Border(bottom: BorderSide(color: Mc.hairline, width: 0.6)),
          ),
          child: Row(children: widget.cells),
        ),
      );
}

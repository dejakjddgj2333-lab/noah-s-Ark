import 'package:reown_core/reown_core.dart' show PairingMetadata;
import 'package:reown_sign/reown_sign.dart';

/// WalletConnect v2 (Reown Sign) 连接: TRON + EVM 三网.
///
/// AppKit Flutter 不支持 TRON, 用底层 sign client 直连:
/// - trc20: namespace `tron`, chain `tron:0x2b6653dc`, tron_signTransaction
/// - erc20/bep20/arbitrum: namespace `eip155`, eth_sendTransaction (钱包广播)
/// projectId 走 --dart-define=WC_PROJECT_ID (cloud.reown.com 免费注册);
/// 为空则钱包连接不可用, 充值页降级为地址 + txid 补单.
class WalletService {
  WalletService._();

  /// WalletConnect projectId (公开 dapp id, 非密钥). dart-define 可覆盖.
  static const String projectId = String.fromEnvironment(
    'WC_PROJECT_ID',
    defaultValue: '467a3a5ae7a21119046c7d23818dd11d',
  );
  static bool get available => projectId.isNotEmpty;

  static const tronChain = 'tron:0x2b6653dc'; // TRON 主网 CAIP-2

  /// network → EVM CAIP-2 chain (eip155:chain_id).
  static const evmChains = {
    'erc20': 'eip155:1',
    'bep20': 'eip155:56',
    'arbitrum': 'eip155:42161',
  };

  static bool isEvm(String network) => evmChains.containsKey(network);

  static Map<String, RequiredNamespace> _namespacesFor(String network) {
    if (isEvm(network)) {
      return {
        'eip155': RequiredNamespace(
          chains: [evmChains[network]!],
          methods: ['eth_sendTransaction'],
          events: ['chainChanged', 'accountsChanged'],
        ),
      };
    }
    return {
      'tron': RequiredNamespace(
        chains: [tronChain],
        methods: ['tron_signTransaction', 'tron_signMessage'],
        events: [],
      ),
    };
  }

  static ReownSignClient? _client;

  static Future<ReownSignClient> _ensureClient() async {
    final existing = _client;
    if (existing != null) return existing;
    final client = await ReownSignClient.createInstance(
      projectId: projectId,
      metadata: const PairingMetadata(
        name: '明策 MINGCE',
        description: '明策 · 链上充值',
        url: 'https://shipapi.bdxapi.com',
        icons: [],
      ),
    );
    _client = client;
    return client;
  }

  /// 会话中匹配 network 命名空间的账户 (tron:...:addr / eip155:N:0x...).
  static List<String> _accountsFor(SessionData s, String network) =>
      s.namespaces[isEvm(network) ? 'eip155' : 'tron']?.accounts ?? const [];

  /// 已连接的钱包地址 (重进页面恢复会话).
  static Future<String?> connectedAddress(String network) async {
    if (!available) return null;
    try {
      final client = await _ensureClient();
      for (final s in client.sessions.getAll()) {
        final accs = _accountsFor(s, network);
        if (accs.isNotEmpty) return accs.first.split(':').last;
      }
    } catch (_) {/* 静默 */}
    return null;
  }

  /// 发起连接: 返回 (wc uri, session future). 调用方展示二维码/拉起钱包.
  static Future<(Uri?, Future<SessionData>)> connect(String network) async {
    final client = await _ensureClient();
    final resp =
        await client.connect(requiredNamespaces: _namespacesFor(network));
    return (resp.uri, resp.session.future);
  }

  /// 断开会话.
  static Future<void> disconnect() async {
    final client = _client;
    if (client == null) return;
    for (final s in client.sessions.getAll()) {
      try {
        await client.disconnect(
          topic: s.topic,
          reason: const ReownSignError(code: 6000, message: 'user disconnected'),
        );
      } catch (_) {/* 静默 */}
    }
  }

  static SessionData _sessionFor(String network, String ownerAddress) {
    final client = _client ?? (throw StateError('未连接钱包'));
    SessionData? session;
    for (final s in client.sessions.getAll()) {
      if (_accountsFor(s, network).any((a) =>
          a.toLowerCase().endsWith(ownerAddress.toLowerCase()))) {
        session = s;
        break;
      }
    }
    session ??= client.sessions.getAll().firstOrNull;
    if (session == null) throw StateError('未连接钱包');
    return session;
  }

  /// TRC20: 请求钱包签名转账. 返回钱包响应 (签名交易 json 或含 txid).
  static Future<dynamic> signTransaction({
    required String ownerAddress,
    required Map<String, dynamic> unsignedTx,
  }) async {
    final client = _client ?? (throw StateError('未连接钱包'));
    final session = _sessionFor('trc20', ownerAddress);
    return client.request(
      topic: session.topic,
      chainId: tronChain,
      request: SessionRequestParams(
        method: 'tron_signTransaction',
        params: {'address': ownerAddress, 'transaction': unsignedTx},
      ),
    );
  }

  /// EVM: eth_sendTransaction, 钱包签名并广播, 返回交易哈希 (0x...).
  static Future<String> sendEvmTransaction({
    required String network,
    required Map<String, dynamic> transaction,
  }) async {
    final client = _client ?? (throw StateError('未连接钱包'));
    final from = transaction['from']?.toString() ?? '';
    final session = _sessionFor(network, from);
    final result = await client.request(
      topic: session.topic,
      chainId: evmChains[network]!,
      request: SessionRequestParams(
        method: 'eth_sendTransaction',
        params: [transaction],
      ),
    );
    final hash = result?.toString() ?? '';
    if (hash.isEmpty) throw StateError('钱包未返回交易哈希');
    return hash;
  }
}

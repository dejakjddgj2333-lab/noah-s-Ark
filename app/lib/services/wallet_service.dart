import 'package:reown_core/reown_core.dart' show PairingMetadata;
import 'package:reown_sign/reown_sign.dart';

/// WalletConnect v2 (Reown Sign) TRON 连接.
///
/// AppKit Flutter 不支持 TRON, 用底层 sign client 直连:
/// namespace `tron`, 主网 chain `tron:0x2b6653dc`, 方法 tron_signTransaction.
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
  static const _tronNamespace = {
    'tron': RequiredNamespace(
      chains: [tronChain],
      methods: ['tron_signTransaction', 'tron_signMessage'],
      events: [],
    ),
  };

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

  /// 已连接的 TRON 地址 (重进页面恢复会话).
  static Future<String?> connectedAddress() async {
    if (!available) return null;
    try {
      final client = await _ensureClient();
      for (final s in client.sessions.getAll()) {
        final accs = s.namespaces['tron']?.accounts ?? const [];
        if (accs.isNotEmpty) return accs.first.split(':').last;
      }
    } catch (_) {/* 静默 */}
    return null;
  }

  /// 发起连接: 返回 (wc uri, session future). 调用方展示二维码/拉起钱包.
  static Future<(Uri?, Future<SessionData>)> connect() async {
    final client = await _ensureClient();
    final resp = await client.connect(requiredNamespaces: _tronNamespace);
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

  /// 请求钱包签名 TRC20 转账. 返回钱包响应 (签名交易 json 或含 txid).
  static Future<dynamic> signTransaction({
    required String ownerAddress,
    required Map<String, dynamic> unsignedTx,
  }) async {
    final client = _client ?? (throw StateError('未连接钱包'));
    SessionData? session;
    for (final s in client.sessions.getAll()) {
      final accs = s.namespaces['tron']?.accounts ?? const [];
      if (accs.any((a) => a.endsWith(ownerAddress))) {
        session = s;
        break;
      }
    }
    session ??= client.sessions.getAll().firstOrNull;
    if (session == null) throw StateError('未连接钱包');
    return client.request(
      topic: session.topic,
      chainId: tronChain,
      request: SessionRequestParams(
        method: 'tron_signTransaction',
        params: {'address': ownerAddress, 'transaction': unsignedTx},
      ),
    );
  }
}

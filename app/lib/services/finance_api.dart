import 'api.dart';
import 'auth.dart';

/// 邀请返佣与等级体系 (V0.7) 业务接口封装.
/// 后端 Decimal 序列化为字符串, 统一用 [d] 解析; 时间为 ISO 字符串.
class FinanceApi {
  FinanceApi._();

  static String? get _token => AuthStore.instance.token;

  /// Decimal/num → double (null → 0).
  static double d(dynamic v) =>
      v == null ? 0 : (double.tryParse(v.toString()) ?? 0);

  /// 百分比展示: 0.005 → "0.50%".
  static String pct(dynamic v) => '${(d(v) * 100).toStringAsFixed(2)}%';

  /// ISO 时间 → "2026-10-02 13:02".
  static String time(dynamic v) {
    if (v == null) return '-';
    return v.toString().replaceFirst('T', ' ').substring(0, 16);
  }

  // ── 产品 ──────────────────────────────────────────────
  static Future<List<dynamic>> products() =>
      McApi.getList('/api/products', token: _token);

  // ── VIP / 团队 ────────────────────────────────────────
  static Future<Map<String, dynamic>> vipMe() =>
      McApi.get('/api/vip/me', token: _token);

  static Future<Map<String, dynamic>> teamMe() =>
      McApi.get('/api/team/me', token: _token);

  // ── 订单 ──────────────────────────────────────────────
  static Future<Map<String, dynamic>> buy(int productId, String amount) =>
      McApi.post(
        '/api/orders',
        {'product_id': productId, 'amount': amount},
        token: _token,
      );

  static Future<List<dynamic>> orders() =>
      McApi.getList('/api/orders', token: _token);

  // ── 结算 / 佣金 / 等级 / 资金 ──────────────────────────
  static Future<List<dynamic>> settlements() =>
      McApi.getList('/api/settlements', token: _token);

  static Future<List<dynamic>> commissions() =>
      McApi.getList('/api/commissions', token: _token);

  static Future<Map<String, dynamic>> commissionSummary() =>
      McApi.get('/api/commissions/summary', token: _token);

  static Future<List<dynamic>> levelLogs({String? kind}) =>
      McApi.getList(
        '/api/level-logs${kind != null ? '?kind=$kind' : ''}',
        token: _token,
      );

  static Future<Map<String, dynamic>> account() =>
      McApi.get('/api/deposit/account', token: _token);

  static Future<List<dynamic>> balanceLogs({String? account}) =>
      McApi.getList(
        '/api/account/logs${account != null ? '?account=$account' : ''}',
        token: _token,
      );

  // ── 充值 ──────────────────────────────────────────────
  /// 我的充值地址 (首次自动从池分配). network: trc20|erc20|bep20|arbitrum.
  static Future<Map<String, dynamic>> depositAddress({String network = 'trc20'}) =>
      McApi.get('/api/deposit/address?network=$network', token: _token);

  /// 充值记录 (最新在前).
  static Future<List<dynamic>> depositRecords() =>
      McApi.getList('/api/deposit/records', token: _token);

  /// txid 补单 (链上已转未到账自助核销).
  static Future<Map<String, dynamic>> claimDeposit(String txid,
          {String network = 'trc20'}) =>
      McApi.post('/api/deposit/claim', {'txid': txid, 'network': network},
          token: _token);

  /// 钱包连接支付: 构造未签名 USDT 转账交易.
  static Future<Map<String, dynamic>> prepareDepositTransfer({
    required String ownerAddress,
    required String amount,
    String network = 'trc20',
  }) =>
      McApi.post(
        '/api/deposit/prepare-transfer',
        {'owner_address': ownerAddress, 'amount': amount, 'network': network},
        token: _token,
      );

  /// 广播钱包签名后的交易, 返回 txid.
  static Future<String> broadcastDeposit(Map<String, dynamic> signedTx) async {
    final m = await McApi.post(
      '/api/deposit/broadcast',
      {'signed_tx': signedTx},
      token: _token,
    );
    return (m['txid'] ?? '').toString();
  }

  // ── 提现 ──────────────────────────────────────────────
  static Future<List<dynamic>> withdrawNetworks() =>
      McApi.get('/api/withdrawals/networks', token: _token)
          .then((m) => (m['networks'] as List?) ?? const []);

  static Future<Map<String, dynamic>> withdrawQuote({
    required String account,
    required String amount,
    String network = 'trc20',
  }) =>
      McApi.get(
        '/api/withdrawals/quote?account=$account&amount=$amount&network=$network',
        token: _token,
      );

  static Future<Map<String, dynamic>> withdrawCreate(
    Map<String, dynamic> body,
  ) =>
      McApi.post('/api/withdrawals', body, token: _token);

  static Future<List<dynamic>> withdrawals() =>
      McApi.getList('/api/withdrawals', token: _token);
}

/// 文案映射 (与后端口径一致).
class FinLabels {
  FinLabels._();

  static const returnMethods = {
    'daily': '每日返还',
    'period_7d': '每 7 天返还',
    'period_30d': '每 30 天返还',
    'expiry': '到期一次性返还',
  };

  static const orderStatus = {
    'effective': '生效中',
    'finished': '已完成',
  };

  static const withdrawStatus = {
    'pending': '审核中',
    'approved': '已打款',
    'rejected': '已拒绝',
  };

  static const changeTypes = {
    'deposit_credited': '充值入账',
    'purchase': '购买产品',
    'income_settled': '收益结算',
    'commission': '团队返佣',
    'principal_returned': '到期返本',
    'withdraw_request': '提现申请',
    'withdraw_reject': '提现退回',
    'withdraw_approve': '提现通过',
  };

  static String changeType(dynamic v) =>
      changeTypes[v?.toString()] ?? (v?.toString() ?? '-');
}

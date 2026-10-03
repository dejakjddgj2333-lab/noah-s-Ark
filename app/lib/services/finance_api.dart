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

  // ── 提现 ──────────────────────────────────────────────
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

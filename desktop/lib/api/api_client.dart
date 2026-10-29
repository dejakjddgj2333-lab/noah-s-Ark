import 'package:dio/dio.dart';

/// HTTP client for the MingCe backend.
/// Mirrors web-terminal/src/api/index.js; base URL is the single production backend.
class ApiException implements Exception {
  ApiException(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient._() {
    _dio = Dio(BaseOptions(
      baseUrl: 'https://shipapi.bdxapi.com/api',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ));
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (opt, h) {
      if (token != null) opt.headers['Authorization'] = 'Bearer $token';
      h.next(opt);
    }, onError: (e, h) {
      if (e.response?.statusCode == 401) onUnauthorized?.call();
      final detail = e.response?.data is Map ? e.response?.data['detail'] : null;
      h.reject(DioException(
        requestOptions: e.requestOptions,
        response: e.response,
        error: ApiException(
          detail is String ? detail : (e.message ?? '网络错误'),
          status: e.response?.statusCode,
        ),
        type: e.type,
      ));
    }));
  }

  static final ApiClient I = ApiClient._();
  late final Dio _dio;

  String? token;
  void Function()? onUnauthorized;

  Future<dynamic> _get(String path, [Map<String, dynamic>? params]) async =>
      (await _dio.get(path, queryParameters: params)).data;
  Future<dynamic> _post(String path, [Object? data]) async =>
      (await _dio.post(path, data: data)).data;

  // ---------- Auth ----------
  Future<dynamic> login(String username, String password) => _post(
      '/auth/login',
      {'username': username, 'password': password, 'device_name': '桌面终端', 'platform': 'desktop'});
  Future<dynamic> register(Map<String, dynamic> data) =>
      _post('/auth/register', data);
  Future<dynamic> sendEmailCode(String email, {String purpose = 'register'}) =>
      _post('/auth/send-email-code', {'email': email, 'purpose': purpose});
  Future<dynamic> resetPassword(String email, String code, String newPassword) =>
      _post('/auth/reset-password',
          {'email': email, 'code': code, 'new_password': newPassword});
  Future<dynamic> me() => _get('/auth/me');
  Future<dynamic> changePassword(String oldPwd, String newPwd) =>
      _post('/auth/change-password', {'old_password': oldPwd, 'new_password': newPwd});

  // ---------- Market (OKX proxy) ----------
  Future<dynamic> tickers({String instType = 'SPOT'}) =>
      _get('/market/tickers', {'inst_type': instType});
  Future<dynamic> ticker(String instId) => _get('/market/ticker/$instId');
  Future<dynamic> candles(String instId, {String bar = '1H', int limit = 100}) =>
      _get('/market/candles/$instId', {'bar': bar, 'limit': limit});
  Future<dynamic> fundingRate(String instId) =>
      _get('/market/funding-rate/$instId');
  Future<dynamic> books(String instId, {int sz = 20}) =>
      _get('/market/books/$instId', {'sz': sz});
  Future<dynamic> trades(String instId, {int limit = 60}) =>
      _get('/market/trades/$instId', {'limit': limit});

  // ---------- Market overview ----------
  Future<dynamic> globalStats() => _get('/market-overview/global-stats');
  Future<dynamic> sentiment() => _get('/market-overview/sentiment');
  Future<dynamic> liquidity() => _get('/market-overview/liquidity');
  Future<dynamic> longShortRatio({String symbol = 'BTC'}) =>
      _get('/market-overview/long-short-ratio', {'symbol': symbol});
  Future<dynamic> indicators() => _get('/market-overview/indicators');
  Future<dynamic> openInterest() => _get('/market-overview/open-interest');
  Future<dynamic> liqExchangeList({String range = '24h'}) =>
      _get('/market-overview/liquidations/exchange-list', {'range': range});
  Future<dynamic> liqRecent({int limit = 50}) =>
      _get('/market-overview/liquidations/recent', {'limit': limit});
  Future<dynamic> liqOrders({double minAmount = 100000, int limit = 50}) =>
      _get('/market-overview/liquidations/orders',
          {'min_amount': minAmount, 'limit': limit});
  Future<dynamic> liqCoinList() =>
      _get('/market-overview/liquidations/coin-list');
  Future<dynamic> fundingExchangeRates({String symbol = 'BTC'}) =>
      _get('/market-overview/funding/exchange-rates', {'symbol': symbol});
  Future<dynamic> fundingHistory({String symbol = 'BTC'}) =>
      _get('/market-overview/funding/history', {'symbol': symbol});
  Future<dynamic> whaleAlerts() => _get('/market-overview/whale-alerts');
  Future<dynamic> whaleStatus() => _get('/market-overview/whale-status');

  // ---------- News ----------
  Future<dynamic> newsList([Map<String, dynamic>? params]) =>
      _get('/news', params);
  Future<dynamic> newsDetail(int id) => _get('/news/$id');

  // ---------- Chat ----------
  Future<dynamic> conversations() => _get('/chat/conversations');
  Future<dynamic> chatMessages(int conversationId,
          [Map<String, dynamic>? params]) =>
      _get('/chat/conversations/$conversationId/messages', params);
  Future<dynamic> sendChatMessage(int conversationId, Map<String, dynamic> data) =>
      _post('/chat/conversations/$conversationId/messages', data);
  // Read cursor is monotonic; message_id is required (else 422).
  Future<dynamic> markRead(int conversationId, int messageId) =>
      _post('/chat/conversations/$conversationId/read', {'message_id': messageId});
  // Peer read cursor: direct chats return peer_last_read_message_id.
  Future<dynamic> peerReadState(int conversationId) =>
      _get('/chat/conversations/$conversationId/read-state');

  // ---------- Account / products / orders ----------
  Future<dynamic> depositAccount() => _get('/deposit/account');
  Future<dynamic> products() => _get('/products');
  Future<dynamic> productDetail(int id) => _get('/products/$id');
  Future<dynamic> orders([Map<String, dynamic>? params]) =>
      _get('/orders', params);
  Future<dynamic> createOrder(Map<String, dynamic> data) =>
      _post('/orders', data);
  Future<dynamic> accountLogs([Map<String, dynamic>? params]) =>
      _get('/account/logs', params);
  Future<dynamic> convertQuote(Map<String, dynamic> params) =>
      _get('/account/convert/quote', params);
  Future<dynamic> convert(Map<String, dynamic> data) =>
      _post('/account/convert', data);
  Future<dynamic> vipMe() => _get('/vip/me');
  Future<dynamic> inviteMe() => _get('/invite/me');

  // ---------- Wallet (deposit / withdraw) ----------
  Future<dynamic> depositAddress(String network) =>
      _get('/deposit/address', {'network': network});
  Future<dynamic> depositRecords() => _get('/deposit/records');
  Future<dynamic> depositClaim(String txid, String network) =>
      _post('/deposit/claim', {'txid': txid, 'network': network});
  Future<dynamic> withdrawNetworks() => _get('/withdrawals/networks');
  Future<dynamic> withdrawQuote(Map<String, dynamic> params) =>
      _get('/withdrawals/quote', params);
  Future<dynamic> withdraw(Map<String, dynamic> data) =>
      _post('/withdrawals', data);
  Future<dynamic> withdrawalRecords() => _get('/withdrawals');

  // ---------- Invite / settlement (settlements router 无 prefix) ----------
  Future<dynamic> commissionsSummary() => _get('/commissions/summary');
  Future<dynamic> commissions([Map<String, dynamic>? params]) =>
      _get('/commissions', params);

  // ---------- Interaction ----------
  Future<dynamic> interact(String action, String targetType, int targetId) =>
      _post('/interaction/$action',
          {'target_type': targetType, 'target_id': targetId});
  // 批量查询点赞/收藏状态; target_ids 逗号分隔
  Future<dynamic> interactionState(String targetType, List<int> targetIds) =>
      _get('/interaction/state',
          {'target_type': targetType, 'target_ids': targetIds.join(',')});
  Future<dynamic> comments(String targetType, int targetId) =>
      _get('/interaction/comments',
          {'target_type': targetType, 'target_id': targetId});
  Future<dynamic> addComment(Map<String, dynamic> data) =>
      _post('/interaction/comments', data);

  // ---------- Chat extras ----------
  Future<dynamic> chatMembers(int conversationId) =>
      _get('/chat/conversations/$conversationId/members');
  Future<dynamic> friendsOnline() => _get('/chat/friends/online');

  // ---------- News extras ----------
  Future<dynamic> macroCalendar({String? date}) =>
      _get('/news/macro-calendar', {'date': ?date});

  // ---------- Auth extras ----------
  Future<dynamic> devices() => _get('/auth/devices');
}

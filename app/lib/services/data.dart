import 'api.dart';

/// 资讯条目 (后端 /api/news 行).
class NewsItem {
  NewsItem.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        title = (j['title'] ?? '') as String,
        summary = (j['summary'] ?? '') as String,
        content = (j['content'] ?? '') as String,
        coverUrl = j['cover_url'] as String?,
        source = (j['source'] ?? '') as String,
        category = (j['category'] ?? 'news') as String,
        publishAt = DateTime.tryParse((j['publish_at'] ?? '') as String) ??
            DateTime.now(),
        sentiment = j['sentiment'] as String?,
        likeCount = (j['like_count'] ?? 0) as int,
        commentCount = (j['comment_count'] ?? 0) as int,
        shareCount = (j['share_count'] ?? 0) as int;

  final int id;
  final String title;
  final String summary;
  final String content;
  final String? coverUrl;
  final String source;
  final String category;
  final DateTime publishAt;
  final String? sentiment;
  final int likeCount;
  final int commentCount;
  final int shareCount;
}

/// OKX ticker 行 (/api/market/tickers 透传).
class OkxTicker {
  OkxTicker.fromJson(Map<String, dynamic> j)
      : instId = (j['instId'] ?? '') as String,
        last = double.tryParse((j['last'] ?? '0') as String) ?? 0,
        open24h = double.tryParse((j['open24h'] ?? '0') as String) ?? 0,
        high24h = double.tryParse((j['high24h'] ?? '0') as String) ?? 0,
        low24h = double.tryParse((j['low24h'] ?? '0') as String) ?? 0,
        volCcy24h = double.tryParse((j['volCcy24h'] ?? '0') as String) ?? 0;

  final String instId;
  final double last;
  final double open24h;
  final double high24h;
  final double low24h;
  final double volCcy24h;

  double get changePct => open24h == 0 ? 0 : (last - open24h) / open24h * 100;

  /// BTC-USDT-SWAP / BTC-USDT → BTC
  String get symbol => instId.split('-').first;
}

double? _toDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');

/// 全网全景横幅数据 (CoinGecko /global). 上游失败时字段为 null.
class GlobalStats {
  GlobalStats.fromJson(Map<String, dynamic> j)
      : totalMarketCapUsd = _toDouble(j['total_market_cap_usd']),
        totalVolumeUsd = _toDouble(j['total_volume_usd']),
        changePct24h = _toDouble(j['market_cap_change_pct_24h']),
        btcDominance = _toDouble(j['btc_dominance']),
        ethDominance = _toDouble(j['eth_dominance']);

  final double? totalMarketCapUsd;
  final double? totalVolumeUsd;
  final double? changePct24h;
  final double? btcDominance;
  final double? ethDominance;
}

/// 全局多空账户占比 (多头主导指数).
class LongShortRatio {
  LongShortRatio.fromJson(Map<String, dynamic> j)
      : longPct = _toDouble(j['long_pct']),
        shortPct = _toDouble(j['short_pct']);

  final double? longPct;
  final double? shortPct;
}

/// 数据获取层. 所有方法失败抛 ApiException; 页面自行决定回退.
class McData {
  McData._();

  static Future<List<NewsItem>> news({
    String? category,
    int page = 1,
    int pageSize = 20,
  }) async {
    final q = StringBuffer('/api/news?page=$page&page_size=$pageSize');
    if (category != null) q.write('&category=$category');
    final resp = await McApi.get(q.toString());
    final items = (resp['items'] as List? ?? [])
        .map((e) => NewsItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return items;
  }

  static Future<List<OkxTicker>> tickers({String instType = 'SWAP'}) async {
    final resp = await McApi.get('/api/market/tickers?inst_type=$instType');
    final data = (resp['data'] as List? ?? [])
        .map((e) => OkxTicker.fromJson(e as Map<String, dynamic>))
        .toList();
    return data;
  }

  /// K线: 返回归一化 0..1 收盘价序列 (供 McSparkline).
  static Future<List<double>> sparkline(String instId,
      {String bar = '1H', int limit = 24}) async {
    final resp = await McApi.get(
        '/api/market/candles/$instId?bar=$bar&limit=$limit');
    final data = (resp['data'] as List? ?? [])
        .map((e) => double.tryParse('${(e as List)[4]}') ?? 0)
        .toList()
        .reversed // OKX 最新在前
        .toList();
    if (data.length < 2) return const [];
    final lo = data.reduce((a, b) => a < b ? a : b);
    final hi = data.reduce((a, b) => a > b ? a : b);
    final range = hi - lo;
    if (range == 0) return List.filled(data.length, 0.5);
    return data.map((v) => (v - lo) / range).toList();
  }

  /// CoinGlass 大盘指标透传. path 如 'sentiment', 'liquidations/exchange-list?range=24h'.
  /// 失败 (503 未配置/502 上游错误) 抛 ApiException — 调用方回退 mock.
  static Future<Map<String, dynamic>> overview(String path) =>
      McApi.get('/api/market-overview/$path');

  /// 全网全景 (总市值/成交额/涨跌幅/占比). 字段失败为 null.
  static Future<GlobalStats> globalStats() async =>
      GlobalStats.fromJson(await overview('global-stats'));

  /// 全局多空账户占比 (多头主导指数). 字段失败为 null.
  static Future<LongShortRatio> longShortRatio() async =>
      LongShortRatio.fromJson(await overview('long-short-ratio'));

  /// 大额美元缩写: 2.86T / 112.3B / 3.4M.
  static String fmtUsdCompact(double v) {
    final a = v.abs();
    if (a >= 1e12) return '\$${(v / 1e12).toStringAsFixed(2)}T';
    if (a >= 1e9) return '\$${(v / 1e9).toStringAsFixed(1)}B';
    if (a >= 1e6) return '\$${(v / 1e6).toStringAsFixed(1)}M';
    return '\$${v.toStringAsFixed(0)}';
  }
}

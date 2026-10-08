import '../core/l10n.dart';
import 'api.dart';
import 'auth.dart';
import 'ticker_ws.dart' show BookLevel, TradePush;

/// 资讯语言协商: 中文(简/繁)取中文, 其余语言取原文(英文).
String get newsLang => L10n.instance.isChinese ? 'zh' : 'en';

/// 资讯条目 (后端 /api/news 行).
class NewsItem {
  NewsItem.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        title = (j['title'] ?? '') as String,
        summary = (j['summary'] ?? '') as String,
        content = (j['content'] ?? '') as String,
        coverUrl = j['cover_url'] as String?,
        sourceUrl = j['source_url'] as String?,
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
  final String? sourceUrl;
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

/// 链上流动性总览 (DefiLlama /api/market-overview/liquidity). 字段失败为 null.
class LiquidityOverview {
  LiquidityOverview.fromJson(Map<String, dynamic> j)
      : stableTotalUsd = _toDouble(j['stable_total_usd']),
        stableChange1dPct = _toDouble(j['stable_change_1d_pct']),
        tvlTotalUsd = _toDouble(j['tvl_total_usd']),
        tvlChange1dPct = _toDouble(j['tvl_change_1d_pct']),
        topStables = (j['top_stables'] as List? ?? [])
            .whereType<Map>()
            .map((e) => StableCoin.fromJson(e.cast<String, dynamic>()))
            .toList();

  final double? stableTotalUsd;
  final double? stableChange1dPct;
  final double? tvlTotalUsd;
  final double? tvlChange1dPct;
  final List<StableCoin> topStables;

  bool get isEmpty =>
      stableTotalUsd == null && tvlTotalUsd == null && topStables.isEmpty;
}

/// 单个稳定币 (Top 列表项).
class StableCoin {
  StableCoin.fromJson(Map<String, dynamic> j)
      : name = (j['name'] ?? '') as String,
        circulatingUsd = _toDouble(j['circulating_usd']),
        change1dPct = _toDouble(j['change_1d_pct']);

  final String name;
  final double? circulatingUsd;
  final double? change1dPct;
}

/// 永续合约资金费率.
class FundingRate {  FundingRate.fromJson(Map<String, dynamic> j)
      : rate = _toDouble(j['fundingRate']),
        nextFundingTime = _msToTime(j['nextFundingTime']);

  final double? rate;
  final DateTime? nextFundingTime;

  static DateTime? _msToTime(dynamic v) {
    final ms = int.tryParse('$v');
    return (ms == null || ms == 0)
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms);
  }
}

/// 宏观日历事件 (后端 /api/news/macro-calendar). 时间已是北京时间, 直接展示.
class MacroEventItem {
  MacroEventItem.fromJson(Map<String, dynamic> j)
      : id = (j['id'] ?? 0) as int,
        eventAt = (j['event_at'] ?? '') as String,
        country = (j['country'] ?? '') as String,
        currency = (j['currency'] ?? '') as String,
        name = (j['name'] ?? '') as String,
        importance = (j['importance'] ?? 1) as int,
        previous = j['previous'] as String?,
        forecast = j['forecast'] as String?,
        actual = j['actual'] as String?,
        unit = (j['unit'] ?? '') as String;

  final int id;
  final String eventAt; // 'HH:mm' 北京时间
  final String country;
  final String currency;
  final String name;
  final int importance; // 1-3 (低/中/高)
  final String? previous;
  final String? forecast;
  final String? actual;
  final String unit;

  String get importanceLabel =>
      importance >= 3 ? '高' : importance == 2 ? '中' : '低';
}

/// 宏观事件详情: 中文解读 + 历史走势.
class MacroEventDetail {
  MacroEventDetail.fromJson(Map<String, dynamic> j)
      : id = (j['id'] ?? 0) as int,
        eventAt = (j['event_at'] ?? '') as String,
        country = (j['country'] ?? '') as String,
        currency = (j['currency'] ?? '') as String,
        name = (j['name'] ?? '') as String,
        nameEn = (j['name_en'] ?? '') as String,
        descZh = j['desc_zh'] as String?,
        importance = (j['importance'] ?? 1) as int,
        previous = j['previous'] as String?,
        forecast = j['forecast'] as String?,
        actual = j['actual'] as String?,
        unit = (j['unit'] ?? '') as String,
        history = ((j['history'] as List? ?? [])
            .map((h) => MacroHistoryPoint.fromJson(h as Map<String, dynamic>))
            .toList())
            .reversed
            .toList(); // 接口倒序 -> 正序 (旧->新)

  final int id;
  final String eventAt; // 'YYYY-MM-DD HH:mm' 北京时间
  final String country;
  final String currency;
  final String name;
  final String nameEn;
  final String? descZh;
  final int importance;
  final String? previous;
  final String? forecast;
  final String? actual;
  final String unit;
  final List<MacroHistoryPoint> history; // 时间正序
}

class MacroHistoryPoint {
  MacroHistoryPoint.fromJson(Map<String, dynamic> j)
      : date = (j['date'] ?? '') as String,
        previous = j['previous'] as String?,
        forecast = j['forecast'] as String?,
        actual = j['actual'] as String?;

  final String date;
  final String? previous;
  final String? forecast;
  final String? actual;

  /// 提取数值 (去掉 %, K, M, B, 逗号等), 无法解析返回 null.
  static double? parseNum(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    var s = raw.replaceAll(',', '').replaceAll('%', '').trim();
    double mult = 1;
    if (s.endsWith('K')) {
      mult = 1e3;
      s = s.substring(0, s.length - 1);
    } else if (s.endsWith('M')) {
      mult = 1e6;
      s = s.substring(0, s.length - 1);
    } else if (s.endsWith('B')) {
      mult = 1e9;
      s = s.substring(0, s.length - 1);
    } else if (s.endsWith('T')) {
      mult = 1e12;
      s = s.substring(0, s.length - 1);
    }
    final v = double.tryParse(s);
    return v == null ? null : v * mult;
  }
}

/// 数据获取层. 所有方法失败抛 ApiException; 页面自行决定回退.
class McData {
  McData._();

  static Future<List<NewsItem>> news({
    String? category,
    int page = 1,
    int pageSize = 20,
    String? keyword,
  }) async {
    final q = StringBuffer(
        '/api/news?page=$page&page_size=$pageSize&lang=$newsLang');
    if (category != null) q.write('&category=$category');
    if (keyword != null && keyword.isNotEmpty) {
      q.write('&keyword=${Uri.encodeComponent(keyword)}');
    }
    final resp = await McApi.get(q.toString());
    final items = (resp['items'] as List? ?? [])
        .map((e) => NewsItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return items;
  }

  /// 资讯详情 (后端 /api/news/{id}, 字段同列表项 + content).
  static Future<NewsItem> newsDetail(int id) async {
    final resp = await McApi.get('/api/news/$id?lang=$newsLang');
    return NewsItem.fromJson(resp);
  }

  /// 宏观日历 (/api/news/macro-calendar?date=YYYY-MM-DD). date 为北京时间日, null=今天.
  static Future<List<MacroEventItem>> macroCalendar({String? date}) async {
    final path = (date == null || date.isEmpty)
        ? '/api/news/macro-calendar'
        : '/api/news/macro-calendar?date=${Uri.encodeComponent(date)}';
    final resp = await McApi.get(path);
    return (resp['items'] as List? ?? [])
        .map((e) => MacroEventItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<MacroEventDetail> macroEventDetail(int id) async {
    final resp = await McApi.get('/api/news/macro-calendar/$id/detail');
    return MacroEventDetail.fromJson(resp);
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

  /// 单交易对最新行情 (/api/market/ticker/{instId}).
  static Future<OkxTicker> ticker(String instId) async {
    final resp = await McApi.get('/api/market/ticker/$instId');
    final data = resp['data'] as List? ?? [];
    if (data.isEmpty) throw StateError('no ticker for $instId');
    return OkxTicker.fromJson(data.first as Map<String, dynamic>);
  }

  /// K线原始数据: 返回 [{ts,o,h,l,c,v}] 时间升序 (后端返回最新在前, 已反转).
  static Future<List<Map<String, double>>> candles(String instId,
      {String bar = '1H', int limit = 60}) async {
    final resp =
        await McApi.get('/api/market/candles/$instId?bar=$bar&limit=$limit');
    return (resp['data'] as List? ?? [])
        .map((e) {
          final row = e as List;
          double p(int i) =>
              i < row.length ? (double.tryParse('${row[i]}') ?? 0) : 0;
          return <String, double>{
            'ts': p(0),
            'o': p(1),
            'h': p(2),
            'l': p(3),
            'c': p(4),
            'v': p(5),
          };
        })
        .toList()
        .reversed // OKX 最新在前 -> 时间升序
        .toList();
  }

  /// 盘口深度 (服务端代理 OKX; 手机直连 OKX WS 常被墙).
  /// 返回 (bids, asks), 各档 (px, sz), bids 价格降序 / asks 升序.
  static Future<(List<BookLevel>, List<BookLevel>)> orderBook(String instId,
      {int sz = 20}) async {
    final resp = await McApi.get('/api/market/books/$instId?sz=$sz');
    final data = resp['data'] as List? ?? [];
    if (data.isEmpty) return (const <BookLevel>[], const <BookLevel>[]);
    final book = data.first as Map<String, dynamic>;
    List<BookLevel> parse(dynamic raw) => [
          for (final lv in (raw as List? ?? const []))
            if (lv is List && lv.length >= 2)
              BookLevel(
                double.tryParse('${lv[0]}') ?? 0,
                double.tryParse('${lv[1]}') ?? 0,
              ),
        ];
    return (parse(book['bids']), parse(book['asks']));
  }

  /// 最近逐笔成交 (新在前).
  static Future<List<TradePush>> recentTrades(String instId,
      {int limit = 60}) async {
    final resp = await McApi.get('/api/market/trades/$instId?limit=$limit');
    return [
      for (final e in (resp['data'] as List? ?? const []))
        if (e is Map)
          TradePush(
            instId: instId,
            px: double.tryParse('${e['px']}') ?? 0,
            sz: double.tryParse('${e['sz']}') ?? 0,
            side: '${e['side'] ?? ''}',
            ts: int.tryParse('${e['ts']}') ?? 0,
          ),
    ];
  }

  /// 永续合约资金费率 (/api/market/funding-rate/{instId}).
  static Future<FundingRate> fundingRate(String instId) async {
    final resp = await McApi.get('/api/market/funding-rate/$instId');
    final data = resp['data'] as List? ?? [];
    return FundingRate.fromJson(
        data.isEmpty ? const {} : data.first as Map<String, dynamic>);
  }

  /// CoinGlass 大盘指标透传. path 如 'sentiment', 'liquidations/exchange-list?range=24h'.
  /// 失败 (503 未配置/502 上游错误) 抛 ApiException — 调用方回退 mock.
  static Future<Map<String, dynamic>> overview(String path) =>
      McApi.get('/api/market-overview/$path');

  /// 市场数据源: 'free' | 'coinglass'. 短缓存; 失败默认 'free' (隐藏链上内容更保守).
  static String? _marketSourceCache;
  static DateTime? _marketSourceAt;

  static Future<String> marketSource() async {
    final at = _marketSourceAt;
    if (_marketSourceCache != null &&
        at != null &&
        DateTime.now().difference(at).inMinutes < 10) {
      return _marketSourceCache!;
    }
    String source = 'free';
    try {
      final body = await overview('source');
      source = (body['source'] as String?) ?? 'free';
    } catch (_) {
      // 接口失败保持 free
    }
    _marketSourceCache = source;
    _marketSourceAt = DateTime.now();
    return source;
  }

  /// 全网全景 (总市值/成交额/涨跌幅/占比). 字段失败为 null.
  static Future<GlobalStats> globalStats() async =>
      GlobalStats.fromJson(await overview('global-stats'));

  /// 全局多空账户占比 (多头主导指数). 字段失败为 null.
  static Future<LongShortRatio> longShortRatio() async =>
      LongShortRatio.fromJson(await overview('long-short-ratio'));

  /// 链上流动性总览 (稳定币流通 + DeFi TVL). 字段失败为 null.
  static Future<LiquidityOverview> liquidityOverview() async =>
      LiquidityOverview.fromJson(await overview('liquidity'));

  /// 大额美元缩写: 2.86T / 112.3B / 3.4M.
  static String fmtUsdCompact(double v) {
    final a = v.abs();
    if (a >= 1e12) return '\$${(v / 1e12).toStringAsFixed(2)}T';
    if (a >= 1e9) return '\$${(v / 1e9).toStringAsFixed(1)}B';
    if (a >= 1e6) return '\$${(v / 1e6).toStringAsFixed(1)}M';
    return '\$${v.toStringAsFixed(0)}';
  }
}

/// 互动状态 (点赞/收藏/评论数). 对应 /api/interaction/state.
class InteractionState {
  InteractionState.fromJson(Map<String, dynamic> j)
      : likeCount = (j['like_count'] ?? 0) as int,
        commentCount = (j['comment_count'] ?? 0) as int,
        likedByMe = (j['liked_by_me'] ?? false) as bool,
        favoritedByMe = (j['favorited_by_me'] ?? false) as bool;

  final int likeCount;
  final int commentCount;
  final bool likedByMe;
  final bool favoritedByMe;

  InteractionState copyWith({
    int? likeCount,
    int? commentCount,
    bool? likedByMe,
    bool? favoritedByMe,
  }) =>
      InteractionState.fromJson({
        'like_count': likeCount ?? this.likeCount,
        'comment_count': commentCount ?? this.commentCount,
        'liked_by_me': likedByMe ?? this.likedByMe,
        'favorited_by_me': favoritedByMe ?? this.favoritedByMe,
      });
}

/// 评论/回复条目. 对应 /api/interaction/comments items.
class McComment {
  McComment.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        username = ((j['user'] as Map? ?? const {})['username'] ?? '') as String,
        content = (j['content'] ?? '') as String,
        replyCount = (j['reply_count'] ?? 0) as int,
        likeCount = (j['like_count'] ?? 0) as int,
        likedByMe = (j['liked_by_me'] ?? false) as bool,
        createdAt = DateTime.tryParse((j['created_at'] ?? '') as String) ??
            DateTime.now();

  final int id;
  final String username;
  final String content;
  final int replyCount;
  final int likeCount;
  final bool likedByMe;
  final DateTime createdAt;
}

/// 资讯互动接口 (点赞/收藏/评论). target_type 固定 'news'.
/// 未登录可读 (state/comments 无需 token); 写操作需登录, 自动带 token.
class McInteraction {
  McInteraction._();

  static const _targetType = 'news';

  static String? get _token => AuthStore.instance.token;

  /// 互动状态: 点赞数/评论数 + 我是否已赞/已藏. 未登录 liked/favorited 恒 false.
  static Future<InteractionState> state(int newsId) async {
    final resp = await McApi.get(
      '/api/interaction/state?target_type=$_targetType&target_id=$newsId',
      token: _token,
    );
    return InteractionState.fromJson(resp);
  }

  /// 评论列表 (顶层). 返回 (items, total).
  static Future<(List<McComment>, int)> comments(int newsId,
      {int page = 1, int pageSize = 20}) async {
    final resp = await McApi.get(
      '/api/interaction/comments?target_type=$_targetType&target_id=$newsId'
      '&page=$page&page_size=$pageSize',
      token: _token,
    );
    final items = (resp['items'] as List? ?? [])
        .map((e) => McComment.fromJson(e as Map<String, dynamic>))
        .toList();
    final total = (resp['total'] ?? items.length) as int;
    return (items, total);
  }

  /// 某条评论的回复列表 (时间升序).
  static Future<List<McComment>> replies(int commentId) async {
    final resp = await McApi.get(
      '/api/interaction/comments/$commentId/replies',
      token: _token,
    );
    return (resp['items'] as List? ?? [])
        .map((e) => McComment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 发评论/回复. 返回新评论. 需登录.
  static Future<McComment> addComment(int newsId, String content,
      {int? replyToId}) async {
    final resp = await McApi.post(
      '/api/interaction/comments',
      {
        'target_type': _targetType,
        'target_id': newsId,
        'content': content,
        'reply_to_id': ?replyToId,
      },
      token: _token,
    );
    return McComment.fromJson(resp);
  }

  /// 删除自己的评论. 需登录 (owner). 204 无 body.
  static Future<void> deleteComment(int commentId) async {
    await McApi.del('/api/interaction/comments/$commentId', token: _token);
  }

  /// 举报评论. 需登录; reason ∈ spam/abuse/fraud/porn/other.
  static Future<void> reportComment(int commentId,
      {String reason = 'other', String detail = ''}) async {
    await McApi.post(
      '/api/interaction/comments/$commentId/report',
      {'reason': reason, 'detail': detail},
      token: _token,
    );
  }

  /// 点赞/取消点赞. 返回 (liked, likeCount). 需登录.
  static Future<(bool, int)> toggleLike(int newsId) async {
    final resp = await McApi.post(
      '/api/interaction/like',
      {'target_type': _targetType, 'target_id': newsId},
      token: _token,
    );
    return (
      (resp['liked'] ?? false) as bool,
      (resp['like_count'] ?? 0) as int,
    );
  }

  /// 收藏/取消收藏. 返回 favorited. 需登录.
  static Future<bool> toggleFavorite(int newsId) async {
    final resp = await McApi.post(
      '/api/interaction/favorite',
      {'target_type': _targetType, 'target_id': newsId},
      token: _token,
    );
    return (resp['favorited'] ?? false) as bool;
  }
}

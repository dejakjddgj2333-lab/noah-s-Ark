import 'package:intl/intl.dart';

/// Number/time formatting helpers. All money-ish numbers render mono + right-aligned.
abstract final class Fmt {
  static final _c2 = NumberFormat('#,##0.00');
  static final _c0 = NumberFormat('#,##0');
  static final _c4 = NumberFormat('#,##0.####');

  static num? toNum(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  /// Adaptive precision: big values 2dp, small values up to 4dp,
  /// micro prices (<0.01, e.g. PEPE 0.000004225) up to 10dp with trailing zeros trimmed.
  static String num_(dynamic v, {int dp = 2}) {
    final n = toNum(v);
    if (n == null) return '--';
    if (n.abs() >= 1000) return dp == 0 ? _c0.format(n) : _c2.format(n);
    if (n.abs() >= 0.01 || n == 0) return _c4.format(n);
    return n
        .toStringAsFixed(10)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  /// Compact: 1.2K / 3.4M / 5.6B
  static String compact(dynamic v, {String prefix = ''}) {
    final n = toNum(v);
    if (n == null) return '--';
    final a = n.abs();
    if (a >= 1e9) return '$prefix${_trim(n / 1e9)}B';
    if (a >= 1e6) return '$prefix${_trim(n / 1e6)}M';
    if (a >= 1e3) return '$prefix${_trim(n / 1e3)}K';
    return '$prefix${_trim(n)}';
  }

  static String _trim(num v) {
    final s = v.toStringAsFixed(2);
    return s.contains('.') ? s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '') : s;
  }

  static String pct(dynamic v, {int dp = 2, bool sign = true}) {
    final n = toNum(v);
    if (n == null) return '--';
    final s = n.toStringAsFixed(dp);
    return sign && n > 0 ? '+$s%' : '$s%';
  }

  /// Backend `publish_at` etc. are Beijing-time naive strings — never parse as UTC.
  static DateTime? parseServerTime(dynamic v) {
    if (v == null) return null;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    final s = v.toString().replaceFirst('T', ' ');
    // 纯数字字符串按 epoch 毫秒处理 (如逐笔成交 ts)
    if (RegExp(r'^\d{11,}$').hasMatch(s)) {
      return DateTime.fromMillisecondsSinceEpoch(int.parse(s));
    }
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ ](\d{2}):(\d{2})(?::(\d{2}))?')
        .firstMatch(s);
    if (m == null) return DateTime.tryParse(s);
    return DateTime(
      int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!),
      int.parse(m[4]!), int.parse(m[5]!), int.parse(m[6] ?? '0'),
    );
  }

  static String hm(dynamic v) {
    final t = parseServerTime(v);
    if (t == null) return '--';
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(t.hour)}:${p(t.minute)}';
  }

  static String mdHm(dynamic v) {
    final t = parseServerTime(v);
    if (t == null) return '--';
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(t.month)}-${p(t.day)} ${p(t.hour)}:${p(t.minute)}';
  }

  /// Relative: 刚刚 / N分钟前 / N小时前 / MM-DD
  static String ago(dynamic v) {
    final t = parseServerTime(v);
    if (t == null) return '--';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return '刚刚';
    if (d.inHours < 1) return '${d.inMinutes}分钟前';
    if (d.inDays < 1) return '${d.inHours}小时前';
    return mdHm(v);
  }
}

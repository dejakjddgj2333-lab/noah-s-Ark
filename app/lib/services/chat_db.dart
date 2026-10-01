import 'package:hive_flutter/hive_flutter.dart';

/// 本地消息存储 (微信式: 服务器仅做relay, 历史以本机为准).
/// 用 Hive 存普通 `Map<String,dynamic>` (无 codegen). 每个会话一个 key,
/// value 为该会话消息 Map 列表 (按 id 升序, 上限 500 条, 超出裁最旧).
/// 全程容错: 未初始化 / 平台不支持 (如 Web 个别情况) 一律静默降级为空操作.
class ChatDb {
  ChatDb._();

  static const _boxName = 'chat_msgs';
  static const _perConvCap = 500;

  static Box<dynamic>? _box;
  static bool _triedInit = false;

  /// main() 中 runApp 前调用. 失败静默 (App 仍可跑, 仅无本地缓存).
  static Future<void> init() async {
    if (_triedInit) return;
    _triedInit = true;
    try {
      await Hive.initFlutter();
      _box = await Hive.openBox<dynamic>(_boxName);
    } catch (_) {
      _box = null;
    }
  }

  static bool get _ready => _box != null && _box!.isOpen;

  static String _key(int convId) => 'conv_$convId';

  /// 保存一条消息 (按 id 去重, 服务器最新覆盖旧的). 静默失败.
  static Future<void> saveMessage(int convId, Map<String, dynamic> json) async {
    if (!_ready) return;
    try {
      final id = _msgId(json);
      if (id == 0) return;
      final list = _readList(convId);
      list.removeWhere((m) => _msgId(m) == id);
      list.add(Map<String, dynamic>.from(json));
      list.sort((a, b) => _msgId(a).compareTo(_msgId(b)));
      // 超上限裁最旧 (列表升序, 前面的最旧).
      while (list.length > _perConvCap) {
        list.removeAt(0);
      }
      await _box!.put(_key(convId), list);
    } catch (_) {/* 静默 */}
  }

  /// 批量保存 (服务器拉取/翻页合并时).
  static Future<void> saveMessages(
      int convId, Iterable<Map<String, dynamic>> jsons) async {
    if (!_ready) return;
    try {
      final list = _readList(convId);
      final idx = {for (var i = 0; i < list.length; i++) _msgId(list[i]): i};
      for (final j in jsons) {
        final id = _msgId(j);
        if (id == 0) continue;
        final at = idx[id];
        if (at != null) {
          list[at] = Map<String, dynamic>.from(j); // 覆盖为最新
        } else {
          idx[id] = list.length;
          list.add(Map<String, dynamic>.from(j));
        }
      }
      list.sort((a, b) => _msgId(a).compareTo(_msgId(b)));
      while (list.length > _perConvCap) {
        list.removeAt(0);
      }
      await _box!.put(_key(convId), list);
    } catch (_) {/* 静默 */}
  }

  /// 读取会话本地消息 (按 id 升序). 未初始化/无数据返回空表.
  static List<Map<String, dynamic>> messagesFor(int convId) {
    if (!_ready) return const [];
    try {
      return _readList(convId);
    } catch (_) {
      return const [];
    }
  }

  /// 清空单个会话 (删除/退群时).
  static Future<void> clearConversation(int convId) async {
    if (!_ready) return;
    try {
      await _box!.delete(_key(convId));
    } catch (_) {/* 静默 */}
  }

  /// 清空全部 (登出时).
  static Future<void> clearAll() async {
    if (!_ready) return;
    try {
      await _box!.clear();
    } catch (_) {/* 静默 */}
  }

  // ---------- 内部 ----------

  static List<Map<String, dynamic>> _readList(int convId) {
    final raw = _box!.get(_key(convId));
    if (raw is! List) return <Map<String, dynamic>>[];
    return [
      for (final e in raw)
        if (e is Map)
          e.map((k, v) => MapEntry(k.toString(), v)),
    ];
  }

  static int _msgId(Map<dynamic, dynamic> m) {
    final v = m['id'];
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}

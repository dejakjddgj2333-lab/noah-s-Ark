import 'dart:async';

/// 邀请链接识别 (需求文档第一节: 通过邀请链接注册时识别邀请人).
///
/// 支持两种形态:
/// - App scheme: noahsark://invite?invite=CODE (Android intent-filter 已配, 点开直接唤起)
/// - Web/通用链接: 任意 https://host/?invite=CODE (Universal Links 配好域名后同样生效)
///
/// 识别到的邀请码先暂存, 注册页初始化时取出预填; 取一次即清除, 不会滞留.
class InviteLinkStore {
  InviteLinkStore._();
  static final InviteLinkStore instance = InviteLinkStore._();

  String? _pendingCode;
  final _ctrl = StreamController<String>.broadcast();
  String? _handledKey;

  /// 待预填的邀请码 (注册页读取后应调 consume 清除)
  String? get pendingCode => _pendingCode;

  /// 新识别到邀请码时的通知 (用于界面提示"已识别邀请人")
  Stream<String> get onCode => _ctrl.stream;

  /// 取出并清除暂存的邀请码
  String? consume() {
    final c = _pendingCode;
    _pendingCode = null;
    return c;
  }

  /// 解析 Uri, 提取 ?invite= 参数. 同一链接去重 (冷启动 initialLink 与
  /// stream 可能各投递一次).
  bool handleUri(Uri? uri) {
    if (uri == null) return false;
    final code = uri.queryParameters['invite']?.trim();
    if (code == null || code.isEmpty) return false;
    final key = '$code@${uri.path}';
    if (key == _handledKey) return false;
    _handledKey = key;
    _pendingCode = code.toUpperCase();
    _ctrl.add(_pendingCode!);
    return true;
  }
}

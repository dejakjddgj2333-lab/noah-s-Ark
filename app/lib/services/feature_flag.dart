import 'package:flutter/foundation.dart';

import 'api.dart';

/// 全局功能开关 (后端 /api/config 公开读取, 后台管理系统可改).
///
/// 钱包(充值/提现)等功能按开关显隐, 默认关闭(隐藏), 申请资质后后台打开即显示.
class FeatureFlag extends ChangeNotifier {
  FeatureFlag._();
  static final FeatureFlag instance = FeatureFlag._();

  /// 充值/提现是否开放 (默认 false=隐藏).
  bool walletEnabled = false;

  /// 理财/返佣是否开放 (默认 false=隐藏; 资质下来后后台打开).
  bool financeEnabled = false;

  bool _loaded = false;

  /// 拉取开关 (app 启动 + 进资产页时调用). 失败保持现状.
  Future<void> refresh() async {
    try {
      final m = await McApi.get('/api/config');
      walletEnabled = m['wallet_enabled'] == true;
      financeEnabled = m['finance_enabled'] == true;
      _loaded = true;
      notifyListeners();
    } catch (_) {
      // 网络失败: 首次默认隐藏, 已加载则保持
      if (!_loaded) {
        walletEnabled = false;
        financeEnabled = false;
      }
    }
  }
}

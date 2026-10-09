import 'package:flutter/foundation.dart';

/// 功能开关 — 编译期常量 (--dart-define), 不走任何远程配置.
///
/// 苹果审核 2.3.1 禁止"审核后远程解锁的隐藏功能", 故充值/理财的显隐
/// 必须编译进包: 想开启只能发新版本重新提审, 包能力 = 审核所见.
///
/// 提审包 (默认): 全部隐藏
///   flutter build ipa --release
/// 资质下来后的完整包:
///   flutter build ipa --release --dart-define=WALLET_ENABLED=true --dart-define=FINANCE_ENABLED=true
class FeatureFlag extends ChangeNotifier {
  FeatureFlag._();
  static final FeatureFlag instance = FeatureFlag._();

  /// 充值/提现是否开放 (编译期决定, 默认隐藏).
  static const bool _kWallet =
      bool.fromEnvironment('WALLET_ENABLED', defaultValue: false);

  /// 理财/返佣是否开放 (编译期决定, 默认隐藏).
  static const bool _kFinance =
      bool.fromEnvironment('FINANCE_ENABLED', defaultValue: false);

  bool get walletEnabled => _kWallet;
  bool get financeEnabled => _kFinance;

  /// 兼容旧调用点: 不再请求网络, 直接就绪.
  Future<void> refresh() async {
    notifyListeners();
  }
}

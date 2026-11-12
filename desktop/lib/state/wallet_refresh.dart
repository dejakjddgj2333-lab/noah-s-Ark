import 'package:flutter/foundation.dart';

/// 钱包数据刷新信号: 服务端 deposit_credited 推送后 bump,
/// 资产/充值页监听重拉余额与记录 (对齐 app 侧 WalletRefresh).
class WalletRefresh extends ChangeNotifier {
  WalletRefresh._();
  static final WalletRefresh I = WalletRefresh._();

  void bump() => notifyListeners();
}

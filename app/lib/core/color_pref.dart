import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

/// 涨跌配色偏好: 绿涨红跌 (国际) / 红涨绿跌 (中国习惯).
/// 全局单例 ChangeNotifier, 切换后全 App 涨跌色实时反转并持久化.
class ColorPref extends ChangeNotifier {
  ColorPref._();
  static final ColorPref instance = ColorPref._();

  static const String _key = 'mc_price_color';

  /// true = 红涨绿跌 (中国), false = 绿涨红跌 (国际, 默认).
  bool redUp = false;

  /// 涨/多/正向色.
  Color get bullColor => redUp ? McColors.bear : McColors.bull;

  /// 跌/空/负向色.
  Color get bearColor => redUp ? McColors.bull : McColors.bear;

  /// 按涨跌值取色 (v >= 0 用涨色).
  Color of(num v) => v >= 0 ? bullColor : bearColor;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    redUp = sp.getBool(_key) ?? false;
    notifyListeners();
  }

  Future<void> setRedUp(bool v) async {
    if (v == redUp) return;
    redUp = v;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_key, v);
  }
}

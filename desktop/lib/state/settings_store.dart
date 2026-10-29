import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';

/// Local display preferences (mirrors web Profile.vue 偏好设置卡).
/// Currently only the up/down color scheme has global effect; language and
/// notification toggles are stored for future wiring.
class SettingsStore extends ChangeNotifier {
  SettingsStore._();
  static final SettingsStore I = SettingsStore._();

  static const kColorScheme = 'mc_color_scheme'; // 'intl' | 'cn'

  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      Mc.cnScheme = sp.getString(kColorScheme) == 'cn';
    } catch (_) {}
  }

  /// Apply a color scheme ('intl' | 'cn'), persist, and rebuild listeners.
  Future<void> setColorScheme(String scheme) async {
    Mc.cnScheme = scheme == 'cn';
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(kColorScheme, scheme);
    } catch (_) {}
  }
}

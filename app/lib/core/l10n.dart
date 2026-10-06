import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'strings.dart';

/// 应用内支持的语言. flag 用区域指示 emoji, 选择列表更直观.
class Lang {
  const Lang(this.code, this.flag, this.nativeName, this.englishName);
  final String code; // 唯一键, 也用于后端/资讯语言协商
  final String flag;
  final String nativeName; // 该语言的自称 (列表主显示)
  final String englishName; // 英文名 (副显示)
}

class L10n extends ChangeNotifier {
  L10n._();
  static final L10n instance = L10n._();

  /// 简体中文, 繁体中文, 英语, 日语, 韩语, 西班牙语, 葡萄牙语, 印地语.
  static const List<Lang> languages = [
    Lang('zh-CN', '🇨🇳', '简体中文', 'Simplified Chinese'),
    Lang('zh-TW', '🇨🇳', '繁體中文', 'Traditional Chinese'),
    Lang('en', '🇺🇸', 'English', 'English'),
    Lang('ja', '🇯🇵', '日本語', 'Japanese'),
    Lang('ko', '🇰🇷', '한국어', 'Korean'),
    Lang('es', '🇪🇸', 'Español', 'Spanish'),
    Lang('pt', '🇵🇹', 'Português', 'Portuguese'),
    Lang('hi', '🇮🇳', 'हिन्दी', 'Hindi'),
  ];

  static const String _key = 'mc_lang';

  /// 当前语言码, 默认简体中文.
  String code = 'zh-CN';

  Lang get current =>
      languages.firstWhere((l) => l.code == code,
          orElse: () => languages.first);

  bool get isChinese => code.startsWith('zh');

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final saved = sp.getString(_key);
    if (saved != null && languages.any((l) => l.code == saved)) {
      code = saved;
    }
    notifyListeners();
  }

  Future<void> setCode(String c) async {
    if (c == code) return;
    code = c;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, c);
  }

  /// 查文案. 先查页面分组表, 再查核心表, 缺失回退简体中文, 再回退 key 本身.
  String t(String key) =>
      McStrings.lookup(code, key) ??
      McStrings.lookup('zh-CN', key) ??
      key;
}

/// 全局便捷取文案.
String tr(String key) => L10n.instance.t(key);

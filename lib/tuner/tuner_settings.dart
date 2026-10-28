import 'package:shared_preferences/shared_preferences.dart';

import 'tuning_modes.dart';

class SavedSettings {
  const SavedSettings({
    required this.modeId,
    required this.a4,
    this.isDark = true,
    this.themeMode = 'system',
  });
  final String modeId;
  final double a4;
  final bool isDark;

  /// 'system' | 'light' | 'dark'
  final String themeMode;
}

/// 设置持久化：SharedPreferences 存 modeId + a4。
/// 读取时校验：非法 modeId 回退 standard，a4 超出 [430,450] 回退 440。
class TunerSettings {
  static const _kMode = 'modeId';
  static const _kA4 = 'a4';
  static const _kDark = 'isDark';
  static const _kThemeMode = 'themeMode';

  Future<void> save(String modeId, double a4,
      {bool isDark = true, String themeMode = 'system'}) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kMode, modeId);
    await sp.setDouble(_kA4, a4);
    await sp.setBool(_kDark, isDark);
    await sp.setString(_kThemeMode, themeMode);
  }

  static Future<SavedSettings> load() async {
    final sp = await SharedPreferences.getInstance();
    final modeId = sp.getString(_kMode);
    final a4 = sp.getDouble(_kA4);
    final isDark = sp.getBool(_kDark);
    final tm = sp.getString(_kThemeMode);
    const valid = ['system', 'light', 'dark'];
    return SavedSettings(
      modeId: TuningModes.all.any((m) => m.id == modeId) ? modeId! : 'standard',
      a4: (a4 != null && a4 >= 430 && a4 <= 450) ? a4 : 440.0,
      isDark: isDark ?? true,
      themeMode: tm != null && valid.contains(tm) ? tm : 'system',
    );
  }
}

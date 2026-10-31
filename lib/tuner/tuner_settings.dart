import 'package:shared_preferences/shared_preferences.dart';

import 'tuning_modes.dart';

class SavedSettings {
  const SavedSettings({
    required this.modeId,
    required this.a4,
    this.isDark = true,
    this.themeMode = 'system',
    this.noisyMode = false,
  });
  final String modeId;
  final double a4;
  final bool isDark;

  /// 'system' | 'light' | 'dark'
  final String themeMode;

  /// 嘈杂环境调音：放宽检测器门限（conf 0.70 / band 0.06）+ 拨弦
  /// 起振时间门（OnsetGate）+ 稳定唤醒降为 2 帧。
  final bool noisyMode;
}

/// 设置持久化：SharedPreferences 存 modeId + a4 + 偏好。
/// 读取时校验：非法 modeId 回退 standard，a4 超出 [430,450] 回退 440。
class TunerSettings {
  static const _kMode = 'modeId';
  static const _kA4 = 'a4';
  static const _kDark = 'isDark';
  static const _kThemeMode = 'themeMode';
  static const _kNoisy = 'noisyMode';

  Future<void> save(String modeId, double a4,
      {bool isDark = true,
      String themeMode = 'system',
      bool noisyMode = false}) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kMode, modeId);
    await sp.setDouble(_kA4, a4);
    await sp.setBool(_kDark, isDark);
    await sp.setString(_kThemeMode, themeMode);
    await sp.setBool(_kNoisy, noisyMode);
  }

  static Future<SavedSettings> load() async {
    final sp = await SharedPreferences.getInstance();
    final modeId = sp.getString(_kMode);
    final a4 = sp.getDouble(_kA4);
    final isDark = sp.getBool(_kDark);
    final tm = sp.getString(_kThemeMode);
    const valid = ['system', 'light', 'dark'];
    final noisy = sp.getBool(_kNoisy);
    return SavedSettings(
      modeId: TuningModes.all.any((m) => m.id == modeId) ? modeId! : 'standard',
      a4: (a4 != null && a4 >= 430 && a4 <= 450) ? a4 : 440.0,
      isDark: isDark ?? true,
      themeMode: tm != null && valid.contains(tm) ? tm : 'system',
      noisyMode: noisy ?? false,
    );
  }
}

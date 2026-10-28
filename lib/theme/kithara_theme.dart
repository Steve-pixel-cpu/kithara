import 'package:flutter/material.dart';

/// Kithara 设计令牌 — 移植自 aulos app.css 的设计系统：
/// 冷调石墨深色（B 通道 +4 提"贵气"）与微冷白浅色，1px 边框分层，
/// 色彩只表达状态（ok/err/warn），强调色用中性灰。
class KitharaTheme {
  const KitharaTheme({
    required this.brightness,
    required this.bg,
    required this.bgSide,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.text2,
    required this.text3,
    required this.accent,
    required this.accentSoft,
    required this.ok,
    required this.okSoft,
    required this.warn,
    required this.warnSoft,
    required this.err,
    required this.popBg,
  });

  final Brightness brightness;
  final Color bg;
  final Color bgSide;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color border;
  final Color borderStrong;
  final Color text;
  final Color text2;
  final Color text3;
  final Color accent;
  final Color accentSoft;
  final Color ok;
  final Color okSoft;
  final Color warn;
  final Color warnSoft;
  final Color err;
  final Color popBg;

  /// 深色：aulos :root 默认令牌
  static const dark = KitharaTheme(
    brightness: Brightness.dark,
    bg: Color(0xFF0A0A0D), // OLED 纯黑（辉光对比最强）
    bgSide: Color(0xFF0E0E11),
    surface: Color(0xFF1E1E23),
    surface2: Color(0xFF24242A),
    surface3: Color(0xFF2E2E35),
    border: Color(0xFF2B2B31),
    borderStrong: Color(0xFF3B3B43),
    text: Color(0xFFECECF1),
    text2: Color(0xFFA0A1AB),
    text3: Color(0xFF85868F),
    accent: Color(0xFFB9BEC7),
    accentSoft: Color(0x1ACBD0D9), // rgba(203,208,217,.10)
    ok: Color(0xFF4ADE80),
    okSoft: Color(0x1F4ADE80), // .12
    warn: Color(0xFFFBBF24),
    warnSoft: Color(0x1FFBBF24), // .12
    err: Color(0xFFF87171),
    popBg: Color(0xFF1E1E23), // 实色，不透明
  );

  /// 浅色：aulos [data-theme=light] 覆盖令牌
  static const light = KitharaTheme(
    brightness: Brightness.light,
    bg: Color(0xFFFCFCFD),
    bgSide: Color(0xFFF5F6F8),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF3F3F5),
    surface3: Color(0xFFEAEAEE),
    border: Color(0xFFE8E8EC),
    borderStrong: Color(0xFFD9D9DF),
    text: Color(0xFF1D1D22),
    text2: Color(0xFF5F6068),
    text3: Color(0xFF9A9BA3),
    accent: Color(0xFF757B85),
    accentSoft: Color(0xFFF1F2F4),
    ok: Color(0xFF17803B),
    okSoft: Color(0xFFE7F4EB),
    warn: Color(0xFF946200),
    warnSoft: Color(0xFFFBF2DC),
    err: Color(0xFFCF3A2C),
    popBg: Color(0xFFFFFFFF), // 实色，不透明
  );

  /// 供 MaterialApp 用：Scaffold 底色、字体栈、Material 组件基色。
  ThemeData toThemeData() {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: accent,
      secondary: accent,
      surface: bg,
      // M3 下 Scaffold 底色取 surfaceContainerLowest/surface, 全部钉到令牌,
      // 避免 fromSeed 把 accent 色调混进背景（实测会偏紫）
      surfaceContainerLowest: bg,
      surfaceContainerLow: bg,
      surfaceContainer: bg,
      surfaceContainerHigh: bg,
      surfaceContainerHighest: bg,
    );
    return ThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      useMaterial3: true,
      fontFamilyFallback: const ['PingFang SC', 'Microsoft YaHei UI'],
      dialogTheme: DialogThemeData(
        backgroundColor: popBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
      ),
    );
  }
}

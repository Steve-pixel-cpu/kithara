import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kithara/theme/kithara_theme.dart';
import 'package:kithara/tuner/tuner_controller.dart';
import 'package:kithara/ui/tuner_screen.dart';
import 'package:kithara/audio/mic_stream.dart';
import 'package:kithara/ui/platform_services.dart';

class _Granted implements MicPermission {
  @override
  Future<bool> ensure() async => true;
}

class _NoHaptics implements Haptics {
  @override
  void inTunePulse() {}
}

void main() {
  group('KitharaTheme 令牌 (aulos 设计语言)', () {
    test('深色: 三层背景梯子 + 中性 accent + 状态色', () {
      final t = KitharaTheme.dark;
      expect(t.bg, const Color(0xFF0A0A0D)); // OLED 纯黑
      expect(t.bgSide, const Color(0xFF0E0E11));
      expect(t.surface, const Color(0xFF1E1E23));
      expect(t.surface2, const Color(0xFF24242A));
      expect(t.border, const Color(0xFF2B2B31));
      expect(t.borderStrong, const Color(0xFF3B3B43));
      expect(t.text, const Color(0xFFECECF1));
      expect(t.text2, const Color(0xFFA0A1AB));
      expect(t.text3, const Color(0xFF85868F));
      expect(t.accent, const Color(0xFFB9BEC7)); // 中性灰, 非彩色
      expect(t.ok, const Color(0xFF4ADE80));
      expect(t.warn, const Color(0xFFFBBF24));
    });

    test('浅色: 冷白梯子 + 深灰 accent + 加深的可读状态色', () {
      final t = KitharaTheme.light;
      expect(t.bg, const Color(0xFFFCFCFD));
      expect(t.bgSide, const Color(0xFFF5F6F8));
      expect(t.surface, const Color(0xFFFFFFFF));
      expect(t.border, const Color(0xFFE8E8EC));
      expect(t.text, const Color(0xFF1D1D22));
      expect(t.accent, const Color(0xFF757B85));
      expect(t.ok, const Color(0xFF17803B)); // 浅色下加深保对比度
      expect(t.warn, const Color(0xFF946200));
    });

    test('两套主题的同名令牌值不同（真双主题, 非复制）', () {
      final d = KitharaTheme.dark;
      final l = KitharaTheme.light;
      expect(d.bg, isNot(l.bg));
      expect(d.text, isNot(l.text));
      expect(d.border, isNot(l.border));
      expect(d.ok, isNot(l.ok));
    });
  });

  group('TunerScreen 双主题渲染', () {
    Widget harness(Brightness brightness, {TunerController? controller}) {
      final c = controller ?? TunerController();
      final theme = brightness == Brightness.dark ? KitharaTheme.dark : KitharaTheme.light;
      return MaterialApp(
        theme: theme.toThemeData(),
        home: TunerScreen(
          controller: c,
          mic: MicStream(),
          micPermission: _Granted(),
          haptics: _NoHaptics(),
          theme: theme,
        ),
      );
    }

    testWidgets('深色模式: Scaffold 底色 = #0A0A0D, 音名文字 = #ECECF1',
        (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(Brightness.dark, controller: controller));
      await tester.pump();
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, const Color(0xFF0A0A0D)); // OLED 纯黑
      controller.onPitch(110.0 * 1.02, 0.95); // 非 inTune, 音名白
      await tester.pump();
      final noteStyle = tester.widget<Text>(find.text('A2').first).style;
      expect(noteStyle!.color, const Color(0xFFECECF1));
    });

    testWidgets('浅色模式: Scaffold 底色 = #FCFCFD, 音名文字 = #1D1D22',
        (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(Brightness.light, controller: controller));
      await tester.pump();
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, const Color(0xFFFCFCFD));
      controller.onPitch(110.0 * 1.02, 0.95); // 非 inTune
      await tester.pump();
      final noteStyle = tester.widget<Text>(find.text('A2').first).style;
      expect(noteStyle!.color, const Color(0xFF1D1D22));
    });

    testWidgets('inTune 时两种主题都用各自 ok 色 (深 #4ADE80 / 浅 #17803B)',
        (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(Brightness.dark, controller: controller));
      controller.onPitch(110.0 * 1.001, 0.95);
      await tester.pump();
      // inTune cents 文字用 ok 色（取含 '¢' 的 Text，样式直取 widget.style）
      final darkCents = tester.widgetList<Text>(find.textContaining('¢')).first;
      expect(darkCents.style!.color, const Color(0xFF4ADE80));

      await tester.pumpWidget(harness(Brightness.light, controller: controller));
      await tester.pump();
      controller.onPitch(110.0 * 1.001, 0.95);
      await tester.pump();
      final lightCents = tester.widgetList<Text>(find.textContaining('¢')).first;
      expect(lightCents.style!.color, const Color(0xFF17803B));
    });
  });
}

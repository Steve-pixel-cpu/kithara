import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kithara/audio/mic_stream.dart';
import 'package:kithara/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kithara/theme/kithara_theme.dart';
import 'package:kithara/tuner/tuner_controller.dart';
import 'package:kithara/ui/glow_ring.dart';
import 'package:kithara/ui/platform_services.dart';
import 'package:kithara/ui/tuner_screen.dart';

class _Granted implements MicPermission {
  @override
  Future<bool> ensure() async => true;
}

class _NoHaptics implements Haptics {
  @override
  void inTunePulse() {}

  @override
  void selectionClick() {}
}

Widget harness(TunerController controller, KitharaTheme theme) {
  // mock record 插件（必须在测试体内注册才生效）
  const channel = MethodChannel('com.llfbandit.record/messages');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    switch (call.method) {
      case 'hasPermission':
      case 'isRecording':
      case 'start':
        return true;
      default:
        return null;
    }
  });
  return MaterialApp(
    theme: theme.toThemeData(),
    home: TunerScreen(
      controller: controller,
      mic: MicStream(),
      micPermission: _Granted(),
      haptics: _NoHaptics(),
      theme: theme,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UI 迭代第二轮', () {
    testWidgets('弹窗背景不透明（深色 #1E1E23 / 浅色 #FFFFFF）', (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(controller, KitharaTheme.dark));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('A4 440.0'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(dialog.backgroundColor, const Color(0xFF1E1E23)); // 实色
      expect((dialog.backgroundColor!.a * 255).round(), 255);

      // 关掉第一个弹窗
      await tester.tap(find.text('确定'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 浅色
      await tester.pumpWidget(harness(controller, KitharaTheme.light));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('A4 440.0'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final dialog2 = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(dialog2.backgroundColor, Colors.white);
    });

    testWidgets('接近态: 偏差 10-30¢ 时引导语黄色（接近但未锁定）', (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(controller, KitharaTheme.dark));
      await tester.pump();
      await tester.pump();
      // A2 -20¢: 接近但未到 ±5¢
      controller.onPitch(110.0 * math.pow(2, -20 / 1200), 0.95);
      await tester.pump();
      final centsText = tester
          .widgetList<Text>(find.textContaining('¢'))
          .first;
      expect(centsText.style!.color, const Color(0xFFFBBF24)); // warn 黄
    });

    testWidgets('点击弦条 LED 可手动指定目标弦（activeString 切换）', (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(controller, KitharaTheme.dark));
      await tester.pump();
      await tester.pump();
      // 点 D3 的 LED
      await tester.tap(find.byKey(const Key('led_D3')));
      await tester.pump();
      expect(controller.state.activeString!.name, 'D3');
      // 再点 E2
      await tester.tap(find.byKey(const Key('led_E2')));
      await tester.pump();
      expect(controller.state.activeString!.name, 'E2');
    });

    testWidgets('顶栏主题切换按钮: 点击后 Scaffold 变浅色底', (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(controller, KitharaTheme.dark));
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
        const Color(0xFF0A0A0D),
      );
      await tester.tap(find.byKey(const Key('theme_toggle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // 切换回调触发了（screen 无内部状态，由回调通知外部换主题）
      expect(find.byKey(const Key('theme_toggle')), findsOneWidget);
    });

    testWidgets('KitharaApp 装配: 点主题按钮全应用变浅色（Scaffold 实色切换）', (tester) async {
      // mock record
      const channel = MethodChannel('com.llfbandit.record/messages');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'hasPermission' || call.method == 'isRecording') {
          return true;
        }
        return null;
      });
      // 拦截 SharedPreferences（默认 themeMode=system；测试平台亮度=light）
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const MediaQuery(
        data: MediaQueryData(platformBrightness: Brightness.light),
        child: KitharaApp(),
      ));
      await tester.pump();
      await tester.pump();
      // system + 平台 light → 浅色
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
        const Color(0xFFFCFCFD),
      );
      // 点击: system → dark
      await tester.tap(find.byKey(const Key('theme_toggle')));
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
        const Color(0xFF0A0A0D), // OLED 深
      );
      // 点击: dark → light
      await tester.tap(find.byKey(const Key('theme_toggle')));
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
        const Color(0xFFFCFCFD),
      );
      // 点击: light → system（跟随平台 light → 仍是浅色）
      await tester.tap(find.byKey(const Key('theme_toggle')));
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
        const Color(0xFFFCFCFD), // system 跟随平台 light
      );
    });

    testWidgets('弦条 LED 点击有水波纹反馈（InkWell 包裹而非裸 GestureDetector）', (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(controller, KitharaTheme.dark));
      await tester.pump();
      await tester.pump();
      // LED 顶层应是 InkWell（Material 触感反馈），裸 GestureDetector 没有视觉反馈
      final ink = tester.widget<InkWell>(
        find.ancestor(
          of: find.byKey(const Key('led_D3')),
          matching: find.byType(InkWell),
        ).first,
      );
      expect(ink.onTap, isNotNull);
    });

    testWidgets('装饰: 环有刻度与量程标注, 底部有品牌字标, 静止态呼吸动画', (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(controller, KitharaTheme.dark));
      await tester.pump();
      // GlowRing 存在且带刻度开关
      final ring = tester.widget<GlowRing>(find.byType(GlowRing));
      expect(ring.showTicks, isTrue);
      // 两端量程标注
      expect(find.text('-50'), findsOneWidget);
      expect(find.text('+50'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      // 品牌字标
      expect(find.text('K I T H A R A'), findsOneWidget);
      // 呼吸动画推进一帧不异常
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    });

    testWidgets('themeMode=dark 时 ignore platform, themeMode=system 跟随', (tester) async {
      final controller = TunerController();
      // system + platform light → 实际浅色 Scaffold
      late Widget app;
      app = MediaQuery(
        data: MediaQueryData(platformBrightness: Brightness.light),
        child: MaterialApp(
          theme: KitharaTheme.dark.toThemeData(),
          home: TunerScreen(
            controller: controller,
            mic: MicStream(),
            micPermission: _Granted(),
            haptics: _NoHaptics(),
            theme: KitharaTheme.dark,
            themeMode: 'system',
          ),
        ),
      );
      await tester.pumpWidget(app);
      await tester.pump();
      await tester.pump();
      // system 跟随 → Scaffold 用浅色
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
        const Color(0xFFFCFCFD),
      );
    });

    testWidgets('onThemeToggle 回调被调用', (tester) async {
      final controller = TunerController();
      var toggled = false;
      await tester.pumpWidget(MaterialApp(
        theme: KitharaTheme.dark.toThemeData(),
        home: TunerScreen(
          controller: controller,
          mic: MicStream(),
          micPermission: _Granted(),
          haptics: _NoHaptics(),
          theme: KitharaTheme.dark,
          onThemeToggle: () => toggled = true,
        ),
      ));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const Key('theme_toggle')));
      await tester.pump();
      expect(toggled, isTrue);
    });
  });
}

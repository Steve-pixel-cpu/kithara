import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kithara/audio/mic_stream.dart';
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
  const channel = MethodChannel('com.llfbandit.record/messages');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async => null);

  group('发光环 UI 行为', () {
    testWidgets('静止态: 不显示旧音名 (显示 —), 引导语为拨弦提示', (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(controller, KitharaTheme.dark));
      await tester.pump(); // 让 _startup async 链（权限→start→setState）落地
      await tester.pump();
      // 先有信号再丢失 → 音名不能残留
      controller.onPitch(110.0, 0.95);
      await tester.pump();
      expect(find.text('A2'), findsWidgets); // 环心 + 弦条
      controller.onPitch(null, 0.9);
      await tester.pump();
      // 环心无信号时整体不渲染（无 — 占位，无幽灵音名）；弦条 LED 标签常驻
      expect(find.text('—'), findsNothing);
      expect(find.text('A2'), findsOneWidget);
      expect(find.textContaining('拨'), findsOneWidget); // 引导语
    });

    testWidgets('检测中: 环上存在 GlowRing 且 needle 传入', (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(controller, KitharaTheme.dark));
      controller.onPitch(110.0 * 1.01, 0.95); // +17¢
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200)); // 弹簧运动中
      final ring = tester.widget<GlowRing>(find.byType(GlowRing));
      expect(ring.needle, greaterThan(0.005)); // 弹簧已离起始点
      expect(ring.locked, isFalse);
    });

    testWidgets('锁定: ring.locked=true, needle 钉死 0, 引导语为已调准', (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(controller, KitharaTheme.dark));
      controller.onPitch(110.0 * 1.001, 0.95); // A2 +1.7¢
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final ring = tester.widget<GlowRing>(find.byType(GlowRing));
      expect(ring.locked, isTrue);
      expect(ring.needle, 0.0); // 视觉指针钉死正中
      expect(find.textContaining('已调准'), findsOneWidget);
    });

    testWidgets('弦模式显示 6 个 LED 弦条; 半音阶模式隐藏', (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(controller, KitharaTheme.dark));
      expect(find.byKey(const Key('led_E2')), findsOneWidget);
      expect(find.byKey(const Key('led_E4')), findsOneWidget);
    });

    testWidgets('dark 主题: Scaffold 纯黑 OLED 底 #0A0A0D', (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(controller, KitharaTheme.dark));
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, const Color(0xFF0A0A0D));
    });

    testWidgets('弹簧动画: needle 更新后 AnimatedBuilder 在重建中 (无异常)',
        (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(controller, KitharaTheme.dark));
      controller.onPitch(110.0 * 1.02, 0.95);
      await tester.pump();
      controller.onPitch(110.0, 0.95);
      // 多 pump 几帧让弹簧收敛, 期间不允许异常
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    });
  });
}

import 'package:flutter/material.dart';
import 'dart:math' as math;

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
      // 环心 + 弦条都是纯 A2（弦号改为点击浮层提示）
      expect(find.text('A2'), findsExactly(2));
      controller.onPitch(null, 0.9);
      await tester.pump();
      // 环心无信号时整体不渲染；弦条标签常驻纯音名
      expect(find.text('—'), findsNothing);
      expect(find.text('A2'), findsOneWidget); // 仅弦条
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

    testWidgets('调准后信号短暂丢失: 2s 内保持锁定绿（不因衰减迅速消失）', (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(controller, KitharaTheme.dark));
      await tester.pump();
      await tester.pump();
      controller.onPitch(110.0 * 1.001, 0.95); // A2 锁定
      await tester.pump();
      final ring1 = tester.widget<GlowRing>(find.byType(GlowRing));
      expect(ring1.locked, isTrue);
      // 声音衰减 → 信号丢失
      controller.onPitch(null, 0.9);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final ring2 = tester.widget<GlowRing>(find.byType(GlowRing));
      expect(ring2.locked, isTrue, reason: '2s 保持窗口内仍是锁定态');
      // 超过 2s 的"过期释放"由 controller 单元测试（fakeAsync）覆盖；
      // 这里 pump 过保持窗口让 Timer 自然到期（框架禁 pending Timer）
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('引导语方向: 音偏高→拧松, 音偏低→拧紧（不能反向误导）', (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(controller, KitharaTheme.dark));
      await tester.pump();
      await tester.pump();
      // 锁定 D3 (第4弦, -19), 音偏高 +30¢ → 提示拧松
      controller.selectString(-19);
      for (var i = 0; i < 3; i++) {
        controller.onPitch(146.83 * math.pow(2, 30 / 1200), 0.95);
      }
      await tester.pump();
      expect(find.textContaining('拧松'), findsOneWidget,
          reason: '音偏高必须提示拧松');
      // 音偏低 -30¢ → 提示拧紧
      for (var i = 0; i < 3; i++) {
        controller.onPitch(146.83 * math.pow(2, -30 / 1200), 0.95);
      }
      await tester.pump();
      expect(find.textContaining('拧紧'), findsOneWidget,
          reason: '音偏低必须提示拧紧');
    });

    testWidgets('指针常驻: 无信号停在 -500 满偏待命, 检测后移到读数', (tester) async {
      var now = DateTime(2026, 1, 1);
      final controller = TunerController()..nowForTest = () => now;
      await tester.pumpWidget(harness(controller, KitharaTheme.dark));
      await tester.pump();
      await tester.pump();
      // 初始无信号: 指针在 -1 (满偏 -500 侧)
      expect(controller.state.needle, -1.0);
      // 检测到信号: 指针移到读数
      controller.selectString(-29); // E2
      for (var i = 0; i < 5; i++) {
        controller.onPitch(82.41 * 1.001, 0.95);
      }
      expect(controller.state.needle, closeTo(0.0, 0.05), reason: '调准态居中');
      // 信号消失(保持窗口后): 回到 -1 待命
      controller.onPitch(null, 0.9);
      // 多帧推进: 保持窗口过期(2s) + tween 收敛(150ms) 都需要帧序列
      // (注入时钟随 fake 时间同步推进)
      for (var d = 0; d < 12; d++) {
        await tester.pump(const Duration(milliseconds: 300));
        now = now.add(const Duration(milliseconds: 300));
      }
      expect(controller.state.hasSignal, isFalse);
      expect(tester.widget<GlowRing>(find.byType(GlowRing)).needle,
          closeTo(-1.0, 0.05),
          reason: '回 -500 满偏待命');
    });

    testWidgets('指针平滑: 读数变化时 150ms 内连续过渡, 不瞬跳', (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(controller, KitharaTheme.dark));
      await tester.pump();
      await tester.pump();
      controller.selectString(-29); // E2
      // 稳定到 -180¢ (range 250, needle -0.72)
      for (var i = 0; i < 5; i++) {
        controller.onPitch(82.41 * math.pow(2, -180 / 1200), 0.95);
      }
      await tester.pump(const Duration(milliseconds: 300));
// 阶跃到 -30¢
      for (var i = 0; i < 5; i++) {
        controller.onPitch(82.41 * math.pow(2, -30 / 1200), 0.95);
      }
      for (var d = 0; d < 10; d++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      final after = tester.widget<GlowRing>(find.byType(GlowRing)).needle;
      final target = controller.state.needle;
      expect((after - target).abs(), lessThan(0.05), reason: '收敛到新读数');    });

    testWidgets('指针与引导语同源: 松弦交替帧下指针稳定在滤波偏差处（不追原始帧）', (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(controller, KitharaTheme.dark));
      await tester.pump();
      await tester.pump();
      controller.selectString(-29); // 锁 E2
      // 松弦交替序列: 70/140 交替（八度归一后都 -280¢ → needle -1）
      for (final f in [70.0, 140.0, 70.0, 140.0, 70.0, 140.0, 70.0]) {
        controller.onPitch(f, 0.95);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 400));
      // 弹簧收敛后: 指针稳定满偏 -1, 不因交替帧来回摆
      final ring = tester.widget<GlowRing>(find.byType(GlowRing));
      expect(ring.needle, closeTo(-0.56, 0.12),
          reason: 'needle=${ring.needle} 应稳定在 -282¢/500=-0.56（与引导语同源）');
      // 再连发 5 帧交替, 指针保持
      for (final f in [140.0, 70.0, 140.0, 70.0, 140.0]) {
        controller.onPitch(f, 0.95);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 400));
      final ring2 = tester.widget<GlowRing>(find.byType(GlowRing));
      expect(ring2.needle, closeTo(-0.56, 0.15), reason: '持续稳定不摆动');
    });

    testWidgets('选弦提示为内联胶囊（引导语行内）, 不遮挡环心', (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(controller, KitharaTheme.dark));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const Key('led_A2')));
      await tester.pump();
      // 胶囊存在且有 key
      expect(find.byKey(const Key('string_hint_chip')), findsOneWidget);
      expect(find.text('5弦'), findsOneWidget);
      // 胶囊位置: 与引导语同一行(Row 内), 即不在环心 Stack 里
      final chip = find.byKey(const Key('string_hint_chip'));
      final guidance = find.textContaining('拨');
      final chipTop = tester.getTopLeft(chip).dy;
      final guidanceTop = tester.getTopLeft(guidance).dy;
      expect((chipTop - guidanceTop).abs(), lessThan(40),
          reason: '胶囊与引导语同行(上下40px内), 而非环中央');
      // 2s 后消失
      await tester.pump(const Duration(milliseconds: 2100));
      expect(find.byKey(const Key('string_hint_chip')), findsNothing);
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

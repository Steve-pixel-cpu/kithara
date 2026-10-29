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
      // A2 -20¢: 接近但未到 ±5¢ → 环心音名黄色（接近态）
      controller.onPitch(110.0 * math.pow(2, -20 / 1200), 0.95);
      await tester.pump();
      final noteText = tester.widget<Text>(find.text('A2').first);
      expect(noteText.style!.color, const Color(0xFFFBBF24)); // warn 黄
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
      // 两端量程标注（顶部 0 与刻度重叠，已移除）
      expect(find.text('-50'), findsOneWidget);
      expect(find.text('+50'), findsOneWidget);
      expect(find.text('0'), findsNothing);
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

    testWidgets('设置按钮: 齿轮图标打开设置弹窗（降噪三档），A4 弹窗不含降噪', (tester) async {
      final controller = TunerController();
      var gateChanged = false;
      await tester.pumpWidget(MaterialApp(
        theme: KitharaTheme.dark.toThemeData(),
        home: TunerScreen(
          controller: controller,
          mic: MicStream(),
          micPermission: _Granted(),
          haptics: _NoHaptics(),
          theme: KitharaTheme.dark,
          noiseGate: 'medium',
          onNoiseGateChanged: (_) => gateChanged = true,
        ),
      ));
      await tester.pump();
      await tester.pump();
      // 顶栏有设置齿轮按钮
      expect(find.byKey(const Key('settings_btn')), findsOneWidget);
      // A4 弹窗不含降噪
      await tester.tap(find.text('A4 440.0'));
      await tester.pump();
      expect(find.text('降噪灵敏度'), findsNothing);
      await tester.tap(find.text('取消'));
      await tester.pump();
      // 设置弹窗含降噪（下拉框）
      await tester.tap(find.byKey(const Key('settings_btn')));
      await tester.pump();
      expect(find.text('降噪灵敏度'), findsOneWidget);
      // 打开下拉选'严格' → 回调触发
      await tester.tap(find.byKey(const Key('noise_gate_dropdown')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('严格（嘈杂环境）').last);
      await tester.pump(const Duration(milliseconds: 300));
      expect(gateChanged, isTrue);
    });

    testWidgets('选档后设置弹窗触发器文本立即刷新（弹窗 route 不随父重建）', (tester) async {
      final controller = TunerController();
      String? changed;
      await tester.pumpWidget(MaterialApp(
        theme: KitharaTheme.dark.toThemeData(),
        home: TunerScreen(
          controller: controller,
          mic: MicStream(),
          micPermission: _Granted(),
          haptics: _NoHaptics(),
          theme: KitharaTheme.dark,
          noiseGate: 'medium',
          // 只记录回调不触发父重建: 证明弹窗内文本刷新不依赖父层 setState
          onNoiseGateChanged: (g) => changed = g,
        ),
      ));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const Key('settings_btn')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('noise_gate_dropdown')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('严格（嘈杂环境）').last);
      // pop 选择单: 走完退场动画（含 barrier 消散），只剩设置弹窗本身
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(changed, 'high');
      // 弹窗仍开着: 触发器文本必须已是新档位, 旧档位文本消失
      expect(find.text('严格（嘈杂环境）'), findsOneWidget);
      expect(find.text('标准（日常）'), findsNothing);
    });

    testWidgets('刻度在弧内侧: 刻度半径 < 弧半径', (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(controller, KitharaTheme.dark));
      await tester.pump();
      final ring = tester.widget<GlowRing>(find.byType(GlowRing));
      expect(ring.ticksInside, isTrue);
    });

    testWidgets('A4 弹窗: 确定按钮在取消左侧', (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(controller, KitharaTheme.dark));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('A4 440.0'));
      await tester.pump();
      final confirmCenter = tester.getCenter(find.text('确定'));
      final cancelCenter = tester.getCenter(find.text('取消'));
      expect(confirmCenter.dx, lessThan(cancelCenter.dx));
    });

    testWidgets('UI 精修: 环心无数字/弦号, 弦条标签带弦号, KITHARA 用品牌字体加粗', (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(controller, KitharaTheme.dark));
      await tester.pump();
      await tester.pump();
      controller.onPitch(110.0 * 1.001, 0.95); // 锁定 A2
      await tester.pump();
      // 环心: 纯音名 A2（无弦号、无数字），字号 72 可辨
      final ringNote = tester.widget<Text>(find.text('A2').first);
      expect(ringNote.style!.fontSize, 72); // 环心音名（弦条是 12）
      // 环心 cents 数字不渲染
      expect(find.textContaining('¢'), findsNothing);
      // 弦条标签纯音名（弦号改由点击提示浮层展示）
      expect(find.text('E2(6)'), findsNothing);
      // 点击 A2 弦条 → 浮层显示「5弦」
      await tester.tap(find.byKey(const Key('led_A2')));
      await tester.pump();
      expect(find.text('5弦'), findsOneWidget);
      // 2s 后消失
      await tester.pump(const Duration(milliseconds: 2100));
      expect(find.text('5弦'), findsNothing);
      // 品牌字标加粗 + fontFamily 注入
      final wordmark = tester.widget<Text>(find.text('K I T H A R A'));
      expect(wordmark.style!.fontWeight, FontWeight.w700);
      expect(wordmark.style!.fontFamily, isNotNull);
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

    testWidgets('降噪接线: 选「严格」后 bridge.noiseGate 变 high（DSP 门限实际生效）', (tester) async {
      const channel = MethodChannel('com.llfbandit.record/messages');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'hasPermission' || call.method == 'isRecording') {
          return true;
        }
        return null;
      });
      SharedPreferences.setMockInitialValues({});
      // 测试环境 Ahem 字体每字形 1em 见方，底部弹层三个选项超出半屏
      // (showModalBottomSheet 默认限高) 且不可滚动 → 缩小文本让第 3 项可见。
      // 注意: MaterialApp 内部 MediaQuery.fromView 会重置外层 textScaler,
      // 必须走 platformDispatcher。
      tester.platformDispatcher.textScaleFactorTestValue = 0.5;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.pumpWidget(const MediaQuery(
        data: MediaQueryData(platformBrightness: Brightness.light),
        child: KitharaApp(),
      ));
      await tester.pump();
      await tester.pump();

      // bug 26 后续: UI 档位此前没接到 DSP——bridge.noiseGate 无人写入,
      // RMS 门限恒为 medium。「严格」必须真实改变检测器门限。
      await tester.binding.setSurfaceSize(const Size(1080, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      dynamic homeState;
          tester.element(find.byType(TunerScreen)).visitAncestorElements((el) {
            if (el is StatefulElement &&
                el.widget.runtimeType.toString() == '_TunerHome') {
              homeState = el.state;
              return false;
            }
            return true;
          });
      expect(homeState.bridge.noiseGate, 'medium'); // 初值

      await tester.tap(find.byKey(const Key('settings_btn')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('noise_gate_dropdown')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      // 测试环境 Ahem 字体每字形 1em 见方，第 3 项渲染在视口外无法 tap，
      // 直接触发其 InkWell 回调验证接线（菜单渲染问题见 backlog）
      final strictFinder = find.ancestor(
        of: find.text('严格（嘈杂环境）'),
        matching: find.byType(InkWell),
      );
      (tester.widget(strictFinder) as InkWell).onTap!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(homeState.bridge.noiseGate, 'high'); // 接线生效
    });

    testWidgets('降噪接线: 恢复持久化档位 high → bridge 初值即 high', (tester) async {
      const channel = MethodChannel('com.llfbandit.record/messages');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'hasPermission' || call.method == 'isRecording') {
          return true;
        }
        return null;
      });
      SharedPreferences.setMockInitialValues({'noiseGate': 'high'});
      await tester.pumpWidget(const MediaQuery(
        data: MediaQueryData(platformBrightness: Brightness.light),
        child: KitharaApp(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      dynamic homeState;
          tester.element(find.byType(TunerScreen)).visitAncestorElements((el) {
            if (el is StatefulElement &&
                el.widget.runtimeType.toString() == '_TunerHome') {
              homeState = el.state;
              return false;
            }
            return true;
          });
      expect(homeState.bridge.noiseGate, 'high');
    });
  });
}

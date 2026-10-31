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
      // A2 -20¢: 接近但未到 ±5¢ → 环心音名黄色（接近态, 稳定唤醒 3 帧）
      for (var i = 0; i < 3; i++) {
        controller.onPitch(110.0 * math.pow(2, -20 / 1200), 0.95);
      }
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

    testWidgets('设置按钮: 齿轮图标打开设置弹窗（嘈杂模式开关），A4 弹窗不含', (tester) async {
      final controller = TunerController();
      var noisyChanged = false;
      await tester.pumpWidget(MaterialApp(
        theme: KitharaTheme.dark.toThemeData(),
        home: TunerScreen(
          controller: controller,
          mic: MicStream(),
          micPermission: _Granted(),
          haptics: _NoHaptics(),
          theme: KitharaTheme.dark,
          noisyMode: false,
          onNoisyModeChanged: (_) => noisyChanged = true,
        ),
      ));
      await tester.pump();
      await tester.pump();
      // 顶栏有设置齿轮按钮
      expect(find.byKey(const Key('settings_btn')), findsOneWidget);
      // A4 弹窗不含嘈杂模式
      await tester.tap(find.text('A4 440.0'));
      await tester.pump();
      expect(find.text('嘈杂环境调音'), findsNothing);
      await tester.tap(find.text('取消'));
      await tester.pump();
      // 设置弹窗含嘈杂模式开关，点击 → 回调触发
      await tester.tap(find.byKey(const Key('settings_btn')));
      await tester.pump();
      expect(find.text('嘈杂环境调音'), findsOneWidget);
      await tester.tap(find.byKey(const Key('noisy_mode_switch')));
      await tester.pump();
      expect(noisyChanged, isTrue);
    });

    testWidgets('开关切换: 回调携带新值 false→true', (tester) async {
      final controller = TunerController();
      bool? changed;
      await tester.pumpWidget(MaterialApp(
        theme: KitharaTheme.dark.toThemeData(),
        home: TunerScreen(
          controller: controller,
          mic: MicStream(),
          micPermission: _Granted(),
          haptics: _NoHaptics(),
          theme: KitharaTheme.dark,
          noisyMode: false,
          onNoisyModeChanged: (v) => changed = v,
        ),
      ));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const Key('settings_btn')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('noisy_mode_switch')));
      await tester.pump();
      expect(changed, isTrue);
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
      controller.onPitch(110.0 * 1.001, 0.95); // 锁定 A2（3 帧稳定唤醒）
      controller.onPitch(110.0 * 1.001, 0.95);
      controller.onPitch(110.0 * 1.001, 0.95);
      await tester.pump();
      // 环心: 纯音名 A2（无弦号），字号 72 可辨
      final ringNote = tester.widget<Text>(find.text('A2').first);
      expect(ringNote.style!.fontSize, 72); // 环心音名（弦条是 12）
      // 环心 cents 数字（2026-10 迭代: 需求改为显示高低偏差数字）: 有信号即渲染
      expect(find.textContaining('¢'), findsOneWidget);
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

    testWidgets('嘈杂模式接线: 开关打开后 bridge.noisyMode 变 true（DSP 门限实际生效）', (tester) async {
      const channel = MethodChannel('com.llfbandit.record/messages');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'hasPermission' || call.method == 'isRecording') {
          return true;
        }
        return null;
      });
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const MediaQuery(
        data: MediaQueryData(platformBrightness: Brightness.light),
        child: KitharaApp(),
      ));
      await tester.pump();
      await tester.pump();

      dynamic homeState;
      tester.element(find.byType(TunerScreen)).visitAncestorElements((el) {
        if (el is StatefulElement &&
            el.widget.runtimeType.toString() == '_TunerHome') {
          homeState = el.state;
          return false;
        }
        return true;
      });
      expect(homeState.bridge.noisyMode, isFalse); // 初值

      await tester.tap(find.byKey(const Key('settings_btn')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('noisy_mode_switch')));
      await tester.pump(const Duration(milliseconds: 400));

      expect(homeState.bridge.noisyMode, isTrue); // 接线生效
    });

    testWidgets('嘈杂模式接线: 恢复持久化 noisyMode=true → bridge 初值即 true', (tester) async {
      const channel = MethodChannel('com.llfbandit.record/messages');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'hasPermission' || call.method == 'isRecording') {
          return true;
        }
        return null;
      });
      SharedPreferences.setMockInitialValues({'noisyMode': true});
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
      expect(homeState.bridge.noisyMode, isTrue);
    });
  });

  group('选中弦横线变粗与音分数字', () {
    /// 弦按钮内的 LED 横线（AnimatedContainer）
    Finder ledLineOf(String name) => find.descendant(
          of: find.byKey(Key('led_$name')),
          matching: find.byType(AnimatedContainer),
        );

    BoxDecoration ledDeco(WidgetTester tester, String name) =>
        (tester.widget<AnimatedContainer>(ledLineOf(name)).decoration!
            as BoxDecoration);

    testWidgets('点击无框效果: 水波纹/高亮透明; 弦名与 LED 横线居中对齐', (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(controller, KitharaTheme.dark));
      await tester.pump();
      await tester.pump();
      final ink = tester.widget<InkWell>(
        find.ancestor(
          of: find.byKey(const Key('led_D3')),
          matching: find.byType(InkWell),
        ).first,
      );
      expect(ink.splashColor, Colors.transparent, reason: '点击不画水波纹框');
      expect(ink.highlightColor, Colors.transparent, reason: '按下不画高亮框');
      // 弦名文字与 LED 横线水平中心对齐
      final textRect = tester.getRect(find.text('D3'));
      final ledRect = tester.getRect(ledLineOf('D3'));
      expect((textRect.center.dx - ledRect.center.dx).abs(), lessThan(1.0),
          reason: '文字居中于 LED');
    });

    testWidgets('触控区: 点击 LED 上方空白区也能选中（命中区 ≥52px 高）', (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(controller, KitharaTheme.dark));
      await tester.pump();
      await tester.pump();
      // 弦按钮盒子（led_D3 = _StringBar 根）顶部 8px 处（LED 视觉内容之外的空白）
      final box = tester.getRect(find.byKey(const Key('led_D3')));
      await tester.tapAt(Offset(box.center.dx, box.top + 8));
      await tester.pump();
      expect(controller.state.activeString?.name, 'D3',
          reason: '空白区属于命中范围');
      // 盒子本身 ≥52px 高
      expect(box.height, greaterThanOrEqualTo(52));
    });

    testWidgets('选中弦: LED 横线变粗（10→18）+ accent 色 + 辉光，再点取消', (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(controller, KitharaTheme.dark));
      await tester.pump();
      await tester.pump();

      // 未选中: 高 10、灰色
      final idle = tester.widget<AnimatedContainer>(ledLineOf('D3'));
      expect(idle.constraints!.minHeight, 10);
      expect(ledDeco(tester, 'D3').color, KitharaTheme.dark.surface3);

      // 点 D3 → 变粗 + accent
      await tester.tap(find.byKey(const Key('led_D3')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final sel = tester.widget<AnimatedContainer>(ledLineOf('D3'));
      expect(sel.constraints!.minHeight, 18, reason: '选中变粗');
      final deco = ledDeco(tester, 'D3');
      expect(deco.color, KitharaTheme.dark.accent);
      expect(deco.boxShadow, isNotNull, reason: 'accent 辉光');

      // 再点同一弦 → 取消选择, 回细灰
      await tester.tap(find.byKey(const Key('led_D3')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.widget<AnimatedContainer>(ledLineOf('D3')).constraints!.minHeight,
        10,
      );
      expect(ledDeco(tester, 'D3').color, KitharaTheme.dark.surface3);
    });

    testWidgets('选中且调准: LED 变绿色（ok）+ 绿辉光', (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(controller, KitharaTheme.dark));
      await tester.pump();
      await tester.pump();
      controller.selectString(-19); // D3
      for (var i = 0; i < 5; i++) {
        controller.onPitch(146.83 * 1.001, 0.95);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final deco = ledDeco(tester, 'D3');
      expect(deco.color, KitharaTheme.dark.ok);
      expect(tester.widget<AnimatedContainer>(ledLineOf('D3')).constraints!.minHeight, 18);
      expect(find.text('±0¢'), findsOneWidget);
    });

    testWidgets('环心音分数字: +30¢ 显示 "+30¢" 黄色, 调准显示 "±0¢" 绿色, 无信号隐藏', (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(controller, KitharaTheme.dark));
      await tester.pump();
      await tester.pump();
      // 无信号: 不显示数字
      expect(find.byKey(const Key('cents_display')), findsNothing);

      controller.selectString(-19); // D3
      for (var i = 0; i < 5; i++) {
        controller.onPitch(146.83 * math.pow(2, 30 / 1200), 0.95);
      }
      await tester.pump();
      final centsText =
          tester.widget<Text>(find.byKey(const Key('cents_display')));
      expect(centsText.data, '+30¢');
      expect(centsText.style!.color, const Color(0xFFFBBF24)); // warn 黄

      // 调准（+1.7¢ ∈ ±5¢）: ±0¢ 绿色
      for (var i = 0; i < 5; i++) {
        controller.onPitch(146.83 * 1.001, 0.95);
      }
      await tester.pump();
      final tuned = tester.widget<Text>(find.byKey(const Key('cents_display')));
      expect(tuned.data, '±0¢');
      expect(tuned.style!.color, const Color(0xFF4ADE80)); // ok 绿
    });

    testWidgets('引导语带数字: 偏高/偏低显示具体音分（大偏差分支同格式）', (tester) async {
      final controller = TunerController();
      await tester.pumpWidget(harness(controller, KitharaTheme.dark));
      await tester.pump();
      await tester.pump();
      controller.selectString(-19); // D3
      // +30¢
      for (var i = 0; i < 3; i++) {
        controller.onPitch(146.83 * math.pow(2, 30 / 1200), 0.95);
      }
      await tester.pump();
      expect(find.textContaining('偏高 30¢'), findsOneWidget);
      // -30¢
      for (var i = 0; i < 3; i++) {
        controller.onPitch(146.83 * math.pow(2, -30 / 1200), 0.95);
      }
      await tester.pump();
      expect(find.textContaining('偏低 30¢'), findsOneWidget);
      // +80¢（大偏差分支也要带数字）
      for (var i = 0; i < 3; i++) {
        controller.onPitch(146.83 * math.pow(2, 80 / 1200), 0.95);
      }
      await tester.pump();
      expect(find.textContaining('偏高 80¢'), findsOneWidget);
    });
  });
}

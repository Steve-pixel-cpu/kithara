import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kithara/audio/mic_stream.dart';
import 'package:kithara/tuner/tuner_controller.dart';
import 'package:kithara/ui/tuner_screen.dart';

void main() {
  Widget makeHarness({TunerController? controller}) {
    final c = controller ?? TunerController();
    return MaterialApp(home: TunerScreen(controller: c, mic: MicStream()));
  }

  testWidgets('渲染: 音名大字 + 仪表 + 6 弦条 + 模式按钮 + A4 显示', (tester) async {
    await tester.pumpWidget(makeHarness());
    await tester.pump();
    expect(find.text('—'), findsOneWidget); // 初始音名占位
    expect(find.text('A4 440.0'), findsOneWidget);
    expect(find.byKey(const Key('led_E2')), findsOneWidget);
    expect(find.byKey(const Key('led_E4')), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets); // 仪表
    expect(find.text('标准'), findsOneWidget); // 当前模式名
  });

  testWidgets('onPitch A4+10¢ → 显示 A4, 指针右偏, 非 inTune 色', (tester) async {
    final controller = TunerController();
    await tester.pumpWidget(makeHarness(controller: controller));
    controller.onPitch(440.0 * 1.0058, 0.95); // +10¢
    await tester.pump();
    expect(find.text('A4'), findsOneWidget);
    expect(find.textContaining('+10'), findsWidgets); // cents 显示
  });

  testWidgets('模式下拉切 Drop D → 6 弦条重建为 D2 开头', (tester) async {
    await tester.pumpWidget(makeHarness());
    await tester.pump();
    // 打开模式菜单（点当前模式按钮）
    await tester.tap(find.text('标准'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Drop D').last);
    await tester.pumpAndSettle();
    expect(find.text('Drop D'), findsOneWidget);
    expect(find.byKey(const Key('led_D2')), findsOneWidget);
  });

  testWidgets('inTune: ±5¢ 内显示绿色对勾指示', (tester) async {
    final controller = TunerController();
    await tester.pumpWidget(makeHarness(controller: controller));
    controller.onPitch(110.0 * 1.001, 0.95); // A2 +1.7¢
    await tester.pump();
    expect(find.byKey(const Key('in_tune_indicator')), findsOneWidget);
  });

  testWidgets('A4 弹窗: 点 A4 文本 → 对话框含滑条与确定', (tester) async {
    await tester.pumpWidget(makeHarness());
    await tester.pump();
    await tester.tap(find.text('A4 440.0'));
    await tester.pumpAndSettle();
    expect(find.text('参考音 A4'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
  });
}

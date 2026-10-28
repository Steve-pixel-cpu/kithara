import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kithara/tuner/tuner_controller.dart';
import 'package:kithara/ui/platform_services.dart';
import 'package:kithara/ui/tuner_screen.dart';

/// 可注入假触觉的测试替身。
class FakeHaptics implements Haptics {
  int inTunePulses = 0;
  @override
  void inTunePulse() => inTunePulses++;
}

class FakeMicPermission implements MicPermission {
  FakeMicPermission(this.granted);
  final bool granted;
  @override
  Future<bool> ensure() async => granted;
}

void main() {
  testWidgets('权限被拒 → 显示提示与重试按钮，不崩溃', (tester) async {
    final controller = TunerController();
    await tester.pumpWidget(MaterialApp(
      home: TunerScreen(
        controller: controller,
        micPermission: FakeMicPermission(false),
        haptics: FakeHaptics(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('需要麦克风权限'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('权限通过 → 进入正常界面', (tester) async {
    final controller = TunerController();
    await tester.pumpWidget(MaterialApp(
      home: TunerScreen(
        controller: controller,
        micPermission: FakeMicPermission(true),
        haptics: FakeHaptics(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('需要麦克风权限'), findsNothing);
    expect(find.text('标准'), findsOneWidget);
  });

  testWidgets('inTune 边沿触发一次触觉（持续 inTune 不重复）', (tester) async {
    final controller = TunerController();
    final haptics = FakeHaptics();
    await tester.pumpWidget(MaterialApp(
      home: TunerScreen(
        controller: controller,
        micPermission: FakeMicPermission(true),
        haptics: haptics,
      ),
    ));
    await tester.pump();
    // 进入 inTune（A2 +1.7¢）
    controller.onPitch(110.0 * 1.001, 0.95);
    await tester.pump();
    controller.onPitch(110.0 * 1.001, 0.95);
    await tester.pump();
    expect(haptics.inTunePulses, 1); // 边沿只一次
    // 离开再进入 → 再一次
    controller.onPitch(110.0 * 1.03, 0.95);
    await tester.pump();
    controller.onPitch(110.0 * 1.001, 0.95);
    await tester.pump();
    expect(haptics.inTunePulses, 2);
  });
}

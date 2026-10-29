@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kithara/audio/mic_stream.dart';
import 'package:kithara/theme/kithara_theme.dart';
import 'package:kithara/tuner/tuner_controller.dart';
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

void main() {
  setUp(() {
    // mock record 插件通道（测试环境无平台实现）
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('com.llfbandit.record/messages');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'create':
          return null;
        case 'hasPermission':
        case 'isRecording':
          return true;
        case 'start':
          return null;
        case 'stop':
          return null;
        default:
          return null;
      }
    });
  });

  testWidgets('生成深浅主题截图', (tester) async {
    // physicalSize = 逻辑尺寸 × dpr
    tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    for (final (name, theme) in [('dark', KitharaTheme.dark), ('light', KitharaTheme.light)]) {
      final controller = TunerController();
      await tester.pumpWidget(MaterialApp(
        theme: theme.toThemeData(),
        home: TunerScreen(
          controller: controller,
          mic: MicStream(),
          micPermission: _Granted(),
          haptics: _NoHaptics(),
          theme: theme,
        ),
      ));
      // 模拟检测中 A2 -12¢
      controller.onPitch(110.0 * 0.9931, 0.95);
      await tester.pump();
      await expectLater(
        find.byType(TunerScreen),
        matchesGoldenFile('goldens/tuner_$name.png'),
      );
    }
  });
}

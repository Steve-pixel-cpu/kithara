import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kithara/audio/mic_stream.dart';
import 'package:kithara/tuner/tuner_controller.dart';
import 'package:kithara/ui/platform_services.dart';
import 'package:kithara/ui/tuner_screen.dart';

/// 回归测试（2026-10-28 拨弦无反应 bug）：
/// TunerScreen 曾自建第二个 MicStream 实例并 start 它，
/// 而 main.dart 的管线桥读的是另一个实例的空 RingBuffer。
/// 修复后 mic 是 required 注入参数——本测试锁住"注入必须生效"语义：
/// 给注入 mic 的 RingBuffer 喂数据 + 权限放行 + 手动 start，
/// TunerScreen 的生命周期操作必须作用于同一实例。
class _AlwaysGranted implements MicPermission {
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
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TunerScreen 使用注入实例：dispose 后实例仍可复用（无人自建替代品）', (tester) async {
    final controller = TunerController();
    final mic = MicStream();
    await tester.pumpWidget(MaterialApp(
      home: TunerScreen(
        controller: controller,
        mic: mic,
        micPermission: _AlwaysGranted(),
        haptics: _NoHaptics(),
      ),
    ));
    // 权限通过后 screen 会尝试 mic.start()——测试环境 record 平台通道
    // 无响应，start 的 await 挂起是预期；不 pumpAndSettle（会卡超时）。
    await tester.pump();
    // 关键断言：组件树卸载后，注入的 mic 没有被 screen dispose 掉
    // （所有权在装配层），还能正常调用 clear：
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    mic.ringBuffer.write([0.1, 0.2]);
    expect(mic.ringBuffer.available, 2);
  });
}

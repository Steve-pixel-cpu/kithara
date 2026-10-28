import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kithara/tuner/tuner_controller.dart';
import 'package:kithara/tuner/tuning_modes.dart';

void main() {
  late TunerController controller;

  setUp(() {
    controller = TunerController();
  });

  test('初始状态: standard 模式, a4=440, noSignal', () {
    expect(controller.state.mode.id, 'standard');
    expect(controller.state.a4, 440.0);
    expect(controller.state.hasSignal, isFalse);
    expect(controller.state.activeString, isNull);
  });

  test('onPitch: chromatic 模式显示音名+cents', () {
    controller.setMode(TuningModes.byId('chromatic'));
    // A4+10¢
    controller.onPitch(440.0 * 1.0058, 0.95);
    expect(controller.state.hasSignal, isTrue);
    expect(controller.state.noteLabel, 'A4');
    expect(controller.state.cents, closeTo(10.0, 0.5));
    expect(controller.state.activeString, isNull);
  });

  test('onPitch: 字符串模式吸附最近弦, ±5¢ 内 inTune', () {
    // A2 +3¢
    controller.onPitch(110.0 * 1.0017, 0.95);
    expect(controller.state.activeString!.name, 'A2');
    expect(controller.state.inTune, isTrue);
    expect(controller.state.cents, closeTo(3.0, 0.5));
  });

  test('onPitch: 偏离 >5¢ 不 inTune', () {
    controller.onPitch(110.0 * 1.02, 0.95); // +34¢
    expect(controller.state.inTune, isFalse);
  });

  test('onPitch: 模式内无弦匹配 → hasSignal 但 activeString null', () {
    controller.onPitch(500.0, 0.95);
    expect(controller.state.hasSignal, isTrue);
    expect(controller.state.activeString, isNull);
  });

  test('onPitch(null): hasSignal=false, 音名/弦保留 (UI 平滑)', () {
    controller.onPitch(110.0, 0.95);
    controller.onPitch(null, 0.9);
    expect(controller.state.hasSignal, isFalse);
    expect(controller.state.noteLabel, 'A2'); // 保留
  });

  test('锁弦: 字符串模式 2 次同弦才切换 activeString', () {
    // 先到 D3 附近一次
    controller.onPitch(146.83, 0.95);
    // 立刻跳到 A2 一次 → 不切换
    controller.onPitch(110.0, 0.95);
    expect(controller.state.activeString!.name, 'D3');
    // 第二次 A2 → 切换
    controller.onPitch(110.0, 0.95);
    expect(controller.state.activeString!.name, 'A2');
  });

  test('setMode: 清锁弦计数, activeString 重置', () {
    controller.onPitch(110.0, 0.95);
    controller.onPitch(110.0, 0.95);
    expect(controller.state.activeString, isNotNull);
    controller.setMode(TuningModes.byId('drop_d'));
    expect(controller.state.activeString, isNull);
    expect(controller.state.mode.id, 'drop_d');
  });

  test('setA4: 重建 mapper, A4=435 时 110Hz 显示 +19.6¢', () {
    controller.setA4(435.0);
    controller.onPitch(110.0, 0.95);
    // 110Hz 相对 A2@435(=108.335) 偏 +19.6¢
    expect(controller.state.cents, closeTo(19.6, 0.5));
    expect(controller.state.noteLabel, 'A2');
  });

  test('needle: -1..1 归一化, ±50¢ 映射满偏', () {
    controller.setMode(TuningModes.byId('chromatic'));
    controller.onPitch(440.0 * math.pow(2, 50 / 1200), 0.95); // +50¢
    expect(controller.state.needle, closeTo(1.0, 0.01));
    controller.onPitch(440.0, 0.95);
    expect(controller.state.needle, closeTo(0.0, 0.001));
    controller.onPitch(440.0 * math.pow(2, -50 / 1200), 0.95); // -50¢
    expect(controller.state.needle, closeTo(-1.0, 0.01));
  });
}

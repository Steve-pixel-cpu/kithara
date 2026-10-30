import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kithara/audio/ring_buffer.dart';
import 'package:kithara/dsp/pitch_detector.dart';
import 'package:kithara/tuner/tuner_controller.dart';
import 'package:kithara/tuner/tuner_pipeline.dart';
import 'package:kithara/tuner/tuning_modes.dart';

Float32List synth(double f0, {int n = 5000}) {
  final buf = Float32List(n);
  for (var i = 0; i < n; i++) {
    final t = i / 44100.0;
    buf[i] = 0.5 * math.sin(2 * math.pi * f0 * t) +
        0.25 * math.sin(2 * math.pi * 2 * f0 * t) +
        0.125 * math.sin(2 * math.pi * 3 * f0 * t);
  }
  return buf;
}

void main() {
  test('全链路 -50¢: E2 低 50¢ (80.06Hz) → needle 满偏 -1', () {
    final rb = RingBuffer(8192);
    final controller = TunerController();
    final pipeline = TunerPipeline(
      ringBuffer: rb,
      detector: PitchDetector(),
      controller: controller,
    );
    final f = 82.41 * math.pow(2, -50 / 1200);
    rb.write(synth(f));
    pipeline.tick();
    rb.write(synth(f));
    pipeline.tick();
    rb.write(synth(f));
    pipeline.tick();
    expect(controller.state.noteLabel, 'E2');
    expect(controller.state.cents, closeTo(-50, 3), reason: 'cents=${controller.state.cents}');
    // -50¢ 触发滞回扩档到 ±250, needle = -50/250 = -0.2（量程自适应后
    // 满偏不再出现在恰好 ±50 处, 更大偏差才逐渐到边）
    expect(controller.state.range, 250);
    expect(controller.state.needle, closeTo(-0.2, 0.05), reason: 'needle=${controller.state.needle}');
  });

  test('尤克里里模式: 管线以模式声明的范围重建 detector（392Hz 可检出）', () {
    final rb = RingBuffer(8192);
    final controller = TunerController();
    final dropD = TuningModes.byId('drop_d');
    final uke = TuningModes.byId('ukulele');
    // 模拟桥的 detector 生命周期: 范围由模式声明
    var detector = PitchDetector(
        minFreq: dropD.detectorMinFreq, maxFreq: dropD.detectorMaxFreq);
    final pipeline = TunerPipeline(
      ringBuffer: rb,
      detector: detector,
      controller: controller,
    );
    controller.setMode(dropD);
    rb.write(synth(110.0));
    pipeline.tick();
    rb.write(synth(110.0));
    pipeline.tick();
    rb.write(synth(110.0));
    pipeline.tick();
    expect(controller.state.noteLabel, 'A2');

    // 切到 ukulele → 桥按声明重建
    controller.setMode(uke);
    detector = PitchDetector(
        minFreq: uke.detectorMinFreq, maxFreq: uke.detectorMaxFreq);
    final pipeline2 = TunerPipeline(
      ringBuffer: rb,
      detector: detector,
      controller: controller,
    );
    rb.write(synth(392.0));
    pipeline2.tick();
    rb.write(synth(392.0));
    pipeline2.tick();
    rb.write(synth(392.0));
    pipeline2.tick();
    expect(controller.state.noteLabel, 'G4');
    expect(controller.state.activeString!.name, 'G4');
  });

  test('端到端: 110Hz 合成信号 → pipeline → controller 显示 A2 / inTune', () {
    final rb = RingBuffer(8192);
    final det = PitchDetector();
    final controller = TunerController();
    final pipeline = TunerPipeline(
      ringBuffer: rb,
      detector: det,
      controller: controller,
    );

    rb.write(synth(110.0));
    pipeline.tick();
    rb.write(synth(110.0));
    pipeline.tick();
    rb.write(synth(110.0));
    pipeline.tick();

    final s = controller.state;
    expect(s.hasSignal, isTrue);
    expect(s.noteLabel, 'A2');
    expect(s.cents, closeTo(0.0, 1.0));
    expect(s.activeString!.name, 'A2');
    expect(s.inTune, isTrue);
  });
  test('端到端: 静音帧 → hasSignal=false, noteLabel 保留', () {
    final rb = RingBuffer(8192);
    final controller = TunerController();
    final pipeline = TunerPipeline(
      ringBuffer: rb,
      detector: PitchDetector(),
      controller: controller,
    );

    rb.write(synth(110.0));
    pipeline.tick();
    rb.write(synth(110.0));
    pipeline.tick();
    rb.write(synth(110.0));
    pipeline.tick();
    // 全零帧
    rb.write(Float32List(5000));
    pipeline.tick();

    expect(controller.state.hasSignal, isFalse);
    expect(controller.state.noteLabel, 'A2');
  });

  test('tick: 缓冲不足 4096 时安全无操作', () {
    final rb = RingBuffer(8192);
    final controller = TunerController();
    final pipeline = TunerPipeline(
      ringBuffer: rb,
      detector: PitchDetector(),
      controller: controller,
    );
    rb.write(List.filled(100, 0.1));
    pipeline.tick(); // 不应抛异常
    expect(controller.state.hasSignal, isFalse);
  });

  test('端到端 Drop D: 73.42Hz → 活动弦 D2', () {
    final rb = RingBuffer(8192);
    final controller = TunerController();
    final pipeline = TunerPipeline(
      ringBuffer: rb,
      detector: PitchDetector(),
      controller: controller,
    );
    controller.setMode(TuningModes.byId('drop_d'));

    rb.write(synth(73.42));
    pipeline.tick();
    rb.write(synth(73.42));
    pipeline.tick();
    rb.write(synth(73.42));
    pipeline.tick();

    expect(controller.state.activeString!.name, 'D2');
  });
}

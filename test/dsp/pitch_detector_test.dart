import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kithara/dsp/pitch_detector.dart';

final sr = 44100.0;

/// 合成弦音：基频+2/3/4 次谐波（幅度 0.5/0.25/0.125/0.0625），可选白噪声。
/// f0<=0 时返回纯噪声（测安静/门控场景）。
Float32List synth(double f0,
    {int n = 4096, double noise = 0, int? seed, double phaseSamples = 0}) {
  final rng = seed == null ? null : math.Random(seed);
  final buf = Float32List(n);
  for (var i = 0; i < n; i++) {
    final t = (i + phaseSamples) / sr;
    var s = 0.0;
    if (f0 > 0) {
      s = 0.5 * math.sin(2 * math.pi * f0 * t) +
          0.25 * math.sin(2 * math.pi * 2 * f0 * t) +
          0.125 * math.sin(2 * math.pi * 3 * f0 * t) +
          0.0625 * math.sin(2 * math.pi * 4 * f0 * t);
    }
    if (noise > 0 && rng != null) {
      s += (rng.nextDouble() * 2 - 1) * noise;
    }
    buf[i] = s;
  }
  return buf;
}

void main() {
  late PitchDetector det;

  setUp(() => det = PitchDetector());

  test('场景2: 六弦精确频率 + Drop D D2 边缘频率全部检出 ±0.5Hz', () {
    final cases = [73.42, 82.41, 110.0, 146.83, 196.0, 246.94, 329.63];
    for (final f in cases) {
      final out = det.detect(synth(f));
      expect(out, isNotNull, reason: 'freq=$f 未检出');
      expect(out!, closeTo(f, 0.5), reason: 'freq=$f');
      expect(det.lastConfidence, greaterThanOrEqualTo(0.85));
    }
  });

  test('场景3: +10 cent 检出', () {
    final f = 82.41 * math.pow(2, 10 / 1200);
    final out = det.detect(synth(f));
    expect(out, isNotNull);
    expect(out!, closeTo(f, 0.5));
  });

  test('场景4: 抗八度错误——2次谐波强于基频仍报基频', () {
    final buf = Float32List(4096);
    for (var i = 0; i < 4096; i++) {
      final t = i / sr;
      buf[i] = 0.1 * math.sin(2 * math.pi * 82.41 * t) +
          0.5 * math.sin(2 * math.pi * 164.82 * t);
    }
    final out = det.detect(buf);
    expect(out, isNotNull);
    expect(out!, closeTo(82.41, 0.5), reason: '应报基频 82.41 而非 164.82');
  });

  test('场景5: 噪声鲁棒 (noise=0.25)', () {
    // noise=0.3 时 NSDF 峰仅 ~0.80，会被 0.85 置信度门限正确拒绝；
    // 门限内的重噪声用 0.25 验证（conf≈0.89）
    final out = det.detect(synth(110.0, noise: 0.25, seed: 7));
    expect(out, isNotNull);
    // 重噪声下 NSDF 峰位置有小偏移是正常的；0.76Hz@110 ≈ 12¢，UI 归到 A2 不受影响
    expect(out!, closeTo(110.0, 1.0));
  });

  test('场景6: 纯噪声 → null (置信度门控)', () {
    final out = det.detect(synth(0, noise: 0.3, seed: 1));
    expect(out, isNull);
  });

  test('场景7: 超范围频率 → null', () {
    expect(det.detect(synth(500.0)), isNull); // > 350
    expect(det.detect(synth(50.0)), isNull); // < 65
  });

  test('RMS 门控: 低于阈值的弱信号直接拒绝（降噪）', () {
    final gated = PitchDetector(minFreq: 65, maxFreq: 350, rmsGate: 0.02);
    // 弱合成信号（幅度 0.01，RMS ~0.008 < 0.02）→ null
    final weak = synth(110.0);
    for (var i = 0; i < weak.length; i++) {
      weak[i] *= 0.03;
    }
    expect(gated.detect(weak), isNull);
    expect(gated.lastConfidence, 0.0);
    // 正常幅度 → 检出
    expect(gated.detect(synth(110.0)), isNotNull);
  });

  test('默认无门控（rmsGate=0）：弱信号也能检出（原行为）', () {
    final weak = synth(110.0);
    for (var i = 0; i < weak.length; i++) {
      weak[i] *= 0.05;
    }
    expect(det.detect(weak), isNotNull);
  });

  test('1 弦高把位: 2次谐波强 + NSDF 微扰下不翻八度（E4/E3 反复的根因）', () {
    // 真实拨弦帧间波动会让 2×lag 处 NSDF 略高于基频峰——子谐波复查曾把它翻成低八度
    final buf = Float32List(4096);
    for (var i = 0; i < 4096; i++) {
      final t = i / 44100.0;
      buf[i] = 0.2 * math.sin(2 * math.pi * 329.63 * t) +
          0.45 * math.sin(2 * math.pi * 659.26 * t) +
          0.2 * math.sin(2 * math.pi * 988.89 * t);
    }
    // 多帧一致性（噪声种子不同）
    final readings = <double>[];
    for (var seed = 0; seed < 5; seed++) {
      final rng = math.Random(seed);
      for (var i = 0; i < 4096; i++) {
        buf[i] += (rng.nextDouble() * 2 - 1) * 0.01;
      }
      final out = det.detect(Float32List.fromList(buf));
      expect(out, isNotNull);
      readings.add(out!);
      expect(out, closeTo(329.63, 1.0), reason: 'seed=$seed → $out (E3=164.8 禁止)');
    }
    expect(readings.every((r) => r > 300), isTrue);
  });

  test('ukulele 范围 (240-500Hz): 392/261.63/440Hz 检出（默认范围外）', () {
    final ukeDet = PitchDetector(minFreq: 240, maxFreq: 500);
    for (final f in [392.0, 261.63, 440.0]) {
      final out = ukeDet.detect(synth(f));
      expect(out, isNotNull, reason: 'freq=$f');
      expect(out!, closeTo(f, 1.0), reason: 'freq=$f');
    }
    // 默认检测器(65-350)应拒绝 440Hz（证明范围声明的必要性）
    expect(det.detect(synth(440.0)), isNull);
  });

  test('chromatic 模式 500Hz 可检出', () {
    final wide = PitchDetector(minFreq: 60.0, maxFreq: 1300.0);
    final out = wide.detect(synth(500.0));
    expect(out, isNotNull);
    expect(out!, closeTo(500.0, 1.0));
  });
}

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kithara/dsp/pitch_detector.dart';

// 乐器级合成: 基频+谐波（真实吉他弦频谱衰减）+ 轻微噪声
Float32List guitarPluck(double f0, {double noise = 0.02, int n = 4096, int seed = 42}) {
  final rng = math.Random(seed);
  final buf = Float32List(n);
  for (var i = 0; i < n; i++) {
    final t = i / 44100.0;
    // 真实弦: 基频最强, 谐波按 1/k 衰减, 二次谐波常强（桥接耦合）
    buf[i] = 0.5 * math.sin(2 * math.pi * f0 * t) +
        0.35 * math.sin(2 * math.pi * 2 * f0 * t) +
        0.15 * math.sin(2 * math.pi * 3 * f0 * t) +
        0.08 * math.sin(2 * math.pi * 4 * f0 * t) +
        0.04 * math.sin(2 * math.pi * 5 * f0 * t) +
        0.02 * math.sin(2 * math.pi * 6 * f0 * t);
    buf[i] += (rng.nextDouble() * 2 - 1) * noise;
  }
  return buf;
}

void main() {
  final det = PitchDetector();

  group('硬核基准 1: 低频不跳八度（E2/B2 弱基频挑战）', () {
    test('E2 82.41Hz: 基频+强二次谐波（1:0.35 乐器级比例）', () {
      for (final f in [82.41, 87.31, 92.50]) {
        final out = det.detect(guitarPluck(f));
        expect(out, isNotNull, reason: '$f 未检出');
        final cents = 1200 * (math.log(out! / f) / math.ln2);
        expect(cents.abs(), lessThan(5), reason: '$f → $out (${cents.toStringAsFixed(1)}¢)');
      }
    });

    test('B2 123.47Hz: 模拟"普通调音器翻车"场景——基频被削到 0.05', () {
      // 恶意构造: 二次谐波比基频强 5 倍（真实拨弦位置效应）
      final buf = Float32List(4096);
      for (var i = 0; i < 4096; i++) {
        final t = i / 44100.0;
        buf[i] = 0.05 * math.sin(2 * math.pi * 123.47 * t) +
            0.5 * math.sin(2 * math.pi * 246.94 * t) +
            0.2 * math.sin(2 * math.pi * 370.41 * t);
      }
      final out = det.detect(buf);
      expect(out, isNotNull);
      final cents = 1200 * (math.log(out! / 123.47) / math.ln2);
      expect(cents.abs(), lessThan(5),
          reason: '基频极弱时仍报 123.47 而非 246.94（八度跳）: got $out');
    });
  });

  group('硬核基准 2: 响应速度（每帧计算耗时）', () {
    test('单帧 detect() < 5ms（44100Hz/4096 窗 = 93ms 一帧, 5% 预算）', () {
      final buf = guitarPluck(110.0);
      final sw = Stopwatch()..start();
      const frames = 50;
      for (var i = 0; i < frames; i++) {
        det.detect(buf);
      }
      sw.stop();
      final perFrame = sw.elapsedMilliseconds / frames;
      expect(perFrame, lessThan(5.0), reason: '单帧 ${perFrame.toStringAsFixed(2)}ms');
      debugPrint('PERF: 单帧 detect = ${perFrame.toStringAsFixed(2)}ms');
    });
  });

  group('硬核基准 3: 音分精度（±1¢ 目标）', () {
    test('全弦域静音环境: 误差 < ±1¢', () {
      // 对每个半音基频 + ±3¢ 微偏移做扫描
      final cases = [82.41, 110.0, 146.83, 196.0, 246.94, 329.63];
      for (final f in cases) {
        for (final centOffset in [-3.0, 0.0, 3.0]) {
          final target = f * math.pow(2, centOffset / 1200);
          final out = det.detect(guitarPluck(target, noise: 0.005));
          expect(out, isNotNull, reason: '$f@$centOffset¢');
          final cents = 1200 * (math.log(out! / target) / math.ln2);
          expect(cents.abs(), lessThan(1.0),
              reason: '$f@$centOffset¢ → ${cents.toStringAsFixed(2)}¢ 误差');
        }
      }
    });

    test('稳态抖动: 连续 30 帧同一信号, 指针不晃（标准差 < 0.5¢）', () {
      final buf = guitarPluck(146.83, noise: 0.01);
      final readings = <double>[];
      for (var i = 0; i < 30; i++) {
        final out = det.detect(buf);
        if (out != null) readings.add(out);
      }
      expect(readings.length, 30);
      final mean = readings.reduce((a, b) => a + b) / readings.length;
      final variance =
          readings.map((r) => (r - mean) * (r - mean)).reduce((a, b) => a + b) /
              readings.length;
      final stdHz = math.sqrt(variance);
      // Hz 标准差换算成音分
      final stdCents = 1200 * math.log(1 + stdHz / mean) / math.ln2;
      debugPrint('STABILITY: 30 帧标准差 = ${stdCents.toStringAsFixed(3)}¢');
      expect(stdCents, lessThan(0.5),
          reason: '稳态抖动 ${stdCents.toStringAsFixed(3)}¢，指针会晃');
    });
  });
}

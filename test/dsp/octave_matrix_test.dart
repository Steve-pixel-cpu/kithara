import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kithara/dsp/pitch_detector.dart';

Float32List synth(String f0s, double f0, {double h2 = 0.4, double h3 = 0.2, double noise = 0.01}) {
  final buf = Float32List(4096);
  final rng = math.Random(7);
  for (var i = 0; i < 4096; i++) {
    final t = i / 44100.0;
    buf[i] = 0.35 * math.sin(2 * math.pi * f0 * t) +
        h2 * math.sin(2 * math.pi * 2 * f0 * t) +
        h3 * math.sin(2 * math.pi * 3 * f0 * t) +
        0.08 * math.sin(2 * math.pi * 4 * f0 * t);
    buf[i] += (rng.nextDouble() * 2 - 1) * noise;
  }
  return buf;
}

void main() {
  test('全调弦八度稳定性矩阵: 每种调弦的每根弦, 强泛音不翻八度', () {
    // (名称, [各弦频率], detector范围)
    final tunings = <(String, List<double>, (double, double))>[
      ('standard',  [82.41, 110.0, 146.83, 196.0, 246.94, 329.63], (65, 350)),
      ('drop_d',    [73.42, 110.0, 146.83, 196.0, 246.94, 329.63], (65, 350)),
      ('open_d',    [73.42, 110.0, 146.83, 185.0, 220.0, 293.66], (65, 350)),
      ('open_g',    [73.42, 98.0, 146.83, 196.0, 246.94, 293.66], (65, 350)),
      ('dadgad',    [73.42, 110.0, 146.83, 196.0, 246.94, 293.66], (65, 350)),
      ('drop_c',    [65.41, 98.0, 130.81, 174.61, 220.0, 293.66], (60, 350)),
      ('eb',        [77.78, 103.83, 138.59, 185.0, 233.08, 311.13], (65, 350)),
      ('d_tuning',  [73.42, 98.0, 130.81, 174.61, 220.0, 293.66], (65, 350)),
      ('ukulele',   [392.0, 261.63, 329.63, 440.0], (240, 500)),
      ('ukulele_low_g', [196.0, 261.63, 329.63, 440.0], (180, 500)),
      ('ukulele_bari', [146.83, 196.0, 246.94, 329.63], (140, 400)),
    ];
    var failures = <String>[];
    for (final (name, freqs, range) in tunings) {
      final det = PitchDetector(minFreq: range.$1, maxFreq: range.$2);
      for (final f in freqs) {
        // 强泛音场景（拨弦位置效应）
        for (final (h2, h3) in [(0.4, 0.2), (0.6, 0.3), (0.3, 0.5)]) {
          final out = det.detect(synth('x', f, h2: h2, h3: h3));
          if (out == null) {
            failures.add('$name ${f}Hz h2=$h2: null');
            continue;
          }
          final cents = 1200 * (math.log(out / f) / math.ln2);
          if (cents.abs() > 5) {
            failures.add('$name ${f}Hz h2=$h2 h3=$h3 → ${out.toStringAsFixed(1)}Hz (${cents.toStringAsFixed(1)}c)');
          }
        }
      }
    }
    expect(failures, isEmpty, reason: failures.take(8).join('\n'));
  });
}

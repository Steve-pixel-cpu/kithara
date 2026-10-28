import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kithara/dsp/fft.dart';

void main() {
  group('FFT 4096', () {
    final fft = FFT(4096);

    test('单频正弦在正确 bin 出峰', () {
      final re = Float64List(4096), im = Float64List(4096);
      const freq = 82.41, sr = 44100.0;
      for (var i = 0; i < 4096; i++) {
        re[i] = math.sin(2 * math.pi * freq * i / sr);
      }
      fft.transform(re, im);
      var best = 0, bestMag = -1.0;
      for (var k = 1; k < 2048; k++) {
        final mag = re[k] * re[k] + im[k] * im[k];
        if (mag > bestMag) { bestMag = mag; best = k; }
      }
      expect(best, anyOf(7, 8)); // 82.41·4096/44100 ≈ 7.65
    });

    test('直流信号能量集中 bin 0', () {
      final re = Float64List.fromList(List.filled(4096, 1.0));
      final im = Float64List(4096);
      fft.transform(re, im);
      expect(re[0], closeTo(4096, 1e-3));
      for (var k = 1; k < 2048; k++) {
        expect(math.sqrt(re[k] * re[k] + im[k] * im[k]), lessThan(1e-3));
      }
    });

    test('逆变换往返恢复原信号 (误差 < 1e-3)', () {
      final re = Float64List(4096), im = Float64List(4096);
      final rng = math.Random(42);
      for (var i = 0; i < 4096; i++) {
        re[i] = rng.nextDouble() * 2 - 1;
        im[i] = rng.nextDouble() * 2 - 1;
      }
      final re0 = Float64List.fromList(re), im0 = Float64List.fromList(im);
      fft.transform(re, im);
      fft.inverse(re, im);
      for (var i = 0; i < 4096; i++) {
        expect(re[i], closeTo(re0[i], 1e-3));
        expect(im[i], closeTo(im0[i], 1e-3));
      }
    });
  });

  test('非 2 的幂 size 抛 AssertionError', () {
    expect(() => FFT(4095), throwsA(isA<AssertionError>()));
  });
}

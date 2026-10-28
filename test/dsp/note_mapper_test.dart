import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:kithara/dsp/note_mapper.dart';

void main() {
  group('NoteMapper (A4=440)', () {
    final mapper = NoteMapper();

    test('六根标准弦音名正确', () {
      expect(mapper.noteName(mapper.nearestSemitoneIndex(82.41)), 'E2');
      expect(mapper.noteName(mapper.nearestSemitoneIndex(110.00)), 'A2');
      expect(mapper.noteName(mapper.nearestSemitoneIndex(146.83)), 'D3');
      expect(mapper.noteName(mapper.nearestSemitoneIndex(196.00)), 'G3');
      expect(mapper.noteName(mapper.nearestSemitoneIndex(246.94)), 'B3');
      expect(mapper.noteName(mapper.nearestSemitoneIndex(329.63)), 'E4');
    });

    test('精确频率 cents 偏差 ≈ 0', () {
      for (final f in [82.41, 110.00, 146.83, 196.00, 246.94, 329.63]) {
        expect(mapper.centsOffset(f), closeTo(0, 0.6), reason: 'freq=$f');
      }
    });

    test('+25 cent 输入返回 +25 cents', () {
      final up = 110.0 * math.pow(2, 25 / 1200);
      expect(mapper.centsOffset(up), closeTo(25.0, 0.1));
    });

    test('-25 cent 输入返回 -25 cents', () {
      final down = 110.0 * math.pow(2, -25 / 1200);
      expect(mapper.centsOffset(down), closeTo(-25.0, 0.1));
    });

    test('±50 cent 交界取偏高半音（上界）', () {
      // 恰 50.0¢ 浮点上落在 -23.49999…，不稳定；用 50.05¢ 验证跨界方向
      final above = 110.0 * math.pow(2, 50.05 / 1200);
      expect(mapper.noteName(mapper.nearestSemitoneIndex(above)), 'A#2');
      final below = 110.0 * math.pow(2, 49.95 / 1200);
      expect(mapper.noteName(mapper.nearestSemitoneIndex(below)), 'A2');
    });

    test('frequencyOf 往返一致', () {
      for (final semi in [-29, -24, -17, -12, -10, -5]) {
        final f = mapper.frequencyOf(semi);
        expect(mapper.nearestSemitoneIndex(f), semi);
      }
    });
  });

  group('NoteMapper (A4=430)', () {
    final mapper = NoteMapper(a4: 430.0);

    test('110Hz（A2@440）显示偏高 ≈ +39.8¢', () {
      // A2@430 = 107.5Hz；1200·log2(110/107.5) = 39.8
      expect(mapper.centsOffset(110.0), closeTo(39.8, 1.0));
    });

    test('A2@430 精确频率 cents=0', () {
      expect(mapper.centsOffset(mapper.frequencyOf(-24)), closeTo(0, 0.6));
    });
  });
}

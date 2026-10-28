import 'package:flutter_test/flutter_test.dart';
import 'package:kithara/tuner/tuning_modes.dart';

void main() {
  test('6 种调弦模式存在且字符串数正确', () {
    final ids = TuningModes.all.map((m) => m.id).toList();
    expect(ids, containsAll(['standard', 'drop_d', 'open_d', 'open_g', 'dadgad', 'chromatic']));
    expect(TuningModes.byId('standard').strings, hasLength(6));
    expect(TuningModes.byId('drop_d').strings, hasLength(6));
    expect(TuningModes.byId('open_d').strings, hasLength(6));
    expect(TuningModes.byId('open_g').strings, hasLength(6));
    expect(TuningModes.byId('dadgad').strings, hasLength(6));
  });

  test('standard 弦表 6→1: E2 A2 D3 G3 B3 E4', () {
    expect(TuningModes.byId('standard').strings.map((s) => s.name).toList(),
        ['E2', 'A2', 'D3', 'G3', 'B3', 'E4']);
  });

  test('drop_d 弦表 6→1: D2 A2 D3 G3 B3 E4', () {
    expect(TuningModes.byId('drop_d').strings.map((s) => s.name).toList(),
        ['D2', 'A2', 'D3', 'G3', 'B3', 'E4']);
  });

  test('open_d 弦表 6→1: D2 A2 D3 F#3 A3 D4', () {
    expect(TuningModes.byId('open_d').strings.map((s) => s.name).toList(),
        ['D2', 'A2', 'D3', 'F#3', 'A3', 'D4']);
  });

  test('chromatic 模式 strings 为空', () {
    expect(TuningModes.byId('chromatic').strings, isEmpty);
  });

  test('openD 测试向量: spec §7 频率→目标弦→cents', () {
    final openD = TuningModes.byId('open_d');
    final cases = [
      (73.42, 'D2'), (110.00, 'A2'), (146.83, 'D3'),
      (185.00, 'F#3'), (220.00, 'A3'), (293.66, 'D4'),
    ];
    for (final (freq, name) in cases) {
      final target = openD.strings.firstWhere((s) => s.name == name);
      expect(target.frequency, closeTo(freq, 0.01), reason: name);
    }
  });

  test('ukulele 标准调弦 GCEA (4弦, re-entrant 高音G)', () {
    final uke = TuningModes.byId('ukulele');
    expect(uke.strings, hasLength(4));
    expect(uke.strings.map((s) => s.name).toList(),
        ['G4', 'C4', 'E4', 'A4']);
    expect(uke.strings[0].frequency, closeTo(392.00, 0.01));
    expect(uke.strings[1].frequency, closeTo(261.63, 0.01));
    expect(uke.strings[2].frequency, closeTo(329.63, 0.01));
    expect(uke.strings[3].frequency, closeTo(440.00, 0.01));
  });

  test('ukulele Low G 线性调弦 G3 C4 E4 A4', () {
    final lg = TuningModes.byId('ukulele_low_g');
    expect(lg.strings.map((s) => s.name).toList(),
        ['G3', 'C4', 'E4', 'A4']);
    expect(lg.strings[0].frequency, closeTo(196.00, 0.01));
  });

  test('ukulele Baritone 调弦 D3 G3 B3 E4', () {
    final bari = TuningModes.byId('ukulele_baritone');
    expect(bari.strings.map((s) => s.name).toList(),
        ['D3', 'G3', 'B3', 'E4']);
  });

  test('ukulele 模式声明检测范围覆盖全部弦频', () {
    for (final id in ['ukulele', 'ukulele_low_g', 'ukulele_baritone']) {
      final m = TuningModes.byId(id);
      final freqs = m.strings.map((s) => s.frequency);
      expect(m.detectorMaxFreq, greaterThan(freqs.reduce((a, b) => a > b ? a : b)),
          reason: '$id maxFreq 应高于最高弦');
      expect(m.detectorMinFreq, lessThan(freqs.reduce((a, b) => a < b ? a : b)),
          reason: '$id minFreq 应低于最低弦');
    }
  });

  test('matchString: 距离 0.4 半音内吸附到最近弦', () {
    final dropD = TuningModes.byId('drop_d');
    // D2@标准+5¢
    final m = dropD.matchString(73.42 * 1.0029);
    expect(m, isNotNull);
    expect(m!.string.name, 'D2');
    // 与两根弦都距离 >0.5 半音 → null
    expect(dropD.matchString(90.0), isNull);
  });
}

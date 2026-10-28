import 'dart:math' as math;

import '../dsp/note_mapper.dart';

/// 一根目标弦：半音索引（相对 A4）+ 当前参考音高。
class StringTarget {
  const StringTarget(this.semitoneIndex, this.a4);

  final int semitoneIndex;
  final double a4;

  String get name => NoteMapper(a4: a4).noteName(semitoneIndex);
  double get frequency => a4 * math.pow(2.0, semitoneIndex / 12.0);
}

/// matchString 的结果：目标弦 + 相对该弦的 cents 偏差。
class StringMatch {
  const StringMatch(this.string, this.cents);

  final StringTarget string;
  final double cents;
}

/// 一种调弦模式。semitones 为 6→1 弦（低→高）的半音索引，chromatic 为空。
class TuningMode {
  const TuningMode(this.id, this.label, this.semitones, {this.a4 = 440.0});

  final String id;
  final String label;
  final List<int> semitones;
  final double a4;

  TuningMode withA4(double a4) => TuningMode(id, label, semitones, a4: a4);

  List<StringTarget> get strings =>
      [for (final n in semitones) StringTarget(n, a4)];

  /// 吸附最近弦；距离 >0.5 半音或 chromatic 模式返回 null。
  StringMatch? matchString(double freq) {
    if (semitones.isEmpty) return null;
    final semis = 12.0 * math.log(freq / a4) / math.ln2;
    var bestIdx = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < semitones.length; i++) {
      final d = (semis - semitones[i]).abs();
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }
    if (bestDist > 0.5) return null;
    final target = semitones[bestIdx];
    return StringMatch(StringTarget(target, a4), (semis - target) * 100.0);
  }
}

/// 内置调弦模式表（A4=440 基准的半音索引）。
class TuningModes {
  static const standard =
      TuningMode('standard', '标准', [-29, -24, -19, -14, -10, -5]); // E2 A2 D3 G3 B3 E4
  static const dropD =
      TuningMode('drop_d', 'Drop D', [-31, -24, -19, -14, -10, -5]);
  static const openD =
      TuningMode('open_d', 'Open D', [-31, -24, -19, -15, -12, -7]);
  static const openG =
      TuningMode('open_g', 'Open G', [-31, -26, -19, -14, -10, -7]);
  static const dadgad =
      TuningMode('dadgad', 'DADGAD', [-31, -24, -19, -14, -12, -7]);
  static const chromatic = TuningMode('chromatic', '半音阶', []);

  static const List<TuningMode> all = [
    standard, dropD, openD, openG, dadgad, chromatic,
  ];

  static TuningMode byId(String id, {double a4 = 440.0}) =>
      all.firstWhere((m) => m.id == id).withA4(a4);
}

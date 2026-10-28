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

/// 一种调弦模式。semitones 为弦（低→高）的半音索引，chromatic 为空。
/// [detectorMinFreq]/[detectorMaxFreq] 声明该模式的音高检测范围——
/// 管线在模式切换时据此重建 PitchDetector（吉他 65-350，尤克里里需更高）。
class TuningMode {
  const TuningMode(
    this.id,
    this.label,
    this.semitones, {
    this.a4 = 440.0,
    this.detectorMinFreq = 65.0,
    this.detectorMaxFreq = 350.0,
  });

  final String id;
  final String label;
  final List<int> semitones;
  final double a4;
  final double detectorMinFreq;
  final double detectorMaxFreq;

  TuningMode withA4(double a4) => TuningMode(id, label, semitones,
      a4: a4,
      detectorMinFreq: detectorMinFreq,
      detectorMaxFreq: detectorMaxFreq);

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

  // 尤克里里：re-entrant GCEA（高音G）/ Low G 线性 / Baritone DGBE
  // 半音索引（相对 A4）：G4=-2, C4=-9, E4=-5, A4=0, G3=-12, D3=-7, B3=-2
  static const ukulele = TuningMode(
    'ukulele', '尤克里里', [-2, -9, -5, 0],
    detectorMinFreq: 240, detectorMaxFreq: 500,
  );
  static const ukuleleLowG = TuningMode(
    'ukulele_low_g', '尤克里里 Low G', [-14, -9, -5, 0],
    detectorMinFreq: 180, detectorMaxFreq: 500,
  );
  static const ukuleleBaritone = TuningMode(
    'ukulele_baritone', '尤克里里 Bari', [-19, -14, -10, -5],
    detectorMinFreq: 140, detectorMaxFreq: 400,
  );

  // 常见扩展: Drop C / Eb(半音降) / D(全音降)
  static const dropC = TuningMode(
    'drop_c', 'Drop C', [-33, -26, -21, -16, -12, -7], // C2 G2 C3 F3 A3 D4
    detectorMinFreq: 60, detectorMaxFreq: 350,
  );
  static const eb = TuningMode(
    'eb', 'Eb 降半音', [-30, -25, -20, -15, -11, -6], // D#2 G#2 C#3 F#3 A#3 D#4
    detectorMinFreq: 65, detectorMaxFreq: 350,
  );
  static const dTuning = TuningMode(
    'd_tuning', 'D 降全音', [-31, -26, -21, -16, -12, -7], // D2 G2 C3 F3 A3 D4
    detectorMinFreq: 65, detectorMaxFreq: 350,
  );

  static const List<TuningMode> all = [
    standard, dropD, dropC, eb, dTuning,
    openD, openG, dadgad,
    ukulele, ukuleleLowG, ukuleleBaritone, chromatic,
  ];

  static TuningMode byId(String id, {double a4 = 440.0}) =>
      all.firstWhere((m) => m.id == id).withA4(a4);
}

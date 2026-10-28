import 'dart:math' as math;

/// 频率 ↔ 音名映射（十二平均律）。
/// n = 距 A4 半音数（负 = 低于 A4），f = a4 · 2^(n/12)
class NoteMapper {
  NoteMapper({this.a4 = 440.0}) : _logA4 = math.log(a4);

  final double a4;
  final double _logA4;

  static const List<String> _names = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
  ];

  int nearestSemitoneIndex(double freq) {
    final n = 12.0 * (math.log(freq) / math.ln2 - _logA4 / math.ln2);
    // floor(n+0.5)：平局(+50¢ 整)归偏高半音（上界）；round() 对负数平局会向下
    return (n + 0.5).floor();
  }

  String noteName(int semitoneIndex) {
    // 音名数组以 C 开头；A4 = 9 号音级，故下标要加 9 再取模
    final name = _names[(semitoneIndex + 9) % 12]; // Dart 的 % 恒非负
    // 注意用 floor 而非 ~/：~/ 向零截断，负半音索引（低于 A4 的弦）会错一档
    final octave = 4 + ((semitoneIndex + 9) / 12).floor();
    return '$name$octave';
  }

  double centsOffset(double freq) {
    final exact = 1200.0 * (math.log(freq) / math.ln2 - _logA4 / math.ln2);
    return exact - 100.0 * nearestSemitoneIndex(freq);
  }

  double frequencyOf(int semitoneIndex) =>
      a4 * math.pow(2.0, semitoneIndex / 12.0);
}

import 'package:flutter/foundation.dart';

import '../dsp/note_mapper.dart';
import 'tuning_modes.dart';

/// 调音器不可变状态快照（UI 监听用）。
class TunerState {
  const TunerState({
    required this.mode,
    required this.a4,
    required this.hasSignal,
    required this.noteLabel,
    required this.cents,
    required this.needle,
    required this.activeString,
    required this.inTune,
  });

  final TuningMode mode;
  final double a4;
  final bool hasSignal;

  /// 最近一次识别的音名；信号丢失时保留（UI 平滑，见 spec §4）。
  final String noteLabel;
  final double cents;

  /// -1..1，±50¢ 映射满偏。
  final double needle;
  final StringTarget? activeString;
  final bool inTune;
}

/// 调音器控制器：接收音高帧，维护状态，通知 UI。
class TunerController extends ChangeNotifier {
  TunerController()
      : _mode = TuningModes.standard,
        _a4 = 440.0,
        _mapper = NoteMapper();

  TuningMode _mode;
  double _a4;
  NoteMapper _mapper;

  bool _hasSignal = false;
  String _noteLabel = '—';
  double _cents = 0.0;
  double _needle = 0.0;
  StringTarget? _active;
  StringTarget? _pending;
  int _pendingCount = 0;

  TunerState get state => TunerState(
        mode: _mode,
        a4: _a4,
        hasSignal: _hasSignal,
        noteLabel: _noteLabel,
        cents: _cents,
        needle: _needle,
        activeString: _active,
        inTune: _active != null && _cents.abs() <= 5.0,
      );

  /// 管线送来一帧音高；freq=null 表示本帧无有效音高（静音/不可靠）。
  void onPitch(double? freq, double confidence) {
    if (freq == null) {
      _hasSignal = false; // noteLabel/cents/needle/active 保留，UI 平滑
      notifyListeners();
      return;
    }
    _hasSignal = true;
    final mapperCents = _mapper.centsOffset(freq);
    _noteLabel = _mapper.noteName(_mapper.nearestSemitoneIndex(freq));

    final match = _mode.matchString(freq);
    if (_mode.semitones.isNotEmpty) {
      if (match == null) {
        // 距所有弦都远：清除锁定
        _active = null;
        _pending = null;
        _pendingCount = 0;
      } else {
        _applyStringLock(match);
      }
    } else {
      _active = null;
    }

    _cents = match?.cents ?? mapperCents;
    _needle = (_cents / 50.0).clamp(-1.0, 1.0);
    notifyListeners();
  }

  /// 锁弦：同一根新弦连续 2 帧才切换，防止边界抖动（spec §5）。
  void _applyStringLock(StringMatch match) {
    final target = match.string;
    if (_active == null) {
      _active = target;
      _pending = null;
      _pendingCount = 0;
      return;
    }
    if (target.semitoneIndex == _active!.semitoneIndex) {
      _pending = null;
      _pendingCount = 0;
      return;
    }
    if (_pending?.semitoneIndex == target.semitoneIndex) {
      _pendingCount++;
    } else {
      _pending = target;
      _pendingCount = 1;
    }
    if (_pendingCount >= 2) {
      _active = target;
      _pending = null;
      _pendingCount = 0;
    }
  }

  void setMode(TuningMode mode) {
    _mode = mode.withA4(_a4);
    _active = null;
    _pending = null;
    _pendingCount = 0;
    notifyListeners();
  }

  void setA4(double a4) {
    _a4 = a4;
    _mapper = NoteMapper(a4: a4);
    _mode = _mode.withA4(a4);
    notifyListeners();
  }
}

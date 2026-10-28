import 'dart:math' as math;

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
  int? _noteSemi; // 当前显示音名的半音索引
  int? _noteCandidateSemi; // 挂起中的新音名（需第 2 帧确认）
  bool _manualLock = false; // 手动选弦粘性锁（自动匹配不覆盖）

  /// 锁定保持：调准后信号丢失仍保持锁定视觉 2s（拨弦衰减是常态，
  /// 绿色不该随音量消失而闪灭）。实现为时间戳比较——无 Timer、无泄漏，
  /// 每次读 state 即时判定。
  DateTime? _lockHoldUntil;
  static const _lockHoldDuration = Duration(seconds: 2);

  /// 可注入时钟（测试用）
  DateTime Function() _now = DateTime.now;

  /// 信号滞回：触发检出需 0.85（防噪声误报），维持检出只需 0.75
  /// （防门限边缘抖动导致音名闪烁）。上帧有信号时用低门限判断。
  static const _confOn = 0.85;
  static const _confHold = 0.75;

  @visibleForTesting
  set nowForTest(DateTime Function() f) => _now = f;

  TunerState get state {
    final lockHeld = _lockHoldUntil != null &&
        _now().isBefore(_lockHoldUntil!);
    final liveTune = _active != null && _cents.abs() <= 5.0 && _hasSignal;
    final inTune = liveTune || (lockHeld && _active != null);
    return TunerState(
      mode: _mode,
      a4: _a4,
      hasSignal: _hasSignal,
      noteLabel: _noteLabel,
      cents: _cents,
      needle: _hasSignal ? _needle : _needle,
      activeString: _active,
      inTune: inTune,
    );
  }

  /// 管线送来一帧音高；freq=null 表示本帧无有效音高（静音/不可靠）。
  void onPitch(double? freq, double confidence) {
    if (freq == null) {
      _hasSignal = false; // noteLabel/cents/needle/active 保留，UI 平滑
      // 锁定保持窗口：已调准状态下信号消失，保持绿色 2s
      final wasTuned = _active != null && _cents.abs() <= 5.0;
      if (wasTuned) {
        _lockHoldUntil = _now().add(_lockHoldDuration);
      }
      notifyListeners();
      return;
    }
    final hadSignal = _hasSignal;
    _hasSignal = confidence >= (hadSignal ? _confHold : _confOn);
    if (!_hasSignal) {
      // 未达门限：走无信号路径（保持窗口仍生效）
      final wasTuned = _active != null && _cents.abs() <= 5.0;
      if (wasTuned) {
        _lockHoldUntil = _now().add(_lockHoldDuration);
      }
      notifyListeners();
      return;
    }
    // 新信号到来 → 结束保持窗口，回到实时判定
    _lockHoldUntil = null;
    final mapperCents = _mapper.centsOffset(freq);
    _noteLabel = _mapper.noteName(_mapper.nearestSemitoneIndex(freq));

    // 音名滞回：与当前音名偏离超过半音的突变，需连续 2 帧一致才换名
    // （单帧八度噪声不再让 E4↔E3 反复跳；正常滑音每帧都不同则立即跟随）
    final newSemi = _mapper.nearestSemitoneIndex(freq);
    final changed = _noteSemi != null && newSemi != _noteSemi;
    if (changed) {
      if (_noteCandidateSemi == newSemi) {
        _noteSemi = newSemi; // 连续第 2 帧 → 确认
        _noteCandidateSemi = null;
      } else {
        _noteCandidateSemi = newSemi; // 第 1 帧 → 挂起，保持旧显示
      }
    } else {
      _noteSemi = newSemi; // 与当前一致（或首次）
      _noteCandidateSemi = null;
    }
    _noteLabel = _mapper.noteName(_noteSemi ?? newSemi);

    if (_manualLock && _active != null) {
      // 粘性锁：跳过自动匹配，偏差 = 检测音高 相对 锁定弦
      final lockedSemi = _active!.semitoneIndex;
      _cents = _semitonesFrom(freq, lockedSemi);
      _needle = (_cents / 50.0).clamp(-1.0, 1.0);
      // 显示音名 = 目标弦音名（初学者视角: 正在调这根弦，不随检测跳）
      _noteLabel = _mapper.noteName(lockedSemi);
      _noteSemi = lockedSemi;
      _noteCandidateSemi = null;
      notifyListeners();
      return;
    }

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

  /// 检测频率相对目标半音的音分差（可为任意大小，供粘性锁显示大偏差）
  double _semitonesFrom(double freq, int targetSemi) {
    final f0 = _a4 * math.pow(2.0, targetSemi / 12.0);
    return 1200.0 * (freq > 0 && f0 > 0 ? math.log(freq / f0) / math.ln2 : 0.0);
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

  /// 手动指定目标弦（点 LED）；再次点击同一弦取消选择。
  /// 粘性锁：锁定期间自动匹配不覆盖/清除，偏差始终相对此弦
  /// （很松的弦离目标几百音分也能显示满偏，不会跳回"任意判断"）。
  void selectString(int semitoneIndex) {
    if (_active?.semitoneIndex == semitoneIndex) {
      _active = null;
      _manualLock = false;
    } else {
      _active = StringTarget(semitoneIndex, _a4);
      _pending = null;
      _pendingCount = 0;
      _manualLock = true;
      // 立即以当前显示音高重算相对偏差（若有信号）
    }
    notifyListeners();
  }

  void setMode(TuningMode mode) {
    _mode = mode.withA4(_a4);
    _active = null;
    _pending = null;
    _pendingCount = 0;
    _lockHoldUntil = null;
    // 模式切换 = 新音域，音名滞回历史作废
    _noteSemi = null;
    _noteCandidateSemi = null;
    _manualLock = false;
    notifyListeners();
  }

  void setA4(double a4) {
    _a4 = a4;
    _mapper = NoteMapper(a4: a4);
    _mode = _mode.withA4(a4);
    notifyListeners();
  }
}

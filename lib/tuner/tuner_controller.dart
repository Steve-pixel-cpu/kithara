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
    required this.range,
    required this.tunedSemis,
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

  /// 当前量程（±音分）: 50 精调 / 250 / 500 粗调（大偏差自动扩档）
  final int range;

  /// 本次会话已调准的弦（半音索引集合）——调准过的弦保持淡绿标记，
  /// 切模式清空
  final Set<int> tunedSemis;
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
  bool _hasSignalWoken = false; // 稳定门限: 是否已通过稳定唤醒

  /// 稳定门限复位（信号丢失/低置信帧）
  void _resetWake() {
    _wakeCount = 0;
    _wakeAnchor = null;
    _hasSignalWoken = false;
  }

  // 3 帧中值滤波: 松弦时检测帧间乱跳（真实物理现象——低张力弦谐波失谐）,
  // 中位数天然免疫单帧毛刺, 比均值平滑不拖慢正常跟弦
  final List<double> _freqWindow = [];

  // 稳定门限（拒非乐器声）: 唤醒需连续 N 帧音高落在同一 40¢ 带内。
  // 人声/环境声音高持续滑动或音节 <300ms → 唤不醒；拨弦持续数秒 → 正常锁定。
  // 仅自动模式设卡；手动锁弦用户意图明确，保持即时反馈（毛刺由中值滤波兜底）。
  // 默认 3 帧；嘈杂模式降至 2 帧（OnsetGate 窗口只有 ~8 帧@20Hz，
  // 拨弦瞬间窗口短暂，3 帧太苛刻——真机"没反应"的拼图之一）。
  static const _wakeFramesDefault = 3;
  static const _wakeBand = 40.0;
  int _wakeFrames = _wakeFramesDefault;
  int _wakeCount = 0;
  double? _wakeAnchor;

  /// 嘈杂模式开关：唤醒帧数 3→2。由管线在设置变更时注入。
  set wakeFrames(int v) => _wakeFrames = v;

  // 量程自适应: 滞回扩档（扩档阈值 95%/缩档 75% 防边界抖动）
  int _range = 50;

  // 会话调准记忆
  final Set<int> _tunedSemis = {};

  /// 锁定保持：调准后信号丢失仍保持锁定视觉 2s（拨弦衰减是常态，
  /// 绿色不该随音量消失而闪灭）。实现为时间戳比较——无 Timer、无泄漏，
  /// 每次读 state 即时判定。
  DateTime? _lockHoldUntil;
  static const _lockHoldDuration = Duration(seconds: 2);

  /// 可注入时钟（测试用）
  DateTime Function() _now = DateTime.now;

  /// 信号滞回：触发检出需 0.85（防噪声误报），维持检出只需 0.75
  /// （防门限边缘抖动导致音名闪烁）。上帧有信号时用低门限判断。
  static const _confOnDefault = 0.85;
  static const _confHold = 0.75;
  double _confOn = _confOnDefault;

  /// 不对称弦锁：捕获/换弦需更高置信（默认 0.85），同弦续锁沿用
  /// _confHold（0.75）。已锁定的音允许在噪声抖动中维持——低置信
  /// 只能"续"不能"抢"。由降噪档位动态设定（main.dart 桥注入，
  /// low/medium/high = 0.80/0.85/0.90），未注入时与 _confOn 一致。
  double _captureConfidence = 0.85;

  set captureConfidence(double v) => _captureConfidence = v;

  /// 信号触发门限（平时 0.85）。嘈杂模式下管线降到 0.75：检测器已放宽到
  /// 0.70, 若控制器仍卡 0.85, 放出来的 0.70-0.85 帧转头就被拒——这正是
  /// "开不开启差别不大"的接线缺口。时间门(onset)已挡噪声帧, 这里可放宽。
  set confOn(double v) => _confOn = v;

  /// 实时诊断（嘈杂模式排障用, 由管线每帧写入, UI 直接展示）
  String diagnostics = '';

  @visibleForTesting
  set nowForTest(DateTime Function() f) => _now = f;

  bool _holdingLock() =>
      _lockHoldUntil != null && _now().isBefore(_lockHoldUntil!);

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
      // 常驻指针: 无信号且不在保持窗口 → 实时判 -1（-500 满偏待命）
      needle: _hasSignal || _holdingLock()
          ? _needle
          : -1.0,
      activeString: _active,
      inTune: inTune,
      range: _range,
      tunedSemis: _tunedSemis,
    );
  }

  /// 管线送来一帧音高；freq=null 表示本帧无有效音高（静音/不可靠）。
  void onPitch(double? freq, double confidence) {
    if (freq == null) {
      _hasSignal = false; // noteLabel/cents/active 保留，UI 平滑
      _resetWake();
      // 锁定保持窗口：已调准状态下信号消失，保持绿色 2s（needle 保持居中）
      final wasTuned = _active != null && _cents.abs() <= 5.0;
      final holding = wasTuned ||
          (_lockHoldUntil != null && _now().isBefore(_lockHoldUntil!));
      if (wasTuned && _lockHoldUntil == null) {
        _lockHoldUntil = _now().add(_lockHoldDuration);
      }
      // 常驻指针: 无信号且不在保持窗口 → 回 -500 满偏待命
      if (!holding) {
        _needle = -1.0;
      }
      notifyListeners();
      return;
    }
    final hadSignal = _hasSignal;
    // 稳定门限: 已唤醒/手动锁弦/已有信号 → 维持门限 0.75; 否则触发门限 0.85
    final holdMode = _hasSignalWoken || _manualLock || hadSignal;
    _hasSignal = false; // 先置否, 通过稳定门限后再置真
    // 中值滤波: 维护最近 3 帧频率, 取中位（仅用于 cents/needle 显示平滑；
    // 音名滞回与弦锁定用原始帧——随机毛刺不会连续 2 帧同值, 滞回本就免疫）
    _freqWindow.add(freq);
    if (_freqWindow.length > 3) _freqWindow.removeAt(0);
    final sorted = [..._freqWindow]..sort();
    final smoothed = sorted[sorted.length ~/ 2];
    if (confidence < (holdMode ? _confHold : _confOn)) {
      // 未达置信门限：走无信号路径（保持窗口仍生效）
      _resetWake();
      final wasTuned = _active != null && _cents.abs() <= 5.0;
      if (wasTuned) {
        _lockHoldUntil = _now().add(_lockHoldDuration);
      }
      notifyListeners();
      return;
    }
    // 稳定门限: 已唤醒（或手动锁弦）→ 直接过卡正常跟随；
    // 未唤醒 → 需连续 3 帧落在同一 40¢ 带内才允许唤醒（拒说话/环境声）。
    if (!_hasSignalWoken && !_manualLock) {
      final anchor = _wakeAnchor;
      final inBand = anchor != null &&
          (1200.0 * math.log(freq / anchor) / math.ln2).abs() <= _wakeBand;
      _wakeCount = inBand ? _wakeCount + 1 : 1;
      _wakeAnchor = freq;
      if (_wakeCount < _wakeFrames) {
        // 未达唤醒帧数: 不更新任何显示状态（对 UI 等同无信号）
        notifyListeners();
        return;
      }
      _hasSignalWoken = true;
    } else {
      _wakeAnchor = freq;
    }
    _hasSignal = true;
    // 新信号到来 → 结束保持窗口，回到实时判定
    _lockHoldUntil = null;
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
      // 粘性锁：跳过自动匹配，偏差 = 滤波后音高 相对 锁定弦
      final lockedSemi = _active!.semitoneIndex;
      // 八度归一：松弦时基频极弱，检测器会在真实基频与 2× 泛音间交替；
      // 把检测频率折到最接近目标弦的八度（×2/÷2），偏差方向恒定，指针不再遍历全量程
      var f = smoothed;
      final target = _a4 * math.pow(2.0, lockedSemi / 12.0);
      while (f < target / 1.5) { f *= 2; } // 检测远低于目标 → 升八度（报的是低八度基频）
      while (f > target * 1.5) { f /= 2; } // 检测远高于目标 → 降八度（报的是泛音）
      _cents = _semitonesFrom(f, lockedSemi);
      _updateRange();
      _needle = (_cents / _range).clamp(-1.0, 1.0);
      _recordTuned();
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
      } else if (confidence < _captureConfidence &&
          (_active == null ||
              match.string.semitoneIndex != _active!.semitoneIndex)) {
        // 不对称弦锁：首次捕获/换弦需高置信；低置信帧只允许维持
        // 当前锁（同弦续锁走 _applyStringLock）——嘈杂环境里带内噪声
        // 偶发的假信号被拦在门外，已锁定的读数不受影响（松弦换弦时
        // 频率大幅远离 → match==null 路径快速释放，不经过此门）。
        _pending = null;
        _pendingCount = 0;
      } else {
        _applyStringLock(match);
      }
    } else {
      _active = null;
    }

    // cents 显示用滤波值（毛刺免疫）; 弦匹配/音名已由原始帧判定
    final matchSmoothed = _mode.matchString(smoothed);
    _cents = matchSmoothed?.cents ?? _mapper.centsOffset(smoothed);
    _updateRange();
    _needle = (_cents / _range).clamp(-1.0, 1.0);
    _recordTuned();
    notifyListeners();
  }

  /// 会话记忆: liveTune（真实信号在 ±5¢ 内）时把目标弦记入 tuned 集
  void _recordTuned() {
    final liveTune =
        _active != null && _cents.abs() <= 5.0 && _hasSignal;
    if (liveTune) {
      _tunedSemis.add(_active!.semitoneIndex);
    }
  }

  /// 滞回扩档: |cents| 超当前量程 95% -> 扩档(50->250->500);
  /// 低于更小档 75% -> 缩档。刻度标注跟随 range。
  void _updateRange() {
    final a = _cents.abs();
    if (_range == 50 && a > 47.5) {
      _range = 250;
    } else if (_range == 250 && a > 237.5) {
      _range = 500;
    } else if (_range == 500 && a < 187.5) {
      _range = 250;
    } else if (_range == 250 && a < 48) {
      _range = 50; // 回到 ±50 内即缩档（精调视角优先, 留边界余量）
    }
  }

  /// 检测频率相对目标半音的音分差（可为任意大小，供粘性锁显示大偏差）
  double _semitonesFrom(double freq, int targetSemi) {
    final f0 = _a4 * math.pow(2.0, targetSemi / 12.0);
    return 1200.0 * (freq > 0 && f0 > 0 ? math.log(freq / f0) / math.ln2 : 0.0);
  }

  /// 锁弦：同一根新弦连续 2 帧才切换，防止边界抖动（spec §5）。
  /// 首次捕获（_active == null）由 onPitch 的不对称门限把关
  /// （confidence ≥ _captureConfidence 才走到这里）。
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
      _resetWake(); // 解锁回自动模式 → 重新走稳定门限
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
    _resetWake();
    _tunedSemis.clear();
    notifyListeners();
  }

  void setA4(double a4) {
    _a4 = a4;
    _mapper = NoteMapper(a4: a4);
    _mode = _mode.withA4(a4);
    notifyListeners();
  }
}

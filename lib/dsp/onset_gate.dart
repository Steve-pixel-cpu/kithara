/// 拨弦起振门（嘈杂环境调音模式的时间维度降噪）。
///
/// 原理：稳态噪声（风扇/空调）与琴声在频率上不可分（带内噪声），
/// 但在时间上完全可分——噪声恒定，琴是瞬态突发。对滤波后 RMS 维护
/// 慢速均线（EMA ≈ 底噪水位），当前帧跳升超过均线 1.5 倍（+3.5dB）
/// 且超过绝对下限 → 判定拨弦，开放 [acceptWindow] 采信窗口；窗口外
/// 的帧一律拒绝（管线层喂 null 给控制器）。
///
/// EMA 更新时机（关键，仿真踩过的坑）：只在窗口【关闭】时更新。
/// 若拨弦帧也更新 EMA，均线被拨弦抬高，下一次拨弦的跳升比不足
/// 2x 永远触发不了（实测触发率从 ~100% 掉到 2%）。
///
/// 无跨帧音频状态（只存标量 EMA 和时间戳），帧间独立可用；
/// reset() 供管线重建时调用。
class OnsetGate {
  OnsetGate({
    this.jumpRatio = 1.5,
    this.minRms = 0.006,
    this.acceptWindow = const Duration(milliseconds: 400),
    this.emaAlpha = 0.02,
  });

  /// 跳升比：rms > ema × jumpRatio 判起振（1.5 ≈ +3.5dB）
  final double jumpRatio;

  /// 绝对下限：再大的相对跳升，绝对 RMS 太小（远场微弱声）不算
  final double minRms;

  /// 起振后采信窗口时长（拨弦起振 ~400ms 内琴能量最高）
  final Duration acceptWindow;

  /// EMA 平滑系数（每帧 0.02 ≈ 50 帧 ≈ 5s 时间常数 @20Hz 帧率）
  final double emaAlpha;

  double? _ema;
  DateTime? _openUntil;

  /// 诊断：当前 EMA（底噪水位估计）/ 窗口状态
  double? get emaValue => _ema;

  /// 是否开放采信窗口（含刚触发起振的这一帧）
  bool get isOpen => _openUntil != null;

  /// 喂入一帧的滤波后 RMS，返回本帧是否放行。
  /// [now] 由管线注入（DateTime.now()），便于测试注入时钟。
  bool accept(double rms, DateTime now) {
    if (_ema == null) {
      _ema = rms; // 首帧直接 seeded，不判跳升
      return false;
    }
    final openUntil = _openUntil;
    final inWindow = openUntil != null && now.isBefore(openUntil);
    if (!inWindow && rms > _ema! * jumpRatio && rms > minRms) {
      // 起振：开窗。EMA 不更新（见类注释）。
      _openUntil = now.add(acceptWindow);
      return true;
    }
    if (inWindow) {
      return true; // 窗口内放行，EMA 仍冻结
    }
    // 窗口关闭：慢速更新 EMA（贴着底噪水位走）
    _ema = _ema! + emaAlpha * (rms - _ema!);
    return false;
  }

  /// 管线重建/模式切换时调用：EMA 重新 seeded，窗口关闭。
  void reset() {
    _ema = null;
    _openUntil = null;
  }
}

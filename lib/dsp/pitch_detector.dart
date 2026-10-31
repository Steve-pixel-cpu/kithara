import 'dart:math' as math;
import 'dart:typed_data';

import 'fft.dart';

/// MPM (McLeod Pitch Method) 音高检测：FFT 加速自相关 + NSDF。
/// 预分配全部工作 buffer；detect 热路径零堆分配。
/// 内部用 Float64 计算（Float32 自相关在大 lag 处误差 ±4% 会破坏 NSDF 归一化），
/// 对外接口仍为 Float32List。
class PitchDetector {
  PitchDetector({
    this.sampleRate = 44100.0,
    this.window = 4096,
    this.minFreq = 65.0,
    this.maxFreq = 350.0,
    this.rmsGate = 0.0,
    this.confidenceGate = 0.85,
    this.bandRatioGate = 0.10,
  })  : _fftSize = window * 2, // 零填充一倍：循环自相关在 lag<window 内 == 线性自相关
        _fft = FFT(window * 2),
        _re = Float64List(window * 2),
        _im = Float64List(window * 2),
        _sqCum = Float64List(window + 1),
        _lpAlpha = 1.0 - math.exp(-2.0 * math.pi * _lpCutoffHz / sampleRate) {
    maxLag = (sampleRate / minFreq).ceil();
    _nsdf = Float64List(maxLag + 1);
  }

  final double sampleRate;
  final int window;
  final double minFreq;
  final double maxFreq;

  /// 输入级 RMS 门限（0=关闭）。低于门限的帧直接判无信号，
  /// 连 NSDF 都不计算——挡环境底噪/远场噪声，还省电。
  /// 计量在【前置滤波后】的信号上进行（见 detect 第 0 步）。
  final double rmsGate;

  /// NSDF 置信门限（默认 0.85）。嘈杂模式降到 0.70：拨弦瞬间帧
  /// 实测置信中位 1.26+（0dB 风扇），0.85 拦不住它们；真机"静默"
  /// 的根因在控制器凑不齐 3 帧一致，不在检测器。放宽门限放行
  /// 拨弦帧，噪声帧由 OnsetGate 时间门拦截（仿真：0dB 风扇下
  /// 每次拨弦命中率 49/20、精度 28¢）。
  final double confidenceGate;

  /// 频段能量占比门限（默认 0.10）。嘈杂模式降到 0.06：风扇能量
  /// 落在吉他频段内，摊薄琴的占比。
  final double bandRatioGate;

  /// 前置低通截止频率。手机麦/AGC 常带高频嘶声与量化噪声，它们不掩蔽
  /// 吉他基频却会污染自相关包络、并虚增原始 RMS（旧实现门控因此"三档
  /// 无感"）。两级 one-pole 级联（-12dB/oct）在 1800Hz 衰减带外成分，
  /// E4 的 4 次谐波（1319Hz）仍在带内不受影响。fc 下限受 1.2·maxFreq
  /// 频段预检上边界的约束（需 maxFreq·1.2·2.2 < fc·2 才不误伤带内能量）。
  static const _lpCutoffHz = 1800.0;
  final double _lpAlpha;


  late final int maxLag;

  final FFT _fft;
  final int _fftSize;
  final Float64List _re;
  final Float64List _im;
  final Float64List _sqCum;
  late final Float64List _nsdf;

  double _confidence = 0.0;
  double get lastConfidence => _confidence;

  /// 返回检出频率；null = 置信度 <0.85 或 f0 超出 [minFreq, maxFreq]。
  double? detect(Float32List frame) {
    assert(frame.length == window);
    final n = window;

    // 0. 前置滤波（弦外验证过的廉价清理链）+ 滤波后 RMS 门控。
    //    a）去直流（均值减除）；b）两级 one-pole 低通 @1800Hz。
    //    帧内独立滤波、无跨帧状态——与环形缓冲"读后耗尽"语义及
    //    换档重建检测器均兼容。RMS 在滤波后信号上计量：嘶声/直流
    //    不再虚增门控读数，三档才有真实区分度（旧行为在原始帧上
    //    计量，嘈杂环境里"琴+噪"总响度轻松过门，档位形同虚设）。
    //    a,b 两级滤波的暂态（首 ~5ms）由 4096 样本窗的长度稀释。
    var mean = 0.0;
    for (var i = 0; i < n; i++) {
      mean += frame[i];
    }
    mean /= n;
    var lp1 = 0.0;
    var lp2 = 0.0;
    var sumSq = 0.0;
    for (var i = 0; i < n; i++) {
      final dc = frame[i] - mean;
      lp1 += _lpAlpha * (dc - lp1);
      lp2 += _lpAlpha * (lp1 - lp2);
      _re[i] = lp2;
      sumSq += lp2 * lp2;
    }
    if (rmsGate > 0) {
      final rms = math.sqrt(sumSq / n);
      if (rms < rmsGate) {
        _confidence = 0.0;
        return null;
      }
    }
    _re.fillRange(n, _fftSize, 0.0); // 零填充后半段
    _im.fillRange(0, _fftSize, 0.0);

    // 3. 平方前缀和必须先用去直流后的信号算——IFFT 会覆写 _re
    _sqCum[0] = 0.0;
    for (var i = 0; i < n; i++) {
      _sqCum[i + 1] = _sqCum[i] + _re[i] * _re[i];
    }

    // 2. 范围预检（修正版）：若检测频段内的谱能量占比过低，
    //    则基频在范围外（如 440Hz 输入吉他模式会被误报为其子谐波 220）。
    //    不能只看全局主峰位置——高把位弦（E4 329Hz）的 2/3 次谐波
    //    （659/989Hz）可能强于基频，全局峰在范围外但基频在范围内。
    _fft.transform(_re, _im);
    var inBand = 0.0;
    var total = 0.0;
    final kMin = (minFreq * 0.8 * _fftSize / sampleRate).floor();
    final kMax = (maxFreq * 1.2 * _fftSize / sampleRate).ceil();
    for (var k = 1; k < _fftSize ~/ 2; k++) {
      final mag = _re[k] * _re[k] + _im[k] * _im[k];
      total += mag;
      if (k >= kMin && k <= kMax) inBand += mag;
    }
    // 频段能量占比过低 → 基频在范围外，拒绝
    if (total > 0 && inBand / total < bandRatioGate) {
      _confidence = 0.0;
      return null;
    }

    // 3. Wiener–Khinchin: FFT → 功率谱 → IFFT = 线性自相关（零填充后）
    for (var i = 0; i < _fftSize; i++) {
      _re[i] = _re[i] * _re[i] + _im[i] * _im[i];
    }
    _im.fillRange(0, _fftSize, 0.0);
    _fft.inverse(_re, _im);

    // 4. NSDF: nsdf[lag] = 2·r[lag] / m[lag]
    for (var lag = 0; lag <= maxLag; lag++) {
      final m = (_sqCum[n] - _sqCum[lag]) + (_sqCum[n - lag] - _sqCum[0]);
      _nsdf[lag] = m > 0 ? 2.0 * _re[lag] / m : 0.0;
    }

    // 5. McLeod 峰挑选（标准 McLeod 两步法）：
    //    (a) 全局最大 NSDF 峰值 → 门限 = k·max（k=0.9）
    //    (b) 从短周期向长周期扫（minLag→maxLag），取第一个 ≥ 门限的局部正峰
    //    规格原写的"从长周期向短周期扫取第一个≥0.9"会先撞上真周期的整数倍处
    //    （完美周期信号在 lag=6×T 处 NSDF 同样 ≈1），报出低 6 倍频的错误音高
    //    （实测 500Hz→83.3Hz、73.42Hz→74.26Hz）。以 spec"取基频方向"意图为准。
    final kThreshold = 0.9;
    final minLag = (sampleRate / maxFreq).floor();
    // (a) 全局最大值
    var nsdfMax = 0.0;
    for (var l = minLag; l <= maxLag; l++) {
      if (_nsdf[l] > nsdfMax) nsdfMax = _nsdf[l];
    }
    final thresh = kThreshold * nsdfMax;
    // (b) 从短周期向长周期，第一个超过门限的局部正峰
    var bestLag = -1;
    for (var l = minLag + 1; l < maxLag; l++) {
      if (_nsdf[l] > 0 && _nsdf[l] >= _nsdf[l - 1] && _nsdf[l] >= _nsdf[l + 1]) {
        if (_nsdf[l] >= thresh) {
          bestLag = l;
          break;
        }
      }
    }
    if (bestLag < 0) {
      _confidence = 0.0;
      return null;
    }

    // 6. 子谐波复查（方向语义：2×lag 频率减半 = 报回基频）：
    //    基频弱/倍频强的信号（拨弦位置效应）在 2×lag 处有真峰，移过去救回基频；
    //    门槛从 0.001 收紧到 +0.05——高把位弦帧间波动约 ±0.02，
    //    只有显著更高才翻，避免 E4↔E3 反复跳（根因：原 0.001 太敏感）
    final twice = bestLag * 2;
    if (twice <= maxLag &&
        _nsdf[twice] >= 0.85 &&
        _nsdf[twice] > _nsdf[bestLag] + 0.05) {
      bestLag = twice;
    }

    _confidence = _nsdf[bestLag];
    if (_confidence < confidenceGate) return null;

    // 7. 抛物线插值 lag → 亚采样精度
    final y0 = _nsdf[bestLag - 1], y1 = _nsdf[bestLag], y2 = _nsdf[bestLag + 1];
    final denom = 2.0 * (y0 - 2.0 * y1 + y2);
    final delta = denom != 0 ? (y0 - y2) / denom : 0.0;
    final f0 = sampleRate / (bestLag + delta);

    // 8. 范围门限
    if (f0 < minFreq || f0 > maxFreq) return null;
    return f0;
  }
}

extension PitchDetectorDebug on PitchDetector {
  /// 测试/调试专用：NSDF 表只读视图
  List<double> debugNsdf() => List.unmodifiable(_nsdf);
}

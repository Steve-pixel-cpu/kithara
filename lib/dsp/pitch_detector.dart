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
  })  : _fftSize = window * 2, // 零填充一倍：循环自相关在 lag<window 内 == 线性自相关
        _fft = FFT(window * 2),
        _re = Float64List(window * 2),
        _im = Float64List(window * 2),
        _sqCum = Float64List(window + 1) {
    maxLag = (sampleRate / minFreq).ceil();
    _nsdf = Float64List(maxLag + 1);
  }

  final double sampleRate;
  final int window;
  final double minFreq;
  final double maxFreq;
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

    // 1. 去直流
    var mean = 0.0;
    for (var i = 0; i < n; i++) {
      mean += frame[i];
    }
    mean /= n;
    for (var i = 0; i < n; i++) {
      _re[i] = frame[i] - mean;
    }
    _re.fillRange(n, _fftSize, 0.0); // 零填充后半段
    _im.fillRange(0, _fftSize, 0.0);

    // 3. 平方前缀和必须先用去直流后的信号算——IFFT 会覆写 _re
    _sqCum[0] = 0.0;
    for (var i = 0; i < n; i++) {
      _sqCum[i + 1] = _sqCum[i] + _re[i] * _re[i];
    }

    // 2. 范围预检：功率谱全局峰若落在检测范围外，基频必然在范围外
    //    （例：500Hz 输入、maxFreq=350 时，其 lag 子谐波伪峰会被误报为 250Hz）
    _fft.transform(_re, _im);
    var specBest = 0;
    var specMax = -1.0;
    for (var k = 1; k < _fftSize ~/ 2; k++) {
      final mag = _re[k] * _re[k] + _im[k] * _im[k];
      if (mag > specMax) {
        specMax = mag;
        specBest = k;
      }
    }
    final specFreq = specBest * sampleRate / _fftSize;
    if (specFreq > maxFreq * 1.35 || specFreq < minFreq * 0.55) {
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

    // 6. 子谐波复查：仅当 2×lag 处 NSDF ≥ 0.85 且严格更高才移动（一次，不级联）
    final twice = bestLag * 2;
    if (twice <= maxLag &&
        _nsdf[twice] >= 0.85 &&
        _nsdf[twice] > _nsdf[bestLag] + 0.001) {
      bestLag = twice;
    }

    _confidence = _nsdf[bestLag];
    if (_confidence < 0.85) return null;

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

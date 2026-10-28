import 'dart:math' as math;
import 'dart:typed_data';

/// 迭代式 radix-2 Cooley-Tukey FFT。
/// 构造期预计算位反转表与旋转因子；transform/inverse 原地、热路径零堆分配。
/// 使用 Float64：MPM 自相关在 Float32 下大 lag 处误差可达 ±4%（NSDF>1），
/// 会让峰挑选误判八度/周期；Float64 误差 <1e-10，性能开销可忽略。
class FFT {
  FFT(int size)
      : assert(size >= 2 && (size & (size - 1)) == 0, 'size 必须是 2 的幂'),
        n = size {
    // 位反转表
    _rev = Uint32List(n);
    final bits = _log2(n);
    for (var i = 0; i < n; i++) {
      var r = 0, x = i;
      for (var b = 0; b < bits; b++) {
        r = (r << 1) | (x & 1);
        x >>= 1;
      }
      _rev[i] = r;
    }
    // 旋转因子表: w[j] = e^(-2πi·j/n), j ∈ [0, n/2)
    final half = n >> 1;
    _cos = Float64List(half);
    _sin = Float64List(half);
    for (var j = 0; j < half; j++) {
      final ang = -2.0 * math.pi * j / n;
      _cos[j] = math.cos(ang);
      _sin[j] = math.sin(ang);
    }
  }

  final int n;
  late final Uint32List _rev;
  late final Float64List _cos;
  late final Float64List _sin;

  static int _log2(int x) {
    var l = 0;
    while (x > 1) {
      x >>= 1;
      l++;
    }
    return l;
  }

  int get size => n;

  /// 原地正变换
  void transform(Float64List re, Float64List im) {
    // 位反转置换
    for (var i = 0; i < n; i++) {
      final j = _rev[i];
      if (j > i) {
        var t = re[i]; re[i] = re[j]; re[j] = t;
        t = im[i]; im[i] = im[j]; im[j] = t;
      }
    }
    // 蝶形
    for (var len = 2; len <= n; len <<= 1) {
      final halfLen = len >> 1;
      final step = n ~/ len;
      for (var i = 0; i < n; i += len) {
        for (var j = 0; j < halfLen; j++) {
          final c = _cos[j * step], s = _sin[j * step];
          final p = i + j, q = p + halfLen;
          final tr = re[q] * c - im[q] * s;
          final ti = re[q] * s + im[q] * c;
          re[q] = re[p] - tr;
          im[q] = im[p] - ti;
          re[p] += tr;
          im[p] += ti;
        }
      }
    }
  }

  /// 原地逆变换（含 1/N 归一化）
  void inverse(Float64List re, Float64List im) {
    _swap(re, im);
    transform(re, im);
    _swap(re, im);
    final inv = 1.0 / n;
    for (var i = 0; i < n; i++) {
      re[i] *= inv;
      im[i] *= inv;
    }
  }

  static void _swap(Float64List a, Float64List b) {
    for (var i = 0; i < a.length; i++) {
      var t = a[i]; a[i] = b[i]; b[i] = t;
    }
  }
}

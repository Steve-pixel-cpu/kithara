# 吉他调音器实施计划（Part 2/3：Task 3-4 DSP 核心）

> 接 Part 1。Global Constraints / Review Focus 见 Part 1，全局适用。

---

### Task 3: PitchDetector——MPM 音高检测（TDD）

**Files:**
- Create: `lib/dsp/fft.dart`
- Create: `lib/dsp/pitch_detector.dart`
- Test: `test/dsp/fft_test.dart`
- Test: `test/dsp/pitch_detector_test.dart`

**Interfaces:**
- Consumes: 无（FFT 纯 Dart）
- Produces（后续任务按此签名消费）:

```dart
// lib/dsp/fft.dart
class FFT {
  FFT(int size);                    // size 必须是 2 的幂，否则 AssertionError
  void transform(Float32List re, Float32List im);  // 原地正变换
  void inverse(Float32List re, Float32List im);    // 原地逆变换（含 1/N 归一化）
  int get size;
}

// lib/dsp/pitch_detector.dart
class PitchDetector {
  PitchDetector({
    double sampleRate = 44100.0,
    int window = 4096,
    double minFreq = 65.0,          // chromatic 用 60.0
    double maxFreq = 350.0,         // chromatic 用 1300.0
  });
  double? detect(Float32List frame); // null = 置信度<0.85 或 f0 超出 [minFreq, maxFreq]
  double get lastConfidence;         // 最近一次 detect 的 NSDF 峰值 (0~1)
}
```

**实现规格（Task 3a FFT，验收 = 3a 测试全绿）：**
- 构造期预计算：位反转表 `Uint32List(n)`、旋转因子表 `Float32List(n/2)` 存 `cos(-2πk/n)` 与 `sin(-2πk/n)`
- `transform`：按 `_rev` 置换 re/im → 三级循环 `len=2,4,...,n`（`halfLen=len>>1`，`step=n~/len`，twiddle 索引 `j*step`）
- `inverse`：swap(re,im) → transform → swap 回 → 全体乘 1/n
- 构造后热路径零堆分配（只用预分配表与调用方的 buffer）
- 迭代式 radix-2 Cooley-Tukey，~120 行以内

**MPM 算法规格（Task 3b PitchDetector，验收 = 3b 测试全绿）：**
1. 预分配 `Float32List`：`_re`、`_im`（window）、`_sqCum`（window+1）、`_nsdf`（maxLag+1，`maxLag = (sr/minFreq).ceil()`）
2. detect 步骤：
   - 去直流（frame 减均值，写入 `_re`，`_im` 清零）
   - `fft.transform(_re, _im)` → 功率谱 `|X|²` 写回 `_re`，`_im` 清零
   - `fft.inverse(_re, _im)` 得自相关 r（Wiener–Khinchin）
   - 平方前缀和：`_sqCum[i] = Σ_{j<i} frame²`（用原始 frame，不是去直流后？——**用去直流后的 `_re`**，保持一致）
   - `NSDF[lag] = 2r[lag] / m[lag]`，其中 `m[lag] = (_sqCum[n] - _sqCum[lag]) + (_sqCum[n-lag] - _sqCum[0])`
3. McLeod 峰挑选：从 `maxLag = (sr/maxLag... )`——**精确语义**：正 lag 范围 `[minLag, maxLag]`（`minLag = (sr/maxFreq).floor()`，`maxLag = (sr/minFreq).ceil()`），从 maxLag 向 minLag 扫描，找局部极大值（`nsdf[l-1] < nsdf[l] >= nsdf[l+1]` 且 nsdf[l] > 0），记录**第一个**峰值 ≥ k=0.9 的峰（从长周期向短周期扫 = 取基频方向）
4. 子谐波复查：若 2×lag 在范围内且 nsdf[2×lag] ≥ 0.85 且 nsdf[2×lag] > nsdf[lag] + 0.001 → lag = 2×lag（仅一次）
5. 抛物线插值：三点 `(lag-1, lag, lag+1)` 的 nsdf 值，`δ = (nsdf[l-1] - nsdf[l+1]) / (2·(nsdf[l-1] - 2·nsdf[l] + nsdf[l+1]))`，`f0 = sr / (lag + δ)`
6. `lastConfidence = nsdf[lag]`（插值前峰值）；< 0.85 → null
7. f0 超出 `[minFreq, maxFreq]` → null

- [ ] **Step 1: 写 FFT 失败测试**

```dart
// test/dsp/fft_test.dart
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tuner/dsp/fft.dart';

void main() {
  group('FFT 4096', () {
    final fft = FFT(4096);

    test('单频正弦在正确 bin 出峰', () {
      final re = Float32List(4096), im = Float32List(4096);
      const freq = 82.41, sr = 44100.0;
      for (var i = 0; i < 4096; i++) {
        re[i] = math.sin(2 * math.pi * freq * i / sr);
      }
      fft.transform(re, im);
      var best = 0, bestMag = -1.0;
      for (var k = 1; k < 2048; k++) {
        final mag = re[k] * re[k] + im[k] * im[k];
        if (mag > bestMag) { bestMag = mag; best = k; }
      }
      expect(best, anyOf(7, 8)); // 82.41·4096/44100 ≈ 7.65
    });

    test('直流信号能量集中 bin 0', () {
      final re = Float32List.fromList(List.filled(4096, 1.0));
      final im = Float32List(4096);
      fft.transform(re, im);
      expect(re[0], closeTo(4096, 1e-3));
      for (var k = 1; k < 2048; k++) {
        expect(math.sqrt(re[k] * re[k] + im[k] * im[k]), lessThan(1e-3));
      }
    });

    test('逆变换往返恢复原信号 (误差 < 1e-3)', () {
      final re = Float32List(4096), im = Float32List(4096);
      final rng = math.Random(42);
      for (var i = 0; i < 4096; i++) {
        re[i] = rng.nextDouble() * 2 - 1;
        im[i] = rng.nextDouble() * 2 - 1;
      }
      final re0 = Float32List.fromList(re), im0 = Float32List.fromList(im);
      fft.transform(re, im);
      fft.inverse(re, im);
      for (var i = 0; i < 4096; i++) {
        expect(re[i], closeTo(re0[i], 1e-3));
        expect(im[i], closeTo(im0[i], 1e-3));
      }
    });
  });

  test('非 2 的幂 size 抛 AssertionError', () {
    expect(() => FFT(4095), throwsA(isA<AssertionError>()));
  });
}
```

- [ ] **Step 2: 确认失败** — `flutter test test/dsp/fft_test.dart` FAIL（fft.dart 不存在）

- [ ] **Step 3: 按实现规格写 `lib/dsp/fft.dart`**（要点：位反转表 + 旋转因子预计算；transform 原地蝶形；inverse 经 re/im swap + 1/n）

- [ ] **Step 4: 确认通过** — `flutter test test/dsp/fft_test.dart` PASS

- [ ] **Step 5: 写 PitchDetector 失败测试**

```dart
// test/dsp/pitch_detector_test.dart
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tuner/dsp/pitch_detector.dart';

final sr = 44100.0;

/// 合成弦音：基频+2/3/4 次谐波（幅度 0.5/0.25/0.125/0.0625），可选白噪声。
/// f0<=0 时返回纯噪声（测安静/门控场景）。
Float32List synth(double f0, {int n = 4096, double noise = 0, int? seed, double phaseSamples = 0}) {
  final rng = seed == null ? null : math.Random(seed);
  final buf = Float32List(n);
  for (var i = 0; i < n; i++) {
    final t = (i + phaseSamples) / sr;
    var s = 0.0;
    if (f0 > 0) {
      s = 0.5 * math.sin(2 * math.pi * f0 * t) +
          0.25 * math.sin(2 * math.pi * 2 * f0 * t) +
          0.125 * math.sin(2 * math.pi * 3 * f0 * t) +
          0.0625 * math.sin(2 * math.pi * 4 * f0 * t);
    }
    if (noise > 0 && rng != null) {
      s += (rng.nextDouble() * 2 - 1) * noise;
    }
    buf[i] = s;
  }
  return buf;
}

void main() {
  late PitchDetector det;

  setUp(() => det = PitchDetector());

  test('场景2: 六弦精确频率 + Drop D D2 边缘频率全部检出 ±0.5Hz', () {
    final cases = [73.42, 82.41, 110.0, 146.83, 196.0, 246.94, 329.63];
    for (final f in cases) {
      final out = det.detect(synth(f));
      expect(out, isNotNull, reason: 'freq=$f 未检出');
      expect(out!, closeTo(f, 0.5), reason: 'freq=$f');
      expect(det.lastConfidence, greaterThanOrEqualTo(0.85));
    }
  });

  test('场景3: +10 cent 检出', () {
    final f = 82.41 * math.pow(2, 10 / 1200);
    final out = det.detect(synth(f));
    expect(out, isNotNull);
    expect(out!, closeTo(f, 0.5));
  });

  test('场景4: 抗八度错误——2次谐波强于基频仍报基频', () {
    // 手工构造：基频 0.1，二次谐波 0.5
    final buf = Float32List(4096);
    for (var i = 0; i < 4096; i++) {
      final t = i / sr;
      buf[i] = 0.1 * math.sin(2 * math.pi * 82.41 * t) +
          0.5 * math.sin(2 * math.pi * 164.82 * t);
    }
    final out = det.detect(buf);
    expect(out, isNotNull);
    expect(out!, closeTo(82.41, 0.5), reason: '应报基频 82.41 而非 164.82');
  });

  test('场景5: 噪声鲁棒 (noise=0.3)', () {
    final out = det.detect(synth(110.0, noise: 0.3, seed: 7));
    expect(out, isNotNull);
    expect(out!, closeTo(110.0, 0.5));
  });

  test('场景6: 纯噪声 → null (置信度门控)', () {
    final out = det.detect(synth(0, noise: 0.3, seed: 1));
    expect(out, isNull);
  });

  test('场景7: 超范围频率 → null', () {
    expect(det.detect(synth(500.0)), isNull);   // > 350
    expect(det.detect(synth(50.0)), isNull);    // < 65
  });

  test('chromatic 模式 500Hz 可检出', () {
    final wide = PitchDetector(minFreq: 60.0, maxFreq: 1300.0);
    final out = wide.detect(synth(500.0));
    expect(out, isNotNull);
    expect(out!, closeTo(500.0, 1.0));
  });
}
```

- [ ] **Step 6: 确认失败** — `flutter test test/dsp/pitch_detector_test.dart` FAIL（pitch_detector.dart 不存在）

- [ ] **Step 7: 按算法规格实现 `lib/dsp/pitch_detector.dart`**

- [ ] **Step 8: 确认通过** — `flutter test test/dsp/pitch_detector_test.dart` PASS（若场景 4 八度错误测试失败，检查子谐波复查方向与扫描方向）

- [ ] **Step 9: Commit**

```bash
git add lib/dsp/fft.dart lib/dsp/pitch_detector.dart test/dsp/
git commit -m "feat(dsp): FFT + MPM pitch detector with octave-error resistance"
```

---

### Task 4: TuningModes + TunerController（TDD）

**Files:**
- Create: `lib/tuner/tuning_modes.dart`
- Create: `lib/tuner/tuner_controller.dart`
- Test: `test/tuner/tuning_modes_test.dart`
- Test: `test/tuner/tuner_controller_test.dart`

**Interfaces:**
- Consumes: `PitchDetector.detect(Float32List) → double?`、`.lastConfidence`（Task 3）；`NoteMapper`（Task 2）
- Produces（后续任务按此签名消费）:

```dart
// lib/tuner/tuning_modes.dart
enum TuningMode { standard, dropD, openD, openG, dadgad, chromatic }

class StringDef {
  final String label;        // "E2"
  final int semitoneIndex;   // 距 A4 半音数
  final double baseFreq;     // A4=440 时的频率
  const StringDef(this.label, this.semitoneIndex, this.baseFreq);
}

/// 各调弦模式 6 弦定义（低→高）；chromatic 返回 const []
List<StringDef> stringsFor(TuningMode m);

// lib/tuner/tuner_controller.dart
class TuningState {
  final int? stringIndex;    // 当前锁定弦（chromatic 永远 null）
  final String note;         // 显示音名 "E2"
  final double cents;        // 平滑后偏差
  final bool inTune;         // |cents|<5 持续 3 帧
  final bool hasSignal;      // 最近帧有有效信号
  const TuningState({this.stringIndex, this.note = '', this.cents = 0,
      this.inTune = false, this.hasSignal = false});
  TuningState copyWith({...});  // 全字段
}

class TunerController {
  final ValueNotifier<TuningState> state;   // 初始 TuningState()（全部默认值）
  final ValueNotifier<double> needle;       // 平滑 cents，初始 0
  final ValueNotifier<String> noteLabel;    // 初始 ''
  TunerController({PitchDetector? detector, NoteMapper? mapper});
  void onPitch(double? freq);  // 音频管线每帧调（freq=null = 无信号）
  void setMode(TuningMode m);  // 重置锁定弦/滤波器/稳定计数
  void setA4(double hz);       // 重建 NoteMapper，立即刷新显示
  void dispose();
}
```

**每帧流水线语义（onPitch 实现，验收 = 测试全绿）：**
1. `freq == null` → `state.hasSignal=false`（其余字段保持），needle/noteLabel 不动，直接返回
2. 确定目标弦（chromatic 除外）：对每根弦算 `d = |centsOffset(freq 相对该弦)|`；`d > 300` 的弦排除；取 d 最小者为候选；**粘滞规则**：若当前锁定弦的 d ≤ 30 则保持当前锁定弦
3. 计算相对锁定目标（锁定弦的 semitoneIndex；chromatic 用 nearestSemitoneIndex）的原始 cents
4. 中值滤波（3 帧窗口，含野值剔除）→ 得 filteredCents
5. 指数平滑：`needle = needle + 0.35·(filteredCents - needle)`
6. 音名稳定计数：目标音名连续 2 帧相同才更新 noteLabel；inTune 计数：`|filteredCents| < 5` 连续 3 帧 → inTune=true，否则 false
7. 组装 TuningState 写入 state，hasSignal=true

**测试规格（写 `test/tuner/tuning_modes_test.dart` + `test/tuner/tuner_controller_test.dart`，验收标准）：**

tuning_modes_test:
1. `stringsFor(standard)` 6 弦：label 依次 E2/A2/D3/G3/B3/E4；baseFreq 依次 82.41/110.00/146.83/196.00/246.94/329.63（closeTo 0.01）；semitoneIndex 依次 -29/-24/-17/-12/-10/-5
2. `stringsFor(dropD)` 第 0 弦 label=D2、baseFreq=73.42、semitoneIndex=-31，其余同 standard
3. `stringsFor(chromatic)` 为空
4. openD = [D2 73.42 -31, A2 110 -24, D3 146.83 -17, F#3 185.00 -20, A3 220.00 -14, D4 293.66 -19]
5. openG = [D2 73.42 -31, G2 98.00 -26, D3 146.83 -17, G3 196.00 -12, B3 246.94 -10, D4 293.66 -19]
6. dadgad = [D2 73.42 -31, A2 110 -24, D3 146.83 -17, G3 196.00 -12, A3 220.00 -14, D4 293.66 -19]

tuner_controller_test（直接 new TunerController()，用 onPitch 注入频率）:
1. `onPitch(82.41)` ×3 → state.stringIndex=0、note="E2"、needle≈0、inTune=true
2. `onPitch(82.41·2^(25/1200))` ×3 → stringIndex=0、needle≈+25（容差 1.0）
3. 粘滞锁定：`onPitch(110.0)` ×3 锁 A2 后，`onPitch(110·2^(28/1200))` ×1 → 仍 stringIndex=1；再 `onPitch(146.83)` ×3 → 切到 stringIndex=2
4. `onPitch(null)` → hasSignal=false，note 保持
5. 野值剔除：`onPitch(82.41)` ×2 → `onPitch(110)` ×1（单帧野值）→ `onPitch(82.41)` ×1 → needle 保持 ≈0（中值滤波剔除了 110 的野值，不发生弦切换）
6. `setA4(430)` 后 `onPitch(107.55)` ×3 → note="A2"、needle≈0；`onPitch(110.0)` ×3 → needle≈+36（容差 1.5）
7. `setMode(dropD)` 重置锁定后 `onPitch(73.42)` ×3 → stringIndex=0、note="D2"
8. chromatic：`setMode(chromatic)` 后 `onPitch(440)` ×3 → stringIndex=null、note="A4"、needle≈0

- [ ] **Step 1: 写两个失败测试文件**（按上面规格）

- [ ] **Step 2: 确认失败** — `flutter test test/tuner/` FAIL

- [ ] **Step 3: 实现 tuning_modes.dart + tuner_controller.dart**（按 Produces 签名 + 流水线语义）

- [ ] **Step 4: 确认通过** — `flutter test test/tuner/` PASS

- [ ] **Step 5: Commit**

```bash
git add lib/tuner/ test/tuner/
git commit -m "feat(tuner): tuning modes + TunerController with sticky string lock"
```

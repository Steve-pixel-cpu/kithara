# 吉他调音器实施计划（Part 1/3：总览 + Task 1-2）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 本计划分 3 个文件，按序执行：Part 1 (Task 1-2) → Part 2 (Task 3-6) → Part 3 (Task 7-11)。

**Goal:** 双平台（Android/iOS）吉他调音 App——实时麦克风音高检测 + 弦自动识别 + 参考音播放。

**Architecture:** Flutter 单代码库；麦克风 Float32 PCM 流 → 主 Isolate 直跑 MPM 音高检测（FFT 加速自相关，零 GC 热路径）→ ValueNotifier 驱动 CustomPainter 指针仪表。DSP 层纯 Dart 不依赖 Flutter，全部可单测。

**Tech Stack:** Flutter 3.x / Dart 3, `record`, `audioplayers`, `shared_preferences`, `flutter_test`。

**Spec:** `docs/superpowers/specs/2026-10-28-guitar-tuner-design.md`

## Global Constraints

- 依赖仅 3 个包：`record`、`audioplayers`、`shared_preferences`（`flutter pub add` 最新稳定版）
- 音频参数固定：44100 Hz、mono、Float32 PCM、分析窗口 4096、步进 2048
- A4 默认 440 Hz，可调范围 430–450 Hz
- 标准 A4=440 六弦精确频率（Hz）：E2=82.41, A2=110.00, D3=146.83, G3=196.00, B3=246.94, E4=329.63；Drop D 6 弦 D2=73.42
- 距 A4 半音数：E2=-29, A2=-24, D3=-17, G3=-12, B3=-10, E4=-5
- 调弦模式频率检测范围 65–350 Hz；chromatic 60–1300 Hz
- MPM 参数：k 门限 0.9；子谐波复查仅当 2×lag 处 NSDF ≥ 0.85 且严格高于当前峰（> 当前 + 0.001）才移动到 2×lag，仅一次不级联；置信度门限 0.85
- 平滑参数：中值滤波 3 帧；指针指数平滑 α=0.35；音名连续 2 帧才切换；调准 = |cents| < 5 持续 3 帧
- DSP 层（`lib/dsp/`）禁止 import Flutter framework（`flutter_test` 仅用于测试文件）；热路径零堆分配——所有 Float32List 预分配复用
- 每个 Dart 文件 ≤ 400 行；`flutter analyze` 零 warning 零 error
- 测试统一 `flutter test`
- 弦粘滞锁定：候选弦 |cents| > 300¢ 不可锁定；已有锁定弦 |cents| ≤ 30¢ 时保持锁定
- UI 决策记录：跳过 widget 冒烟测试（audioplayers 平台通道 mock 复杂度不值，真机验收兜底）；UI 验收 = `flutter analyze` 零警告 + Task 10 真机清单
- 参考音决策记录：真实吉他采样无来源，用 Karplus-Strong 合成拨弦音（有谐波结构、听感接近拨弦，满足 spec"非正弦波"意图）；接口不变，后续可换真实采样

## Review Focus

1. **极端 A4 校准值 (430 Hz) 下 cents 计算**——期望 A2@440 的 110.0 Hz 显示 ≈ +36¢ 而非 0；Task 2 已覆盖（A4=430 group）
2. **Drop D 的 D2 73.42 Hz 落在 65 Hz 检测下限边缘**——期望正确检出 ±0.5 Hz 不被范围门限误杀；Task 3 场景 2 频率表已含 73.42
3. **连续单帧野值（毛刺）**——期望中值滤波 3 帧窗口完全剔除、指针不抖；Task 4 测试规格 6 已覆盖
4. **音名恰在 ±50.0 cent 交界**——期望取偏高半音（上界）且粘滞显示防闪烁；Task 2 已覆盖交界、Task 4 规格覆盖粘滞
5. **权限拒绝→去设置→授权返回**——期望不崩溃、resumed 自动重启 mic；Task 8 实现入口 + Task 10 清单 8 真机验证

---

### Task 1: Flutter 项目脚手架

**Files:**
- Create: `pubspec.yaml`、`lib/main.dart`、`android/`、`ios/`、`.gitignore`（flutter create 生成）
- Delete: `test/widget_test.dart`（默认计数器测试，UI 决策跳过 widget 测试，直接删）

**Interfaces:**
- Consumes: 无
- Produces: 可编译 Flutter 项目；`flutter analyze` / `flutter test` 可用；包名 `guitar_tuner`，import 前缀 `package:guitar_tuner/...`

- [ ] **Step 1: 创建项目**

```bash
cd /d/guitar-tuner
flutter create --org dev.personal --project-name guitar_tuner --platforms android,ios .
```

- [ ] **Step 2: 删除默认测试，验证基线**

```bash
rm test/widget_test.dart
flutter analyze && flutter test
```

Expected: `No issues found!`；`flutter test` 报"No tests were found"属正常（测试随任务逐个添加），不视为失败

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "chore: flutter project scaffold (android+ios)"
```

---

### Task 2: NoteMapper——频率 ↔ 音名映射（TDD）

**Files:**
- Create: `lib/dsp/note_mapper.dart`
- Test: `test/dsp/note_mapper_test.dart`

**Interfaces:**
- Consumes: 无（纯 Dart，仅 `dart:math`）
- Produces（后续任务按此签名消费）:

```dart
class NoteMapper {
  NoteMapper({double a4 = 440.0});
  int nearestSemitoneIndex(double freq);   // 距 A4 半音数（四舍五入到最近半音）
  String noteName(int semitoneIndex);      // 如 semitoneIndex=-29 → "E2"
  double centsOffset(double freq);         // 相对最近半音的偏差，[-50.0, +50.0]，+ 为偏高
  double frequencyOf(int semitoneIndex);   // 该半音理论精确频率
}
```

- [ ] **Step 1: 写失败测试**

```dart
// test/dsp/note_mapper_test.dart
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tuner/dsp/note_mapper.dart';

void main() {
  group('NoteMapper (A4=440)', () {
    final mapper = NoteMapper();

    test('六根标准弦音名正确', () {
      expect(mapper.noteName(mapper.nearestSemitoneIndex(82.41)), 'E2');
      expect(mapper.noteName(mapper.nearestSemitoneIndex(110.00)), 'A2');
      expect(mapper.noteName(mapper.nearestSemitoneIndex(146.83)), 'D3');
      expect(mapper.noteName(mapper.nearestSemitoneIndex(196.00)), 'G3');
      expect(mapper.noteName(mapper.nearestSemitoneIndex(246.94)), 'B3');
      expect(mapper.noteName(mapper.nearestSemitoneIndex(329.63)), 'E4');
    });

    test('精确频率 cents 偏差 ≈ 0', () {
      for (final f in [82.41, 110.00, 146.83, 196.00, 246.94, 329.63]) {
        expect(mapper.centsOffset(f), closeTo(0, 0.6), reason: 'freq=$f');
      }
    });

    test('+25 cent 输入返回 +25 cents', () {
      final up = 110.0 * math.pow(2, 25 / 1200);
      expect(mapper.centsOffset(up), closeTo(25.0, 0.1));
    });

    test('-25 cent 输入返回 -25 cents', () {
      final down = 110.0 * math.pow(2, -25 / 1200);
      expect(mapper.centsOffset(down), closeTo(-25.0, 0.1));
    });

    test('±50 cent 交界取偏高半音（上界）', () {
      final boundary = 110.0 * math.pow(2, 49.9 / 1200);
      expect(mapper.noteName(mapper.nearestSemitoneIndex(boundary)), 'A#2');
    });

    test('frequencyOf 往返一致', () {
      for (final semi in [-29, -24, -17, -12, -10, -5]) {
        final f = mapper.frequencyOf(semi);
        expect(mapper.nearestSemitoneIndex(f), semi);
      }
    });
  });

  group('NoteMapper (A4=430)', () {
    final mapper = NoteMapper(a4: 430.0);

    test('110Hz（A2@440）显示偏高 ≈ +36¢', () {
      expect(mapper.centsOffset(110.0), closeTo(36.3, 1.0));
    });

    test('A2@430 精确频率 cents=0', () {
      expect(mapper.centsOffset(mapper.frequencyOf(-24)), closeTo(0, 0.6));
    });
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/dsp/note_mapper_test.dart`
Expected: FAIL（`note_mapper.dart` 不存在，编译错误）

- [ ] **Step 3: 实现**

```dart
// lib/dsp/note_mapper.dart
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
    return n.round();
  }

  String noteName(int semitoneIndex) {
    final name = _names[semitoneIndex % 12]; // Dart 的 % 恒非负
    final octave = 4 + ((semitoneIndex + 9) ~/ 12);
    return '$name$octave';
  }

  double centsOffset(double freq) {
    final exact = 1200.0 * (math.log(freq) / math.ln2 - _logA4 / math.ln2);
    return exact - 100.0 * nearestSemitoneIndex(freq);
  }

  double frequencyOf(int semitoneIndex) =>
      a4 * math.pow(2.0, semitoneIndex / 12.0);
}
```

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/dsp/note_mapper_test.dart`
Expected: PASS（8 个测试）

- [ ] **Step 5: Commit**

```bash
git add lib/dsp/note_mapper.dart test/dsp/note_mapper_test.dart
git commit -m "feat(dsp): NoteMapper - freq to note name + cents offset"
```

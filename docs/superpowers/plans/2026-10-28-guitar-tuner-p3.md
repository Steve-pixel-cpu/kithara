# 吉他调音器实施计划（Part 3/3：Task 5-8 音频链路 + UI + 生命周期）

> 接 Part 2。Global Constraints / Review Focus 见 Part 1，全局适用。

---

### Task 5: RingBuffer 滑窗 + MicStream 麦克风封装

**Files:**
- Create: `lib/audio/ring_buffer.dart`
- Create: `lib/audio/mic_stream.dart`（薄封装 <80 行，无单测——真实麦克风无法单测，Task 10 真机验收兜底）
- Test: `test/audio/ring_buffer_test.dart`

**Interfaces:**
- Consumes: 无
- Produces（后续任务按此签名消费）:

```dart
// lib/audio/ring_buffer.dart
/// 环形缓冲：音频流 push 采样，调音循环消费 4096/2048 滑窗。
/// 预分配 Float32List，write/readWindow 均零堆分配（readWindow 的一次拷贝除外）。
class RingBuffer {
  RingBuffer({int capacity = 8192});   // ≥ 2×window
  void write(Float32List samples);     // 追加；超容量丢弃最旧
  Float32List? readWindow(int size);   // 可用 ≥ size → 返回 size 长度拷贝，
                                       // 读指针 += 2048（滑窗步进）；否则 null 不推进
  bool get hasWindow;                  // 可用 ≥ 4096
}

// lib/audio/mic_stream.dart
/// record 包薄封装。权限拒绝时 start() 抛 StateError('mic permission denied')。
class MicStream {
  MicStream();
  Future<void> start(void Function(Float32List chunk) onChunk); // Float32 PCM 44100Hz mono
  Future<void> stop();
  Future<bool> get hasPermission;
}
```

**RingBuffer 精确语义：**
- 内部 `Float32List(capacity)` + 写指针 + 读指针 + 已用长度
- `write`：追加 samples；若超容量，保留最新 capacity 个样本
- `readWindow(4096)`：可用 ≥ 4096 时返回**长度 4096 的拷贝**（防分析期间被覆写），读指针 +2048；否则返回 null 且不推进
- capacity 8192 = 2×window，保证 write 与 readWindow 各跑一次不互相踩踏

- [ ] **Step 1: 写 RingBuffer 失败测试**

```dart
// test/audio/ring_buffer_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tuner/audio/ring_buffer.dart';

Float32List inc(int n, [double start = 0]) {
  final b = Float32List(n);
  for (var i = 0; i < n; i++) {
    b[i] = start + i;
  }
  return b;
}

void expectSeq(Float32List w, double start) {
  for (var i = 0; i < w.length; i++) {
    expect(w[i], closeTo(start + i, 1e-4), reason: 'index $i');
  }
}

void main() {
  test('数据不足 → null', () {
    final rb = RingBuffer();
    rb.write(inc(100));
    expect(rb.readWindow(4096), isNull);
    expect(rb.hasWindow, isFalse);
  });

  test('一窗数据 → 读出 [0..4095]，推进后剩 2048 不足再读', () {
    final rb = RingBuffer();
    rb.write(inc(4096));
    expect(rb.hasWindow, isTrue);
    final w = rb.readWindow(4096)!;
    expectSeq(w, 0);
    expect(rb.hasWindow, isFalse);       // 剩 2048 < 4096
    expect(rb.readWindow(4096), isNull);
  });

  test('两窗写入 → 50% overlap 滑窗', () {
    final rb = RingBuffer();
    rb.write(inc(4096));
    rb.write(inc(4096, 4096));
    expectSeq(rb.readWindow(4096)!, 0);      // 样本 0..4095
    expectSeq(rb.readWindow(4096)!, 2048);   // 样本 2048..6143
  });

  test('溢出：写 10000 到 8192 容量 → 读出最新段 [5904..9999]', () {
    final rb = RingBuffer();
    rb.write(inc(10000));
    final w = rb.readWindow(4096)!;
    expectSeq(w, 5904);
    expect(rb.readWindow(4096), isNull); // 已耗尽
  });
}
```

- [ ] **Step 2: 确认失败** — `flutter test test/audio/` FAIL（ring_buffer.dart 不存在）

- [ ] **Step 3: 实现 `lib/audio/ring_buffer.dart`**（按精确语义）

- [ ] **Step 4: 确认通过** — `flutter test test/audio/` PASS

- [ ] **Step 5: 实现 `lib/audio/mic_stream.dart`**（无测试，按 Interfaces 规格；**执行者以 record 包当前文档核对 API**：`AudioRecorder()`、`hasPermission()`、`createStream(RecordConfig(...))`，选 Float32 PCM 流式 API（若 record 仅支持 Int16 流，则在 MicStream 内部转 Float32List 再回调，接口签名不变，并在代码注释记录该决策）；iOS 需在 `ios/Runner/Info.plist` 加 `NSMicrophoneUsageDescription`，Android 需 `RECORD_AUDIO` 权限（record 包 manifest 已带））

- [ ] **Step 6: Commit**

```bash
git add lib/audio/ test/audio/
git commit -m "feat(audio): RingBuffer sliding window + MicStream wrapper"
```

---

### Task 6: TunerPipeline 接线 + 端到端合成信号测试

**Files:**
- Create: `lib/audio/tuner_pipeline.dart`
- Modify: `lib/main.dart`（临时调试页：开始/停止按钮 + 检测结果文本；Task 7 整体替换）
- Test: `test/audio/tuner_pipeline_test.dart`

**Interfaces:**
- Consumes: `RingBuffer`（Task 5）、`PitchDetector`（Task 3）、`TunerController.onPitch(double?)`（Task 4）
- Produces（后续任务按此签名消费）:

```dart
// lib/audio/tuner_pipeline.dart
class TunerPipeline {
  TunerPipeline({required TunerController controller,
                 PitchDetector? detector, RingBuffer? buffer}); // 缺省真实实例
  void addChunk(Float32List chunk);   // 同步 write RingBuffer
  void tick();   // while (buffer.hasWindow) { controller.onPitch(detector.detect(readWindow(4096)!)) }
  void start();  // Timer.periodic(46ms, (_) => tick())
  void stop();   // 取消 timer；幂等
  void dispose(); // stop()；不拥有依赖，不 dispose 它们
}
```

- [ ] **Step 1: 写失败测试**（真 RingBuffer + 真 PitchDetector + 真 TunerController 端到端）

```dart
// test/audio/tuner_pipeline_test.dart
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tuner/audio/ring_buffer.dart';
import 'package:guitar_tuner/audio/tuner_pipeline.dart';
import 'package:guitar_tuner/dsp/pitch_detector.dart';
import 'package:guitar_tuner/tuner/tuner_controller.dart';

final sr = 44100.0;

/// 与 pitch_detector_test 相同谐波结构，相位连续（跨 chunk 不断裂）
Float32List synthCont(double f0, int n, double phaseSamples) {
  final buf = Float32List(n);
  for (var i = 0; i < n; i++) {
    final t = (i + phaseSamples) / sr;
    buf[i] = 0.5 * math.sin(2 * math.pi * f0 * t) +
        0.25 * math.sin(2 * math.pi * 2 * f0 * t) +
        0.125 * math.sin(2 * math.pi * 3 * f0 * t) +
        0.0625 * math.sin(2 * math.pi * 4 * f0 * t);
  }
  return buf;
}

void main() {
  late TunerController controller;
  late TunerPipeline pipeline;

  setUp(() {
    controller = TunerController();
    pipeline = TunerPipeline(controller: controller);
  });

  test('端到端: 3 个连续 chunk → E2 锁定 + inTune', () {
    pipeline.addChunk(synthCont(82.41, 4096, 0));
    pipeline.tick();
    expect(controller.state.value.note, 'E2');
    expect(controller.state.value.stringIndex, 0);

    pipeline.addChunk(synthCont(82.41, 4096, 4096));
    pipeline.tick();
    pipeline.addChunk(synthCont(82.41, 4096, 8192));
    pipeline.tick();
    expect(controller.state.value.inTune, isTrue);
  });

  test('多窗口 drain: 一次 8192 → tick 消费 2 窗，第 3 次 tick state 不变', () {
    pipeline.addChunk(synthCont(110.0, 8192, 0));
    pipeline.tick(); // 窗口 1
    final s1 = controller.state.value;
    pipeline.tick(); // 窗口 2
    expect(controller.state.value.note, 'A2');
    pipeline.tick(); // 无窗口
    expect(controller.state.value.hasSignal, isFalse);
    expect(controller.state.value.note, s1.note == 'A2' ? s1.note : s1.note); // note 不被清空
  });

  test('stop 幂等', () {
    pipeline.stop();
    pipeline.stop(); // 不抛错
  });
}
```

注：第 2 个测试中 `s1` 的断言意图 = "第 3 次 tick 不产生新信号，state 不被 null 帧污染"——hasSignal 变 false 是 onPitch(null) 的正常语义（Task 4 流水线第 1 步），note 保持不变。执行者若发现语义冲突，以"note 字段不被清空"为断言重点。

- [ ] **Step 2: 确认失败** — `flutter test test/audio/tuner_pipeline_test.dart` FAIL

- [ ] **Step 3: 实现 `lib/audio/tuner_pipeline.dart`**（按 Produces 规格）

- [ ] **Step 4: 确认通过** — PASS

- [ ] **Step 5: main.dart 临时调试页**（StatefulWidget：持有 controller/pipeline/micStream；开始按钮 = `await micStream.start(onChunk: pipeline.addChunk); pipeline.start();`；停止按钮反向；AnimatedBuilder(state) 显示 note/cents/stringIndex/hasSignal；权限拒绝 SnackBar。零样式要求，Task 7 整体替换）

- [ ] **Step 6: `flutter analyze` 零警告 + Commit**

```bash
git add -A && git commit -m "feat(pipeline): tuner pipeline wiring + e2e synthetic test"
```

---

### Task 7: 正式 UI——仪表、弦条、模式切换、参考音

**Files:**
- Create: `lib/ui/tuner_screen.dart`（主屏 StatefulWidget：WidgetsBindingObserver 在 Task 8 加；本任务先做纯 UI）
- Create: `lib/ui/needle_painter.dart`（CustomPainter：弧形刻度 -50¢~+50¢，红→绿色带，指针位置 = needle ValueListenable）
- Create: `lib/ui/string_bar.dart`（六弦条 Row：检测弦高亮 + 点击播参考音）
- Create: `lib/ui/mode_sheet.dart`（BottomSheet：六模式列表 + 当前项高亮 + 点击即生效）
- Create: `lib/ui/tone_player.dart`（参考音封装：audioplayers AssetSource 预建 6 个，`play(StringDef)` / `stop()`）
- Create: `assets/audio/string_e2.wav` … `string_e4.wav`（6 个，Karplus-Strong 合成拨弦音）
- Create: `scripts/gen_tones.py`（生成脚本，python3 标准库 wave 模块，**提交**——便于以后换采样重生成）
- Modify: `pubspec.yaml`（`flutter pub add audioplayers` + assets 声明 `assets/audio/`）
- Delete: `lib/main.dart` 临时调试页内容 → 替换为 `runApp(MaterialApp(theme: dark, home: TunerScreen()))`

**Interfaces:**
- Consumes: `TunerController.state/needle/noteLabel`（Task 4）、`stringsFor(TuningMode)`（Task 4）、`MicStream`（Task 5）、`TunerPipeline`（Task 6）、`TunerSettings`（Task 9 接线时引入，本任务可先硬编码 standard/440）
- Produces: 正式调音界面（真机可用）

**UI 规格（按 spec §5）：**
- 深色主题 + 锁竖屏（AndroidManifest `screenOrientation="portrait"` / Info.plist）
- 顶部行：当前模式名（点击开 ModeSheet）+ A4 显示 440（长按弹滑块 430–450，Task 9 接持久化）
- 中央：大字号音名（72pt，noteLabel）+ 频率/cents 文本行
- 弧形仪表：CustomPainter 画 -50¢~+50¢ 刻度弧 + 红→绿渐变色带 + 指针（needle 值映射到弧上角度，`ValueListenableBuilder<double>` 只重绘此画布）
- 六弦条：`stringsFor(mode)` 渲染 6 个弦块，`state.stringIndex` 高亮，点击 → `tonePlayer.play(stringsFor(mode)[i])`，再点 stop；chromatic 模式弦条区显示提示文字"Chromatic——无弦锁定"
- 状态栏：hasSignal=false 时 "Listening…" 呼吸动画（AnimatedOpacity 循环）；inTune 时 "In Tune ✓"
- 权限拒绝态：整屏说明 + "去设置"按钮（Task 8 完整接线）

**Karplus-Strong 生成规格（gen_tones.py）**：每弦 2 秒 44100Hz 16-bit mono：环缓冲 `D = round(sr/f0)` 个白噪声初始化；每输出样本 `out = 0.5·(buf[i%D] + buf[(i+1)%D])`，`buf[i%D] = out`；输出乘指数衰减包络 `e^(-t/0.8)`；归一化峰值 0.8；写 16-bit PCM WAV。六弦 f0 = [82.41, 110.0, 146.83, 196.0, 246.94, 329.63]，文件名 string_e2/a2/d3/g3/b3/e4.wav。

- [ ] **Step 1: 生成参考音** — `python3 scripts/gen_tones.py` → 确认 6 个 wav 生成且时长 2s

- [ ] **Step 2: pubspec.yaml 依赖 + assets** — `flutter pub add audioplayers`；flutter: assets: [- assets/audio/]

- [ ] **Step 3: 实现 tone_player.dart**（audioplayers：`AudioPlayer.play(AssetSource('assets/audio/string_e2.wav'))`，播放前 `setReleaseMode(release)` 自动停；同弦再点 → stop()）

- [ ] **Step 4: 实现 needle_painter.dart + string_bar.dart + mode_sheet.dart + tuner_screen.dart**（按 UI 规格；每文件 ≤400 行）

- [ ] **Step 5: main.dart 替换为正式入口**（深色 ThemeData + TunerScreen）

- [ ] **Step 6: `flutter analyze` 零警告 + Commit**

```bash
git add -A && git commit -m "feat(ui): tuner screen, needle gauge, string bar, mode sheet, KS reference tones"
```

---

### Task 8: 生命周期 + 权限拒绝态 + 触觉反馈

**Files:**
- Modify: `lib/ui/tuner_screen.dart`（WidgetsBindingObserver + 权限拒绝态 + inTune 震动）
- Modify: `lib/ui/tone_player.dart`（如需：iOS 静音键场景确认 playback 类别，audioplayers 默认满足，仅注释记录）

**语义规格：**
- `WidgetsBindingObserver.didChangeAppLifecycleState`：paused/inactive → `pipeline.stop() + micStream.stop()`；resumed → 权限仍在则 `micStream.start + pipeline.start`，权限被吊销则切权限拒绝态
- 权限拒绝态 UI：整屏说明文案 + "去设置"按钮 → record 包的 `openAppSettings()`（或 `AudioRecorder` 对应 API，以包文档为准）——**不引入 permission_handler**（Global Constraints 3 包限制）
- inTune 边沿震动：监听 state，`inTune` 从 false→true 时 `HapticFeedback.mediumImpact()`（用 state.value 的前一值对比，或 controller 内加 inTune 边沿回调——执行者选实现简单者，语义 = 只在变绿瞬间震一次）

- [ ] **Step 1: 实现三处语义**（lifecycle observer / 权限拒绝态 / 震动）

- [ ] **Step 2: `flutter analyze` 零警告**

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat(ui): lifecycle handling, permission-denied state, in-tune haptics"
```

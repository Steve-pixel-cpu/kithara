# Kithara 吉他调音器

Flutter 实现的移动端吉他调音器（Android 优先，iOS 就绪）。

## 功能

- **实时调音**：麦克风采集 → MPM 音高检测 → 音名 + cents 偏差 + 指针仪表
- **6 种调弦模式**：标准 (E A D G B E)、Drop D、Open D、Open G、DADGAD、半音阶
- **参考音可调**：A4 = 430–450 Hz，设置持久化
- **触觉反馈**：调准（±5¢）时震动脉冲一次
- **智能细节**：调准绿色指示、锁弦防抖、信号丢失保留显示、后台自动停麦

## 构建

```bash
flutter pub get
flutter run            # 开发运行
flutter test           # 全部测试（55 个）
flutter build apk --release   # 出 release APK
```

APK 输出：`build/app/outputs/flutter-apk/app-release.apk`

## 架构

```
mic_stream.dart   麦克风采集 (record 包, 16-bit PCM → float)
ring_buffer.dart  环形缓冲（溢出丢旧）
fft.dart          radix-2 FFT (float64, 预计算表)
pitch_detector.dart  MPM: 自相关 + NSDF + McLeod 峰挑选
note_mapper.dart  频率 ↔ 音名/半音/cents
tuning_modes.dart 6 模式弦表 + 吸附匹配
tuner_controller.dart  状态机 (ChangeNotifier)
tuner_settings.dart    设置持久化 (shared_preferences)
ui/tuner_screen.dart   主界面 (仪表/弦条/权限态)
```

数据流：`MicStream → RingBuffer → PitchDetector → TunerController → UI (Ticker 驱动)`

## 测试与验收

- `test/`：55 个测试（DSP 单元、端到端、widget、持久化）
- `docs/acceptance.md`：真机验收清单（权限/调音/模式/抗噪/性能，22 项）
- `docs/superpowers/specs/`：设计规格；`plans/`：实施计划

## 关键参数

| 参数 | 值 |
|------|-----|
| 采样率 | 44100 Hz |
| 检测窗口 | 4096 样本（FFT 8192 零填充） |
| 检测范围 | 65–350 Hz（标准吉他弦域） |
| 置信度门限 | 0.85 (NSDF) |
| 调准阈值 | ±5 cents |
| 指针满偏 | ±50 cents |

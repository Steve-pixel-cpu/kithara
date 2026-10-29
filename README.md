<div align="center">

<img src="assets/icon/app_icon_512.png" width="128" alt="Kithara 图标" />

# Kithara 吉他 / 尤克里里调音器

**实时音高检测 · 12 种调弦 · 纯手工 DSP，无第三方音频算法库**

Flutter 打造的 Android 调音器（本项目不做 iOS 端）。

[![Release](https://img.shields.io/github/v/release/Steve-pixel-cpu/kithara?label=%E4%B8%8B%E8%BD%BD&color=2ea44f)](https://github.com/Steve-pixel-cpu/kithara/releases)

</div>

## 下载安装

从 [Releases](https://github.com/Steve-pixel-cpu/kithara/releases) 下载最新的 `kithara-x.y.z.apk`，传到手机直接安装（debug 签名，首次安装需允许「未知来源」）。

## 功能

- **实时调音**：麦克风采集 → MPM 音高检测（Float64 FFT）→ 音名大字 + cents 偏差 + 发光环指针仪表
- **12 种调弦**：吉他 8 种（标准 / Drop D / Drop C / Eb / D / Open D / Open G / DADGAD）+ 尤克里里 3 种 + 半音阶
- **参考音可调**：A4 = 430–450 Hz，设置持久化
- **粘性锁弦**：检测到弦后锁定目标，临近半音不抢跳；手动点弦条可强制指定
- **八度归一**：同音名跨八度（如 E2/E3/E4）自动归位到目标弦，松弦乱跳不存在的
- **量程自适应仪表**：偏差 ±50 / ±250 / ±500¢ 三档自动切换，大偏差也能看清方向
- **降噪三档**：RMS 门控（低/中/高）过滤环境噪声
- **引导方向**：指针 + 文字双向引导（拧紧 / 拧松，差多少¢），方向从第一天起就是对的
- **触觉反馈**：调准（±5¢）时震动脉冲一次
- **深浅双主题**：深色 / 浅色 / 跟随系统三态，选择持久化

## 自建 DSP（为什么不用库）

音频链路全部手写，可单测、可复现：

```
mic_stream.dart      麦克风采集 (record 包, 16-bit PCM → float)
ring_buffer.dart     环形缓冲（16384, 溢出丢旧）
fft.dart             radix-2 FFT (float64, 预计算表)
pitch_detector.dart  MPM: 自相关 + NSDF + McLeod 峰挑选 + 功率谱预检
note_mapper.dart     频率 ↔ 音名/半音/cents
tuning_modes.dart    12 模式弦表 + 吸附匹配
tuner_controller.dart  状态机 (ChangeNotifier)：粘性锁/八度归一/量程自适应
tuner_settings.dart    设置持久化 (shared_preferences)
ui/                  发光环仪表 (CustomPainter) + 主界面 + 平台服务
```

数据流：`MicStream → RingBuffer → PitchDetector → TunerController → UI`

- **检测节流 10Hz**（100ms）：超出人手耳反应分辨率的不多算，采集与指针动画仍 60fps
- **指针平滑**：150ms easeOutCubic 过渡到读数，静默 2s 后悠回待命位
- **不跳八度**：功率谱预检 + McLeod 两步峰挑选，E4=329.63Hz 报 329 而非 82

## 关键参数

| 参数 | 值 |
|------|-----|
| 采样率 | 44100 Hz |
| 检测窗口 | 4096 样本（FFT 8192 零填充） |
| 检测范围 | 65–350 Hz（覆盖 Drop C 低音 E2 到高频 B4） |
| 置信度门限 | 0.85 (NSDF) |
| 调准阈值 | ±5 cents |
| 降噪门控 | RMS 0.0 / 0.008 / 0.02（低/中/高） |

## 本地构建

```bash
flutter pub get
flutter test --exclude-tags=golden   # 121 个测试（golden 像素比对需本地环境）
flutter build apk --release
```

APK 输出：`build/app/outputs/flutter-apk/app-release.apk`

App 图标是外部工具处理好的方形成品（`assets/icon/`，深色满铺构图），直接拷入
`res/mipmap-*/ic_launcher.png` 使用，**不走 adaptive 前景/背景**（方形图套 adaptive
遮罩会把主体缩进安全区，白底上浮小图标——就是上一版「图标有点奇怪」的根因）。
若改动 `assets/icon/app_icon.png` 后想重新生成：

```bash
dart run flutter_launcher_icons
```

CI（`.github/workflows/release.yml`）：push `v*` 标签自动构建并发布 Release。

## 测试

- `test/`：121 个测试——DSP 单元、端到端、八度稳定性矩阵（11 调弦 × 弦 × 3 泛音全过 ±5¢）、widget、持久化
- `docs/acceptance.md`：真机验收清单（22 项）

## 协议

MIT

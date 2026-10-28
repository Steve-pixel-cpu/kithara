# 吉他调音器 App 设计文档

- **日期**: 2026-10-28
- **状态**: 待用户评审
- **路径**: Architectural（新项目）

## 1. 目标与定位

**个人日常使用的吉他调音工具**，Android + iOS 双平台，一个代码库。

成功标准：
- 拿真吉他能快速调准六根弦，指针稳、不乱跳、无八度错误
- 冷启动到可调音 < 2s
- 调准反馈清晰（颜色 + 触觉震动），暗光环境可读

明确不做：账号系统、广告、引导页、多乐器（贝斯/尤克里里）、节拍器。

## 2. 技术选型

| 层 | 选择 | 理由 |
|----|------|------|
| 框架 | Flutter (Dart) | 双平台单代码库；热重载；个人工具开发效率优先 |
| 音频捕获 | `record` 包 (44.1kHz mono Float32 PCM 流) | 自带权限处理，少一个依赖（不引 permission_handler） |
| 音高检测 | 纯 Dart MPM（FFT 加速自相关 + NSDF） | <1ms/帧，精度 <1 cent，零原生胶水代码 |
| 参考音播放 | `audioplayers` | 播放打包的真实吉他采样 |
| 状态管理 | ValueNotifier | 单屏应用，精准驱动指针画布和音名文本重建，零框架开销 |
| 持久化 | `shared_preferences` | 记住调弦模式 / A4 校准值 |

依赖仅 3 个包：`record`、`audioplayers`、`shared_preferences`。

## 3. 架构与性能设计

**性能目标**: 主 Isolate 直跑 DSP（4096 点 FFT + MPM < 1ms），分析节流 ~20Hz
（窗口 4096 / 步进 2048 @ 44.1kHz ≈ 每 46ms 一帧），占主线程 <2%。不做 Isolate——
跨 Isolate 传 buffer 多一次拷贝与通信开销；`PitchEngine` 设计为纯同步函数，
将来 profile 出问题再无痛迁移到 worker isolate。

```
麦克风 PCM 流 (44.1kHz, mono, Float32)
   ↓
RingBuffer 滑窗 (4096/2048 → 每 46ms 一帧)
   ↓
PitchEngine.detect()          ← 主 Isolate, <1ms/帧
   ├─ MPM: 去直流 → Hann 窗 → FFT → IFFT 自相关 → NSDF → 峰挑选
   ├─ 置信度门限 (<0.85 丢弃)
   └─ 中值滤波(3帧) + cents 指数平滑(α=0.35)
   ↓
TuningState (immutable: {note, cents, stable})
   ↓ 两个独立 ValueNotifier
   ├─ needleNotifier → ValueListenableBuilder → CustomPainter (只重绘指针画布)
   └─ noteNotifier   → 音名变化时才 rebuild 大字号文本
```

**热路径零 GC**: DSP 全部预分配 Float32List 复用，无临时对象、无闭包分配——
GC 停顿是指针卡顿的头号元凶。

**粘滞锁定**: 锁定当前弦持续追踪，直到频谱明显切到别的弦才切换，避免两根弦间跳变。

**冷启动**: 麦克风初始化与首帧渲染并行。

## 4. 音高检测算法（MPM）

流程：
1. 去直流（buffer 减均值）
2. FFT (4096) → 功率谱（自相关路径**不加窗**——加窗会钝化 NSDF 峰、降低周期检测清晰度，标准 MPM 不加窗）
3. IFFT 得自相关 → 归一化平方差 NSDF
5. 找 NSDF 正峰 → 取首个超过 k=0.9 门限的峰
6. f0 = sampleRate / lag
7. 抛物线插值 lag → 亚采样精度（<1 cent 的来源）
8. 置信度 = 峰的 NSDF 值 (0~1)

FFT：迭代式 radix-2 Cooley-Tukey，纯 Dart ~80 行，Float32List 原地运算。

### 抗八度错误（三层防御）
1. k 门限 0.9：倍频处 NSDF 峰通常更弱
2. 子谐波复查：若检测 lag 的 2×lag 处 NSDF ≥ 0.85 且差距 < 0.1，取更长 lag（基频优先）
3. 吉他先验范围：调弦模式下 65–350Hz（下限覆盖 Drop D 等模式的 D2 73.42Hz），chromatic 放宽到 60–1300Hz，范围外丢弃

### 平滑策略
| 环节 | 方法 | 参数 |
|------|------|------|
| 频率抖动 | 中值滤波 | 3 帧 |
| 指针 | 指数平滑 | α = 0.35 |
| 音名显示 | 稳定计数 | 同一音名连续 2 帧才切换 |
| 已调准 | 门限 | \|cents\| < 5 持续 3 帧 → 绿色 + 震动 |

### 置信度门控
confidence < 0.85 直接丢弃，UI 显示 "Listening..." 呼吸动画。

## 5. UI 与交互

主界面单屏，Glanceable 原则，深色主题，锁竖屏，零弹窗零广告：

```
┌─────────────────────────────┐
│  Standard ▾          🎵 A4=440 │  ← 模式切换 + A4 校准(长按滑块 430–450Hz)
│         ┌─────────┐         │
│         │    E    │         │  ← 大字号音名 (~72pt)
│      82.4 Hz  ▓ -3¢         │  ← 频率读数 + cents
│    ╭───────────────────╮    │
│    │        ◉ ▼        │    │  ← 弧形仪表 -50¢~+50¢, 红→绿色带
│   [E] [A] [D] [G] [B] [e]   │  ← 六弦条, 自动高亮检测弦; 点击播放参考音
│   ● Listening...            │  ← 状态栏 (listening/锁定/已调准)
└─────────────────────────────┘
```

交互：
- 自动识别弦（粘滞锁定）；chromatic 模式不锁定
- 参考音：真实吉他采样（非正弦波），再点停止，播完 2s 自动停
- 调准：|cents| < 5 → 仪表变绿 + `HapticFeedback.mediumImpact`
- 模式：BottomSheet 列出 Standard / Drop D / Open D / Open G / DADGAD / Chromatic，选择即生效并记住
- A4 长按校准 430–450Hz，默认 440

## 6. 错误处理

| 场景 | 处理 |
|------|------|
| 麦克风权限拒绝 | 整屏说明 + `openAppSettings()`，不重复弹权限框 |
| 安静/置信度低 | 指针保持原位，"Listening..." 呼吸动画 |
| 退到后台 | 停麦克风流（省电），回前台恢复 |
| 音频中断（来电） | 暂停分析，中断结束恢复 |
| iPhone 静音键 | 参考音走 playback 类别；麦克风输入不受影响 |

## 7. 调弦模式定义

| 模式 | 六弦频率 (Hz, A4=440) |
|------|----------------------|
| Standard | E2 82.41, A2 110.00, D3 146.83, G3 196.00, B3 246.94, E4 329.63 |
| Drop D | D2 73.42, A2 110.00, D3 146.83, G3 196.00, B3 246.94, E4 329.63 |
| Open D | D2 73.42, A2 110.00, D3 146.83, F#3 185.00, A3 220.00, D4 293.66 |
| Open G | D2 73.42, G2 98.00, D3 146.83, G3 196.00, B3 246.94, D4 293.66 |
| DADGAD | D2 73.42, A2 110.00, D3 146.83, G3 196.00, A3 220.00, D4 293.66 |
| Chromatic | 无弦锁定, 全音域 60–1300Hz |

频率按 A4 可调（430–450）动态换算：`f = f_base × (A4 / 440)^(n/12 距离)`。

## 8. 项目结构

```
lib/
├── audio/    MicStream (record 封装) + RingBuffer     ~150 行
├── dsp/      FFT + PitchDetector(MPM) + NoteMapper    ~400 行  ← 核心
├── tuner/    TunerController + TuningState + TuningModes ~200 行
└── ui/       TunerScreen + NeedlePainter + ModeSheet   ~300 行
```

模块边界：`dsp/` 不依赖 Flutter，纯 Dart 可单测；`tuner/` 编排并持有
ValueNotifier；`ui/` 只读 Notifier 渲染 + 发用户事件给 controller。

## 9. 测试策略

- **DSP 单元测试**（核心资产）：合成正弦波注入——六根标准弦精确频率
  ±0.5 cent 内检出；2 次谐波强于基频的信号验证抗八度错误；白噪声测置信度门控
- **NoteMapper 单元测试**：频率→音名→cents 全覆盖
- **UI 冒烟测试**: 模式切换、弦条点击、调准变色
- **真机验收**: 真吉他调一轮（最终标准）

## 10. 里程碑

1. **M1 DSP 核心**: FFT + MPM + NoteMapper + 合成信号单测全绿（纯 Dart，无 UI）
2. **M2 实时链路**: MicStream + RingBuffer + TunerController 串起，控制台打印检测结果
3. **M3 UI**: 主界面 + 指针仪表 + 弦条 + 模式切换 + 参考音
4. **M4 打磨**: 粘滞锁定、平滑参数调优、后台/中断处理、触觉反馈
5. **M5 真机验收**: Android/iOS 真机各调一轮吉他

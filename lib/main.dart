import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:math' as math;

import 'audio/mic_stream.dart';
import 'theme/kithara_theme.dart';
import 'dsp/onset_gate.dart';
import 'dsp/pitch_detector.dart';
import 'tuner/tuner_controller.dart';
import 'tuner/tuner_settings.dart';
import 'tuner/tuning_modes.dart';
import 'ui/platform_services.dart';
import 'ui/tuner_screen.dart';

void main() => runApp(const KitharaApp());

class KitharaApp extends StatefulWidget {
  const KitharaApp({super.key});

  @override
  State<KitharaApp> createState() => _KitharaAppState();
}

class _KitharaAppState extends State<KitharaApp> {
  /// 'system' | 'light' | 'dark'（循环切换：dark → light → system → dark）
  String _themeMode = 'system';
  bool _noisyMode = false;
  bool _settingsRestored = false;

  bool get _effectiveDark =>
      _themeMode == 'system'
          ? WidgetsBinding
              .instance.platformDispatcher.platformBrightness ==
              Brightness.dark
          : _themeMode == 'dark';

  @override
  void initState() {
    super.initState();
    TunerSettings.load().then((s) {
      // 用户若在恢复完成前已切换，恢复值不覆盖用户选择（竞态防护）
      if (mounted && !_settingsRestored) {
        setState(() {
          _themeMode = s.themeMode;
          _noisyMode = s.noisyMode;
        });
      }
    });
  }

  void _handleThemeModeChanged(String mode) {
    _settingsRestored = true;
    setState(() => _themeMode = mode);
    // 主题持久化（含 mode/a4 合并写入）
    _saveSettings(themeMode: mode);
  }

  final _homeKey = GlobalKey<_TunerHomeState>();

  /// 统一保存入口：mode/a4 + 主题一起落盘（桥与主题切换共用）
  void _saveSettings({String? modeId, double? a4, String? themeMode}) {
    TunerSettings().save(
      modeId ?? _homeKey.currentState?.bridge.lastSavedModeId ?? 'standard',
      a4 ?? _homeKey.currentState?.bridge.lastSavedA4 ?? 440.0,
      isDark: _effectiveDark,
      themeMode: themeMode ?? _themeMode,
      noisyMode: _noisyMode,
    );
  }

  @override
  Widget build(BuildContext context) {
    // system 模式：MaterialApp theme 也按平台亮度解析（Material 组件/弹窗跟随）
    final platDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
    final theme = switch (_themeMode) {
      'light' => KitharaTheme.light,
      'dark' => KitharaTheme.dark,
      _ => (platDark ? KitharaTheme.dark : KitharaTheme.light),
    };
    return MaterialApp(
      title: 'Kithara',
      theme: theme.toThemeData(),
      home: _TunerHome(
        key: _homeKey,
        theme: theme,
        themeMode: _themeMode,
        noisyMode: _noisyMode,
        onThemeModeChanged: _handleThemeModeChanged,
        onNoisyModeChanged: (v) {
          setState(() => _noisyMode = v);
          _saveSettings();
        },
        settingsSaver: (modeId, a4) => _saveSettings(modeId: modeId, a4: a4),
      ),
    );
  }
}

/// 装配根：设置加载 → controller → 管线（Ticker 驱动）→ 屏幕。
/// 主题状态在这里持有（切换按钮 → setState → 全应用生效）。
class _TunerHome extends StatefulWidget {
  const _TunerHome({
    super.key,
    this.theme,
    this.themeMode,
    this.noisyMode,
    this.onThemeModeChanged,
    this.onNoisyModeChanged,
    required this.settingsSaver,
  });

  final KitharaTheme? theme;
  final String? themeMode;
  final bool? noisyMode;
  final ValueChanged<String>? onThemeModeChanged;
  final ValueChanged<bool>? onNoisyModeChanged;
  final void Function(String modeId, double a4) settingsSaver;

  @override
  State<_TunerHome> createState() => _TunerHomeState();
}

class _TunerHomeState extends State<_TunerHome> {
  final TunerController _controller = TunerController();
  final MicStream _mic = MicStream();
  late final TunerPipelineBridge _bridge;
  Ticker? _ticker;

  /// 供 App 层读取最近保存的模式/A4（主题持久化合并写入用）
  TunerPipelineBridge get bridge => _bridge;

  @override
  void initState() {
    super.initState();
    _bridge = TunerPipelineBridge(
      controller: _controller,
      mic: _mic,
      // App 层统一保存（mode/a4 + 当前主题一起落盘，不互相覆盖）
      onSave: widget.settingsSaver,
      // 嘈杂环境调音接线：桥在 tick() 检测变更即切换检测器门限 + onset 门
      noisyMode: widget.noisyMode ?? false,
    );
    _restoreSettings();
    _ticker = Ticker((_) => _bridge.tick());
    _ticker!.start();
  }

  @override
  void didUpdateWidget(covariant _TunerHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    // App 层开关（或恢复）后下行同步: 桥在下次 tick 检测到变更即切换
    if (widget.noisyMode != oldWidget.noisyMode) {
      _bridge.noisyMode = widget.noisyMode ?? false;
    }
  }

  Future<void> _restoreSettings() async {
    final s = await TunerSettings.load();
    _controller.setMode(TuningModes.byId(s.modeId));
    _controller.setA4(s.a4);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _mic.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // themeMode='system' → TunerScreen 内部按平台亮度实时解析有效主题
    // theme 字段作 system 模式下的缺省（被 system 解析覆盖）
    return TunerScreen(
      controller: _controller,
      mic: _mic,
      micPermission: MicPermissionImpl(_mic),
      haptics: HapticsImpl(),
      theme: widget.theme ?? KitharaTheme.dark,
      themeMode: widget.themeMode ?? 'dark',
      noisyMode: widget.noisyMode ?? false,
      onNoisyModeChanged: widget.onNoisyModeChanged,
      onThemeToggle: () {
        // 三态循环: dark → light → system → dark
        final cur = widget.themeMode ?? 'dark';
        final next = switch (cur) {
          'dark' => 'light',
          'light' => 'system',
          _ => 'dark',
        };
        widget.onThemeModeChanged?.call(next);
      },
    );
  }
}

/// 把 MicStream 的 RingBuffer 与 controller 连成 tick 管线，并在模式/A4
/// 变化时持久化（spec §9：设置变更即存）。
/// 注意：MicStream 内部有自己的 RingBuffer；这里桥接用它暴露的缓冲。
class TunerPipelineBridge {
  TunerPipelineBridge({
    required this.controller,
    required this.mic,
    required this.onSave,
    this.noisyMode = false,
  });

  final TunerController controller;
  final MicStream mic;
  final void Function(String modeId, double a4) onSave;

  /// 嘈杂环境调音（2026-10 取代降噪三档）：
  /// 仿真结论（真实 Martin 录音 + 风扇/白噪声）：
  /// - 拨弦瞬间帧置信中位 1.26+（0dB 风扇），0.85 门拦不住它们——
  ///   真机"静默"根因是控制器凑不齐 3 帧一致 + 带内噪声摊薄频段占比。
  /// - 解药 = 检测器双门限放宽（conf 0.70 / band 0.06）+ OnsetGate
  ///   时间门（1.5x RMS 跳升开 400ms 窗，窗外帧不进控制器）+
  ///   唤醒帧数 3→2。0dB 风扇下每次拨弦命中率 49/20、精度 28¢。
  /// - 平时模式行为与旧"标准档"一致（rmsGate 0.008, conf 0.85）。
  static const _rmsGatePlain = 0.008;

  bool noisyMode;
  PitchDetector _detector = PitchDetector(rmsGate: _rmsGatePlain);
  final OnsetGate _onsetGate = OnsetGate();
  TuningMode? _lastMode;
  double? _lastA4;
  bool _lastNoisy = false;

  // 检测节流 10Hz: 人对指针方向变化的反应 ~200ms, 拧弦动作 0.5-2s,
  // 10Hz 刷新绰绰有余; DSP(CPU/电量)开销直降 2/3
  // （嘈杂模式下 OnsetGate 窗口粒度需要更密的帧——节流仍是 100ms，
  //   EMA/窗口以 10Hz 节奏运转，400ms 窗 = 4 帧，仿真同参数。）
  static const _detectInterval = Duration(milliseconds: 100);
  DateTime _lastDetect = DateTime.now().subtract(_detectInterval);

  String get lastSavedModeId => _lastMode?.id ?? 'standard';
  double get lastSavedA4 => _lastA4 ?? 440.0;

  void tick() {
    // 检测节流: Ticker 60fps 进来, 每 100ms 才真正检测一次
    final now = DateTime.now();
    if (now.difference(_lastDetect) < _detectInterval) return;
    _lastDetect = now;
    // 设置变更检测（含首次）：模式/嘈杂模式变更 → 重建检测器 + 重置 onset 门
    final s = controller.state;
    if (noisyMode != _lastNoisy) {
      _lastNoisy = noisyMode;
      _detector = _buildDetector(s.mode);
      _onsetGate.reset();
      // 嘈杂模式：唤醒 3→2 帧；信号触发门限 0.85→0.75（检测器已放宽到
      // 0.70, 不联动这里会出现"检测器放行、控制器拒收"的缺口——真机
      // 表现即"开不开启差别不大"）
      controller.wakeFrames = noisyMode ? 2 : 3;
      controller.captureConfidence = 0.85;
      controller.confOn = noisyMode ? 0.75 : 0.85;
    }
    if (_lastMode == null ||
        s.mode.id != _lastMode!.id ||
        _lastA4 == null ||
        s.a4 != _lastA4) {
      final modeChanged = _lastMode != null && s.mode.id != _lastMode!.id;
      _lastMode = s.mode;
      _lastA4 = s.a4;
      if (modeChanged) {
        _detector = _buildDetector(s.mode);
        _onsetGate.reset();
      }
      onSave(s.mode.id, s.a4);
    }
    final window = mic.ringBuffer.readWindow(_detector.window);
    if (window == null) return;
    // 前置滤波 + RMS（滤波后计量，与检测器第 0 步同一口径）。
    if (noisyMode) {
      final rms = _filteredRms(window);
      // 嘈杂模式双通道：检测器先跑（门限已放宽），再决定放行——
      //   通道1 RMS 跳升（onset）：琴明显比噪声响时有效
      //   通道2 置信旁路：近场风扇下琴噪同响（真机诊断 RMS 0.087 <
      //          EMA 0.096，跳升不存在），改信周期性——琴 NSDF>1.0
      //          立即放行，0.70-1.0 需连续 2 帧音高一致（风扇伪周期
      //          不会稳定重复）
      final pitch = _detector.detect(window);
      final conf = _detector.lastConfidence;
      var gateAccepted = _onsetGate.accept(rms, now);
      var channel = 'rms';
      if (!gateAccepted && pitch != null) {
        final cents = 1200.0 * math.log(pitch / 440.0) / math.ln2;
        gateAccepted = _onsetGate.acceptByConfidence(conf, cents, now);
        channel = 'conf';
      }
      controller.diagnostics =
          'RMS ${rms.toStringAsFixed(3)} · EMA ${_onsetGate.emaValue?.toStringAsFixed(3) ?? "-"} · conf ${conf.toStringAsFixed(2)} · ${gateAccepted ? "放行($channel)" : "拒"}';
      if (!gateAccepted) {
        controller.onPitch(null, 0.0);
        return;
      }
      controller.onPitch(pitch, conf);
      return;
    }
    controller.onPitch(_detector.detect(window), _detector.lastConfidence);
  }

  PitchDetector _buildDetector(TuningMode mode) => PitchDetector(
        minFreq: mode.detectorMinFreq,
        maxFreq: mode.detectorMaxFreq,
        rmsGate: noisyMode ? 0.0 : _rmsGatePlain,
        confidenceGate: noisyMode ? 0.70 : 0.85,
        bandRatioGate: noisyMode ? 0.06 : 0.10,
      );

  /// 与 PitchDetector.detect 第 0 步相同的去直流 + 两级低通后 RMS。
  /// （复制 8 行数学以避免检测器暴露中间态；若滤波参数改动需同步。）
  static double _filteredRms(Float32List frame) {
    const lpCutoffHz = 1800.0;
    const sampleRate = 44100.0;
    final alpha = 1.0 - math.exp(-2.0 * math.pi * lpCutoffHz / sampleRate);
    var mean = 0.0;
    for (var i = 0; i < frame.length; i++) {
      mean += frame[i];
    }
    mean /= frame.length;
    var lp1 = 0.0, lp2 = 0.0, sumSq = 0.0;
    for (var i = 0; i < frame.length; i++) {
      final dc = frame[i] - mean;
      lp1 += alpha * (dc - lp1);
      lp2 += alpha * (lp1 - lp2);
      sumSq += lp2 * lp2;
    }
    return math.sqrt(sumSq / frame.length);
  }
}

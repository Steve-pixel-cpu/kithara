import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'audio/mic_stream.dart';
import 'theme/kithara_theme.dart';
import 'dsp/pitch_detector.dart';
import 'tuner/tuner_controller.dart';
import 'tuner/tuner_settings.dart';
import 'tuner/tuning_modes.dart';
import 'ui/platform_services.dart';
import 'ui/tuner_screen.dart';

void main() => runApp(const KitharaApp());

class KitharaApp extends StatelessWidget {
  const KitharaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kithara',
      theme: KitharaTheme.dark.toThemeData(),
      home: const _TunerHome(),
    );
  }
}

/// 装配根：设置加载 → controller → 管线（Ticker 驱动）→ 屏幕。
class _TunerHome extends StatefulWidget {
  const _TunerHome();

  @override
  State<_TunerHome> createState() => _TunerHomeState();
}

class _TunerHomeState extends State<_TunerHome> {
  final TunerController _controller = TunerController();
  final MicStream _mic = MicStream();
  late final TunerPipelineBridge _bridge;
  Ticker? _ticker;

  @override
  void initState() {
    super.initState();
    _bridge = TunerPipelineBridge(
      controller: _controller,
      mic: _mic,
      onSave: (modeId, a4) => TunerSettings().save(modeId, a4),
    );
    _restoreSettings();
    _ticker = Ticker((_) => _bridge.tick());
    _ticker!.start();
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
    return TunerScreen(
      controller: _controller,
      mic: _mic,
      micPermission: MicPermissionImpl(_mic),
      haptics: HapticsImpl(),
      theme: KitharaTheme.dark,
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
  });

  final TunerController controller;
  final MicStream mic;
  final void Function(String modeId, double a4) onSave;

  PitchDetector _detector = PitchDetector();
  TuningMode? _lastMode;
  double _lastA4 = 0;

  void tick() {
    // 设置变更检测（含首次），变更即持久化；
    // 模式切换时按模式声明重建检测器（尤克里里等需要不同检测范围）
    final s = controller.state;
    if (_lastMode == null || s.mode.id != _lastMode!.id || s.a4 != _lastA4) {
      final modeChanged = _lastMode != null && s.mode.id != _lastMode!.id;
      _lastMode = s.mode;
      _lastA4 = s.a4;
      if (modeChanged) {
        _detector = PitchDetector(
          minFreq: s.mode.detectorMinFreq,
          maxFreq: s.mode.detectorMaxFreq,
        );
      }
      onSave(s.mode.id, s.a4);
    }
    final window = mic.ringBuffer.readWindow(_detector.window);
    if (window == null) return;
    controller.onPitch(_detector.detect(window), _detector.lastConfidence);
  }
}

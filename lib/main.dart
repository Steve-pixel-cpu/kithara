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

class KitharaApp extends StatefulWidget {
  const KitharaApp({super.key});

  @override
  State<KitharaApp> createState() => _KitharaAppState();
}

class _KitharaAppState extends State<KitharaApp> {
  /// 'system' | 'light' | 'dark'（循环切换：dark → light → system → dark）
  String _themeMode = 'system';
  bool _settingsRestored = false;

  @override
  void initState() {
    super.initState();
    TunerSettings.load().then((s) {
      // 用户若在恢复完成前已切换，恢复值不覆盖用户选择（竞态防护）
      if (mounted && !_settingsRestored) {
        setState(() => _themeMode = s.themeMode);
      }
    });
  }

  void _handleThemeModeChanged(String mode) {
    _settingsRestored = true;
    setState(() => _themeMode = mode);
    // 同步 isDark 兼容字段 + 持久化 themeMode
    final platDark = WidgetsBinding
            .instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    final effDark = mode == 'system'
        ? platDark
        : mode == 'dark';
    TunerSettings().save(
      _homeKey.currentState?.bridge.lastSavedModeId ?? 'standard',
      _homeKey.currentState?.bridge.lastSavedA4 ?? 440.0,
      isDark: effDark,
      themeMode: mode,
    );
  }

  final _homeKey = GlobalKey<_TunerHomeState>();

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
        onThemeModeChanged: _handleThemeModeChanged,
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
    this.onThemeModeChanged,
  });

  final KitharaTheme? theme;
  final String? themeMode;
  final ValueChanged<String>? onThemeModeChanged;

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
    // themeMode='system' → TunerScreen 内部按平台亮度实时解析有效主题
    // theme 字段作 system 模式下的缺省（被 system 解析覆盖）
    return TunerScreen(
      controller: _controller,
      mic: _mic,
      micPermission: MicPermissionImpl(_mic),
      haptics: HapticsImpl(),
      theme: widget.theme ?? KitharaTheme.dark,
      themeMode: widget.themeMode ?? 'dark',
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
  });

  final TunerController controller;
  final MicStream mic;
  final void Function(String modeId, double a4) onSave;

  PitchDetector _detector = PitchDetector();
  TuningMode? _lastMode;
  double _lastA4 = 0;

  String get lastSavedModeId => _lastMode?.id ?? 'standard';
  double get lastSavedA4 => _lastA4 == 0 ? 440.0 : _lastA4;

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


import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../audio/mic_stream.dart';
import '../theme/kithara_theme.dart';
import '../tuner/tuner_controller.dart';
import '../tuner/tuning_modes.dart';
import 'glow_ring.dart';
import 'platform_services.dart';

/// 调音器主界面：仪表指针 + 音名大字 + 弦条 + 模式/参考音控件。
/// 生命周期：进入前台自动 start 麦克风；退后台 stop；权限拒绝显示引导页。
class TunerScreen extends StatefulWidget {
  const TunerScreen({
    super.key,
    required this.controller,
    required this.mic,
    this.micPermission,
    this.haptics,
    this.theme = KitharaTheme.dark,
    this.themeMode = 'dark',
    this.noiseGate = 'medium',
    this.onThemeToggle,
    this.onNoiseGateChanged,
    this.onSelectString,
  });

  final TunerController controller;

  /// 由装配层传入的唯一 MicStream 实例。本组件只负责 start/stop 生命周期，
  /// 绝不自建实例（曾因自建第二实例导致管线读取空缓冲：拨弦无反应）。
  final MicStream mic;
  final MicPermission? micPermission;
  final Haptics? haptics;

  /// 设计令牌（aulos 设计语言，深浅两套）。
  final KitharaTheme theme;

  /// 主题模式：'system' 跟随系统亮度（覆盖 theme 字段），'light'/'dark' 固定。
  final String themeMode;

  /// 降噪档位 'low' | 'medium' | 'high'（显示 + 修改回调）
  final String noiseGate;
  final ValueChanged<String>? onNoiseGateChanged;

  /// 主题切换回调（主题所有权在装配层/外部）。
  final VoidCallback? onThemeToggle;

  /// 点击弦条手动指定目标弦（参数为该弦音名对应的半音索引）。
  final ValueChanged<int>? onSelectString;

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  bool _micStarted = false;
  bool _permissionDenied = false;
  bool _wasInTune = false;
  String? _stringHint; // 选弦提示（6弦），2s 自动消失
  Timer? _stringHintTimer;

  // 弹簧动画：把 15Hz 的检测跳变插值成 60fps 连续运动
  late final AnimationController _springCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  // 静止态呼吸：底环透明度 3s 周期缓变
  late final AnimationController _breathCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  );
  SpringSimulation _needleSim = SpringSimulation(
    const SpringDescription(mass: 1, stiffness: 120, damping: 14),
    0, 0, 0,
  );
  double _displayNeedle = 0.0;

  MicPermission get _perm =>
      widget.micPermission ?? MicPermissionImpl(widget.mic);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onState);
    _breathCtrl.repeat();
    _startup();
  }

  Future<void> _startup() async {
    final granted = await (widget.micPermission ?? _perm).ensure();
    if (!mounted) return;
    if (!granted) {
      setState(() => _permissionDenied = true);
      return;
    }
    await _startMic();
  }

  Future<void> _startMic() async {
    final ok = await widget.mic.start();
    if (!mounted) return;
    setState(() {
      _permissionDenied = !ok;
      _micStarted = ok;
    });
  }

  Future<void> _stopMic() async {
    if (!_micStarted) return;
    await widget.mic.stop();
    _micStarted = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startup();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _stopMic();
    }
  }

  @override
  void didUpdateWidget(covariant TunerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onState);
      widget.controller.addListener(_onState);
    }
  }

  @override
  void dispose() {
    _stringHintTimer?.cancel();
    _springCtrl.dispose();
    _breathCtrl.dispose();
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onState);
    _stopMic();
    super.dispose();
  }

  void _onState() {
    final s = widget.controller.state;
    // inTune 边沿 → 触觉脉冲 + 音名弹跳 + 弹簧目标切到 0（环心对准）
    if (s.inTune && !_wasInTune) {
      widget.haptics?.inTunePulse();
    }
    _wasInTune = s.inTune;
    // 新目标 = 靠近对准区时把视觉目标吸到 0，减少抖动；否则用真实 needle
    final target = s.inTune ? 0.0 : s.needle;
    _needleSim = SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 120, damping: 14),
      _displayNeedle, target, 0,
    );
    _springCtrl
      ..stop()
      ..animateWith(_needleSim);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.controller.state;
    // 'system' → 跟随平台亮度实时解析；'light'/'dark' 用传入 theme 的亮暗
    final KitharaTheme t;
    if (widget.themeMode == 'system') {
      final platformBright =
          MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.dark;
      t = platformBright == Brightness.light
          ? KitharaTheme.light
          : KitharaTheme.dark;
    } else {
      t = widget.theme;
    }
    final isChromatic = s.mode.semitones.isEmpty;

    if (_permissionDenied) {
      return Scaffold(
        backgroundColor: t.bg,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.mic_off, color: t.text3, size: 64),
              const SizedBox(height: 16),
              Text('需要麦克风权限',
                  style: TextStyle(color: t.text2, fontSize: 18)),
              const SizedBox(height: 24),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: t.surface2,
          foregroundColor: t.text,
          elevation: 0,
          onPressed: () {
            setState(() => _permissionDenied = false);
            _startup();
          },
          label: const Text('重试'),
          icon: const Icon(Icons.refresh),
        ),
      );
    }

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部：模式选择 + 参考音（surface-2 底 + 1px 边框, aulos 分层手法）
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: PopupMenuButton<TuningMode>(
                    color: t.popBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: t.border),
                    ),
                    onSelected: (m) {
                      widget.haptics?.selectionClick();
                      widget.controller.setMode(m);
                    },
                    constraints: const BoxConstraints(maxHeight: 420),
                    itemBuilder: (_) => [
                      for (final m in TuningModes.all)
                        PopupMenuItem(
                          value: m,
                          child: Text(m.label,
                              style: TextStyle(color: t.text)),
                        ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(s.mode.label,
                              style: TextStyle(
                                color: t.text2,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              )),
                          Icon(Icons.arrow_drop_down,
                              color: t.text3, size: 22),
                        ],
                      ),
                    ),
                  ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        key: const Key('settings_btn'),
                        onTap: () {
                          widget.haptics?.selectionClick();
                          _showSettingsDialog(context);
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(Icons.settings_outlined,
                              color: t.text3, size: 20),
                        ),
                      ),
                      InkWell(
                        key: const Key('theme_toggle'),
                        onTap: () {
                          widget.haptics?.selectionClick();
                          widget.onThemeToggle?.call();
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                          switch (widget.themeMode) {
                            'system' => Icons.brightness_auto_outlined,
                            'light' => Icons.dark_mode_outlined, // 当前浅色,点击切深色
                            _ => Icons.light_mode_outlined, // 当前深色,点击切浅色
                          },
                          color: t.text3,
                          size: 20,
                        ),
                        ),
                      ),
                      Flexible(
                        child: InkWell(
                          onTap: () {
                            widget.haptics?.selectionClick();
                            _showA4Dialog(context, s.a4);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Text(
                              'A4 ${s.a4.toStringAsFixed(1)}',
                              style: TextStyle(
                                color: t.text3,
                                fontSize: 16,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Spacer(flex: 2),
            // 发光环仪表：环心音名大字 + cents；弹簧插值 needle
            Center(
              child: AnimatedBuilder(
                animation: _springCtrl,
                builder: (context, _) {
                  _displayNeedle = _needleSim.x(
                      _springCtrl.value * 450 / 1000);
                  // 锁定时指针钉死正中：±5¢ 内的真实抖动不传给视觉
                  final display = s.inTune ? 0.0 : _displayNeedle;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      GlowRing(
                        needle: display,
                        locked: s.inTune,
                        near: s.hasSignal &&
                            !s.inTune &&
                            s.cents.abs() <= 30,
                        hasSignal: s.hasSignal,
                        theme: t,
                        size: 300,
                        breathPhase: _breathCtrl.value,
                      ),
                      // 选弦提示浮层（2s 自动消失）
                      if (_stringHint != null)
                        Positioned(
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: t.accentSoft,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: t.accent),
                            ),
                            child: Text(
                              _stringHint!,
                              style: TextStyle(
                                color: t.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      // 量程标注（弧两端 + 顶部）
                      Positioned(
                        left: 18,
                        bottom: 42,
                        child: Text('-50',
                            style: TextStyle(
                              color: t.text3,
                              fontSize: 11,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            )),
                      ),
                      Positioned(
                        right: 18,
                        bottom: 42,
                        child: Text('+50',
                            style: TextStyle(
                              color: t.text3,
                              fontSize: 11,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            )),
                      ),
                      // 环心音名：AnimatedSwitcher 淡入淡出治闪烁
                      // （置信度门限边缘抖动时，音名渐隐渐现而非瞬灭瞬现）
                      KeyedSubtree(
                        key: const Key('in_tune_indicator'),
                        child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: child,
                        ),
                        child: s.hasSignal
                            ? Text(
                                s.noteLabel,
                                key: ValueKey(s.noteLabel),
                                style: TextStyle(
                                  color: s.inTune
                                      ? t.ok
                                      : (s.cents.abs() <= 30
                                          ? t.warn
                                          : t.text),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 72,
                                  height: 1.0,
                                  letterSpacing: -2,
                                ),
                              )
                            : SizedBox(
                                key: const ValueKey('empty'),
                                width: 1,
                                height: 72,
                              ),
                      ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const Spacer(),
            // 品牌字标（环底部缺口处）
            Text(
              'K I T H A R A',
              style: const TextStyle(
                fontFamily: 'Montserrat',
                color: Color(0xFF85868F),
                fontSize: 11,
                letterSpacing: 6,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            // 状态引导语（替代生硬的"未检测到信号"）
            Text(
              _guidance(s),
              style: TextStyle(
                color: s.inTune
                    ? t.ok
                    : (s.hasSignal && s.cents.abs() <= 30
                        ? t.warn
                        : t.text3),
                fontSize: 15,
                letterSpacing: 0.3,
              ),
            ),
            const Spacer(),
            // 弦条
            if (!isChromatic)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final st in s.mode.strings)
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            widget.haptics?.selectionClick();
                            widget.controller.selectString(st.semitoneIndex);
                            widget.onSelectString?.call(st.semitoneIndex);
                            _showStringHint(st);
                          },
                          child: _StringBar(
                            key: Key('led_${st.name}'),
                            target: st,
                            t: t,
                            active: s.activeString?.semitoneIndex ==
                                st.semitoneIndex,
                            inTune: s.activeString?.semitoneIndex ==
                                    st.semitoneIndex &&
                                s.inTune,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 选弦提示浮层：显示「6弦」2 秒后淡出（初学者辅助）
  void _showStringHint(StringTarget target) {
    final s = widget.controller.state;
    final idx = s.mode.semitones.indexOf(target.semitoneIndex);
    if (idx < 0) return;
    final stringNo = s.mode.semitones.length - idx;
    setState(() => _stringHint = '$stringNo弦');
    _stringHintTimer?.cancel();
    _stringHintTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _stringHint = null);
    });
  }

  /// 状态引导语：告诉用户下一步做什么，替代"未检测到信号"。
  String _guidance(TunerState s) {
    // 大偏差（粘性锁下很松的弦）: 告诉用户还差多少, 指导拧紧
    if (s.hasSignal && s.activeString != null && s.cents < -50) {
      return '向 ${s.activeString!.name} 拧紧…（差 ${s.cents.abs().toStringAsFixed(0)}¢）';
    }
    if (s.mode.semitones.isEmpty) {
      // 半音阶：无目标弦
      if (!s.hasSignal) return '拨响任意弦开始调音';
      if (s.inTune) return '✓ ${s.noteLabel} 已调准';
      return s.cents > 15
          ? '偏低，向 ${s.noteLabel} 拧紧'
          : (s.cents < -15 ? '偏高，向 ${s.noteLabel} 拧松' : '微调…');
    }
    final target = s.activeString;
    if (!s.hasSignal) {
      return target == null ? '拨响任意弦开始调音' : '拨响 ${target.name} 弦';
    }
    if (s.inTune && target != null) return '✓ ${target.name} 已调准';
    if (target == null) return '音高偏离各弦，继续调整';
    return s.cents > 8
        ? '向 ${target.name} 拧紧…'
        : (s.cents < -8 ? '向 ${target.name} 拧松…' : '微调…');
  }

  String _gateLabel(String gate) => switch (gate) {
        'low' => '宽松（安静房间）',
        'high' => '严格（嘈杂环境）',
        _ => '标准（日常）',
      };

  /// 圆角下拉选择器：选项列表也是圆角容器+圆角高亮，风格与弹窗一致
  Future<String?> _showGatePicker(BuildContext ctx, KitharaTheme t) {
    return showModalBottomSheet<String>(
      context: ctx,
      backgroundColor: t.popBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 4),
                child: Text('降噪灵敏度',
                    style: TextStyle(color: t.text2, fontSize: 13)),
              ),
              for (final (label, val) in [
                ('宽松（安静房间）', 'low'),
                ('标准（日常）', 'medium'),
                ('严格（嘈杂环境）', 'high'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      widget.haptics?.selectionClick();
                      Navigator.pop(sheetCtx, val);
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: widget.noiseGate == val
                            ? t.accentSoft
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: widget.noiseGate == val
                              ? t.accent
                              : Colors.transparent,
                        ),
                      ),
                      child: Text(label,
                          style: TextStyle(
                            color: widget.noiseGate == val
                                ? t.text
                                : t.text2,
                            fontWeight: widget.noiseGate == val
                                ? FontWeight.w600
                                : FontWeight.w400,
                          )),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSettingsDialog(BuildContext context) {
    final t = widget.theme;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.popBg,
        title: Text('设置', style: TextStyle(color: t.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('降噪灵敏度', style: TextStyle(color: t.text2, fontSize: 14)),
            const SizedBox(height: 8),
            // 自绘下拉触发器（圆角容器，与弹窗风格统一）
            InkWell(
              key: const Key('noise_gate_dropdown'),
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                widget.haptics?.selectionClick();
                final picked = await _showGatePicker(ctx, t);
                if (picked != null && picked != widget.noiseGate) {
                  widget.onNoiseGateChanged?.call(picked);
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: t.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.borderStrong),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _gateLabel(widget.noiseGate),
                        style: TextStyle(color: t.text, fontSize: 15),
                      ),
                    ),
                    Icon(Icons.expand_more, color: t.text3, size: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              widget.haptics?.selectionClick();
              Navigator.pop(ctx);
            },
            child: Text('关闭', style: TextStyle(color: t.text2)),
          ),
        ],
      ),
    );
  }

  void _showA4Dialog(BuildContext context, double current) {
    final t = widget.theme;
    var value = current;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: t.popBg,
          title: Text('参考音 A4', style: TextStyle(color: t.text)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${value.toStringAsFixed(1)} Hz',
                  style: TextStyle(
                    color: t.text,
                    fontSize: 24,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: t.accent,
                  inactiveTrackColor: t.surface3,
                  thumbColor: t.text,
                  overlayColor: t.accentSoft,
                ),
                child: Slider(
                  value: value,
                  min: 430,
                  max: 450,
                  divisions: 20,
                  label: value.toStringAsFixed(1),
                  onChanged: (v) => setState(() => value = v),
                ),
              ),
            ],
          ),
          actions: [
            // 主操作放左（用户要求），取消弱化居右
            TextButton(
              onPressed: () {
                widget.haptics?.selectionClick();
                widget.controller.setA4(value);
                Navigator.pop(ctx);
              },
              child: Text('确定', style: TextStyle(color: t.accent)),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                widget.haptics?.selectionClick();
                Navigator.pop(ctx);
              },
              child: Text('取消', style: TextStyle(color: t.text2)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StringBar extends StatelessWidget {
  const _StringBar({
    super.key,
    required this.target,
    required this.t,
    required this.active,
    required this.inTune,
  });

  final StringTarget target;
  final KitharaTheme t;
  final bool active;
  final bool inTune;

  @override
  Widget build(BuildContext context) {
    // LED 胶囊：默认暗块，active 亮白描边，inTune 绿色常亮
    return Column(
      children: [
        Container(
          height: 10,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: inTune
                ? t.ok
                : (active ? t.text : t.surface3),
            borderRadius: BorderRadius.circular(5),
            boxShadow: inTune
                ? [BoxShadow(color: t.ok.withValues(alpha: 0.45), blurRadius: 10)]
                : (active
                    ? [BoxShadow(color: t.text.withValues(alpha: 0.25), blurRadius: 6)]
                    : null),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          target.name,
          style: TextStyle(
            color: inTune ? t.ok : (active ? t.text : t.text3),
            fontSize: 12,
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: active || inTune ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

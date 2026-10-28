
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
    this.onThemeToggle,
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

  /// 主题切换回调（主题所有权在装配层/外部）。
  final VoidCallback? onThemeToggle;

  /// 点击弦条手动指定目标弦（参数为该弦音名对应的半音索引）。
  final ValueChanged<int>? onSelectString;

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  bool _micStarted = false;
  bool _permissionDenied = false;
  bool _wasInTune = false;

  // 弹簧动画：把 15Hz 的检测跳变插值成 60fps 连续运动
  late final AnimationController _springCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
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
    _springCtrl.dispose();
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
    final t = widget.theme;
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
                    onSelected: (m) => widget.controller.setMode(m),
                    itemBuilder: (_) => [
                      for (final m in TuningModes.all)
                        PopupMenuItem(
                          value: m,
                          child: Text(m.label,
                              style: TextStyle(color: t.text)),
                        ),
                    ],
                  ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        key: const Key('theme_toggle'),
                        onTap: widget.onThemeToggle,
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            t.brightness == Brightness.dark
                                ? Icons.light_mode_outlined
                                : Icons.dark_mode_outlined,
                            color: t.text3,
                            size: 20,
                          ),
                        ),
                      ),
                      Flexible(
                        child: InkWell(
                          onTap: () => _showA4Dialog(context, s.a4),
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
                      ),
                      if (s.hasSignal)
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 环心音名（无信号整体不渲染，环心留给指针轴点）
                            Text(
                              s.noteLabel,
                              key: const Key('in_tune_indicator'),
                              style: TextStyle(
                                color: s.inTune
                                    ? t.ok
                                    : (s.cents.abs() <= 30 ? t.warn : t.text),
                                fontWeight: FontWeight.w700,
                                fontSize: 64,
                                height: 1.0,
                                letterSpacing: -2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${s.cents >= 0 ? '+' : ''}${s.cents.toStringAsFixed(0)}¢',
                              style: TextStyle(
                                color: s.inTune
                                    ? t.ok
                                    : (s.cents.abs() <= 30
                                        ? t.warn
                                        : t.text2),
                                fontSize: 20,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  );
                },
              ),
            ),
            const Spacer(),
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
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            widget.controller.selectString(st.semitoneIndex);
                            widget.onSelectString?.call(st.semitoneIndex);
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

  /// 状态引导语：告诉用户下一步做什么，替代"未检测到信号"。
  String _guidance(TunerState s) {
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
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('取消', style: TextStyle(color: t.text2)),
            ),
            TextButton(
              onPressed: () {
                widget.controller.setA4(value);
                Navigator.pop(ctx);
              },
              child: Text('确定', style: TextStyle(color: t.accent)),
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

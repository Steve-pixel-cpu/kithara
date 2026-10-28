import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../audio/mic_stream.dart';
import '../theme/kithara_theme.dart';
import '../tuner/tuner_controller.dart';
import '../tuner/tuning_modes.dart';
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
  });

  final TunerController controller;

  /// 由装配层传入的唯一 MicStream 实例。本组件只负责 start/stop 生命周期，
  /// 绝不自建实例（曾因自建第二实例导致管线读取空缓冲：拨弦无反应）。
  final MicStream mic;
  final MicPermission? micPermission;
  final Haptics? haptics;

  /// 设计令牌（aulos 设计语言，深浅两套）。
  final KitharaTheme theme;

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen> with WidgetsBindingObserver {
  bool _micStarted = false;
  bool _permissionDenied = false;
  bool _wasInTune = false;

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
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onState);
    _stopMic();
    super.dispose();
  }

  void _onState() {
    // inTune 边沿 → 触觉脉冲一次
    final s = widget.controller.state;
    if (s.inTune && !_wasInTune) {
      widget.haptics?.inTunePulse();
    }
    _wasInTune = s.inTune;
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
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: t.surface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: t.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(s.mode.label,
                                style: TextStyle(color: t.text),
                                overflow: TextOverflow.ellipsis),
                          ),
                          Icon(Icons.arrow_drop_down, color: t.text2),
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
                  Flexible(
                    child: InkWell(
                    onTap: () => _showA4Dialog(context, s.a4),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: t.surface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: t.border),
                      ),
                      child: Text('A4 ${s.a4.toStringAsFixed(1)} Hz',
                          style: TextStyle(color: t.text2)),
                    ),
                  ),
                  ),
                ],
              ),
            ),
            const Spacer(flex: 2),
            // 音名大字 + inTune 指示
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  s.noteLabel,
                  style: TextStyle(
                    color: s.hasSignal ? t.text : t.text3,
                    fontWeight: FontWeight.w700,
                    fontSize: 72,
                    height: 1.0,
                  ),
                ),
                const SizedBox(width: 12),
                if (s.inTune)
                  KeyedSubtree(
                    key: const Key('in_tune_indicator'),
                    child: Icon(Icons.check_circle, color: t.ok, size: 40),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              s.hasSignal
                  ? '${s.cents >= 0 ? '+' : ''}${s.cents.toStringAsFixed(0)} ¢'
                  : '未检测到信号',
              style: TextStyle(
                // 色彩只表达状态（aulos 原则）: inTune=ok, 检测中=warn, 无信号=text3
                color: s.inTune
                    ? t.ok
                    : (s.hasSignal ? t.warn : t.text3),
                fontSize: 22,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const Spacer(),
            // 仪表
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                height: 140,
                child: CustomPaint(
                  painter: _NeedleGauge(
                      needle: s.needle, hasSignal: s.hasSignal, t: t),
                  size: Size.infinite,
                ),
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
                        child: _StringBar(
                          key: Key('string_bar_${st.name}'),
                          target: st,
                          t: t,
                          active: s.activeString?.semitoneIndex ==
                              st.semitoneIndex,
                          inTune: s.activeString?.semitoneIndex ==
                                  st.semitoneIndex &&
                              s.inTune,
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
    // aulos 手法: 默认 surface-2 融入背景, active 用 accent 描边+微亮底,
    // inTune 才给状态色 (ok-soft 底 + ok 描边)
    return Column(
      children: [
        Container(
          width: 40,
          height: 64,
          decoration: BoxDecoration(
            color: inTune
                ? t.okSoft
                : (active ? t.accentSoft : t.surface2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: inTune
                  ? t.ok
                  : (active ? t.accent : t.border),
              width: inTune || active ? 1.5 : 1,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          target.name,
          style: TextStyle(
            color: inTune ? t.ok : (active ? t.text : t.text3),
            fontSize: 12,
            fontWeight: active || inTune ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

/// 半圆仪表：刻度弧 + 指针。needle ∈ [-1,1]，0 居中，±50¢ 满偏。
/// 颜色即状态: 指针常态 accent 灰, 接近居中(|n|<0.1)变 ok 绿, 无信号 text3。
class _NeedleGauge extends CustomPainter {
  _NeedleGauge({required this.needle, required this.hasSignal, required this.t});

  final double needle;
  final bool hasSignal;
  final KitharaTheme t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.92);
    final radius = math.min(size.width / 2 - 8, size.height * 0.85);
    final sweepMax = math.pi * 0.75; // 可视扇形 ±135°

    // 刻度弧
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = t.surface3;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi + (math.pi - sweepMax) / 2,
      sweepMax,
      false,
      trackPaint,
    );
    // 中央刻度（对准区）
    final tickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = t.borderStrong;
    final midAngle = math.pi + (math.pi - sweepMax) / 2 + sweepMax / 2;
    canvas.drawLine(
      center,
      center +
          Offset(math.cos(midAngle), math.sin(midAngle)) *
              (radius - 14),
      tickPaint,
    );

    // 指针
    final n = needle.clamp(-1.0, 1.0);
    final angle = math.pi +
        (math.pi - sweepMax) / 2 +
        sweepMax * (0.5 + n * 0.5);
    final needlePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = hasSignal
          ? (n.abs() < 0.1 ? t.ok : t.accent)
          : t.text3;
    canvas.drawLine(
      center,
      center + Offset(math.cos(angle), math.sin(angle)) * (radius - 6),
      needlePaint,
    );
    canvas.drawCircle(center, 6, needlePaint);
  }

  @override
  bool shouldRepaint(_NeedleGauge oldDelegate) =>
      oldDelegate.needle != needle || oldDelegate.hasSignal != hasSignal;
}

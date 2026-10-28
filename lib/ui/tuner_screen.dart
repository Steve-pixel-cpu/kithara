import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../audio/mic_stream.dart';
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
  });

  final TunerController controller;

  /// 由装配层传入的唯一 MicStream 实例。本组件只负责 start/stop 生命周期，
  /// 绝不自建实例（曾因自建第二实例导致管线读取空缓冲：拨弦无反应）。
  final MicStream mic;
  final MicPermission? micPermission;
  final Haptics? haptics;

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
    final theme = Theme.of(context);
    final isChromatic = s.mode.semitones.isEmpty;

    if (_permissionDenied) {
      return Scaffold(
        backgroundColor: const Color(0xFF15171C),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.mic_off, color: Colors.white24, size: 64),
              SizedBox(height: 16),
              Text('需要麦克风权限',
                  style: TextStyle(color: Colors.white70, fontSize: 18)),
              SizedBox(height: 24),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
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
      backgroundColor: const Color(0xFF15171C),
      body: SafeArea(
        child: Column(
          children: [
            // 顶部：模式选择 + 参考音
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  PopupMenuButton<TuningMode>(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF23262E),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Text(s.mode.label,
                              style: const TextStyle(color: Colors.white)),
                          const Icon(Icons.arrow_drop_down,
                              color: Colors.white70),
                        ],
                      ),
                    ),
                    onSelected: (m) => widget.controller.setMode(m),
                    itemBuilder: (_) => [
                      for (final m in TuningModes.all)
                        PopupMenuItem(value: m, child: Text(m.label)),
                    ],
                  ),
                  InkWell(
                    onTap: () => _showA4Dialog(context, s.a4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF23262E),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('A4 ${s.a4.toStringAsFixed(1)} Hz',
                          style: const TextStyle(color: Colors.white70)),
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
                  style: theme.textTheme.displayLarge?.copyWith(
                    color: s.hasSignal ? Colors.white : Colors.white30,
                    fontWeight: FontWeight.bold,
                    fontSize: 72,
                  ),
                ),
                const SizedBox(width: 12),
                if (s.inTune)
                  const KeyedSubtree(
                    key: Key('in_tune_indicator'),
                    child: Icon(Icons.check_circle,
                        color: Color(0xFF33D17A), size: 40),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              s.hasSignal
                  ? '${s.cents >= 0 ? '+' : ''}${s.cents.toStringAsFixed(0)} ¢'
                  : '未检测到信号',
              style: TextStyle(
                color: s.inTune
                    ? const Color(0xFF33D17A)
                    : (s.hasSignal ? Colors.orange : Colors.white24),
                fontSize: 22,
              ),
            ),
            const Spacer(),
            // 仪表
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                height: 140,
                child: CustomPaint(
                  painter: _NeedleGauge(needle: s.needle, hasSignal: s.hasSignal),
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
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final st in s.mode.strings)
                      _StringBar(
                        key: Key('string_bar_${st.name}'),
                        target: st,
                        active: s.activeString?.semitoneIndex ==
                            st.semitoneIndex,
                        inTune: s.activeString?.semitoneIndex ==
                                st.semitoneIndex &&
                            s.inTune,
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
    var value = current;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: const Color(0xFF23262E),
          title: const Text('参考音 A4', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${value.toStringAsFixed(1)} Hz',
                  style: const TextStyle(color: Colors.white, fontSize: 24)),
              Slider(
                value: value,
                min: 430,
                max: 450,
                divisions: 20,
                label: value.toStringAsFixed(1),
                onChanged: (v) => setState(() => value = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                widget.controller.setA4(value);
                Navigator.pop(ctx);
              },
              child: const Text('确定'),
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
    required this.active,
    required this.inTune,
  });

  final StringTarget target;
  final bool active;
  final bool inTune;

  @override
  Widget build(BuildContext context) {
    final color = inTune
        ? const Color(0xFF33D17A)
        : (active ? Colors.orange : const Color(0xFF3A3E48));
    return Column(
      children: [
        Container(
          width: 40,
          height: 64,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 4),
        Text(target.name, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }
}

/// 半圆仪表：刻度弧 + 指针。needle ∈ [-1,1]，0 居中，±50¢ 满偏。
class _NeedleGauge extends CustomPainter {
  _NeedleGauge({required this.needle, required this.hasSignal});

  final double needle;
  final bool hasSignal;

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
      ..color = const Color(0xFF3A3E48);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi + (math.pi - sweepMax) / 2,
      sweepMax,
      false,
      trackPaint,
    );
    // 中央刻度
    final tickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFF5A5F6B);
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
          ? (n.abs() < 0.1
              ? const Color(0xFF33D17A)
              : Colors.orange)
          : Colors.white24;
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

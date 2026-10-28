import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tuner/tuner_controller.dart';
import '../tuner/tuning_modes.dart';

/// 调音器主界面：仪表指针 + 音名大字 + 弦条 + 模式/参考音控件。
class TunerScreen extends StatefulWidget {
  const TunerScreen({super.key, required this.controller});

  final TunerController controller;

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onState);
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
    widget.controller.removeListener(_onState);
    super.dispose();
  }

  void _onState() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final s = widget.controller.state;
    final theme = Theme.of(context);
    final isChromatic = s.mode.semitones.isEmpty;

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

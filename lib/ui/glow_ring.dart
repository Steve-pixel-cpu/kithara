import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/kithara_theme.dart';

/// 发光环仪表：270° 圆弧，needle ∈ [-1,1]。
/// 环心指针从中心指向弧上光点位置，颜色即状态：
/// 锁定=ok 绿（实心锐利）、接近(±30¢ 内)=warn 黄、常规=text 白、无信号=灰。
class GlowRing extends StatelessWidget {
  const GlowRing({
    super.key,
    required this.needle,
    required this.locked,
    required this.near,
    required this.hasSignal,
    required this.theme,
    this.size = 300,
  });

  final double needle;
  final bool locked;
  final bool near;
  final bool hasSignal;
  final KitharaTheme theme;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GlowRingPainter(
          needle: needle,
          locked: locked,
          near: near,
          hasSignal: hasSignal,
          t: theme,
        ),
      ),
    );
  }
}

class _GlowRingPainter extends CustomPainter {
  _GlowRingPainter({
    required this.needle,
    required this.locked,
    required this.near,
    required this.hasSignal,
    required this.t,
  });

  final double needle;
  final bool locked;
  final bool near;
  final bool hasSignal;
  final KitharaTheme t;

  // 270° 弧，缺口朝下
  static const _sweep = math.pi * 1.5;
  static const _startAngle = math.pi * 0.75;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 14;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // 状态色：锁定绿 / 接近黄 / 常规白 / 无信号灰
    final stateColor =
        !hasSignal ? t.text3 : (locked ? t.ok : (near ? t.warn : t.text));

    // 底环
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = t.surface3;
    canvas.drawArc(rect, _startAngle, _sweep, false, track);

    // 对准区（±5¢）：锁定时实心绿（锐利，无 blur）
    final zoneStart = _startAngle + _sweep * 0.45;
    final zoneSpan = _sweep * 0.1;
    final zonePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.butt
      ..color = locked ? t.ok : t.borderStrong;
    canvas.drawArc(rect, zoneStart, zoneSpan, false, zonePaint);

    if (!hasSignal) return;

    final n = needle.clamp(-1.0, 1.0);
    final headAngle = _startAngle + _sweep * (0.5 + n * 0.5);

    // 光点辉光：常规态强一点，接近/锁定态收敛
    final glowAlpha = locked ? 0.30 : (near ? 0.35 : 0.5);
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..color = stateColor.withValues(alpha: glowAlpha)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
    canvas.drawArc(rect, headAngle - 0.02, 0.04, false, glow);

    // 光点核心（实心锐利）
    final core = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = stateColor;
    canvas.drawArc(rect, headAngle - 0.012, 0.024, false, core);

    // 环心指针：从中心 42% 半径指向光点（留出环心文字空间）
    final innerR = radius * 0.42;
    final tail =
        center + Offset(math.cos(headAngle), math.sin(headAngle)) * innerR;
    final head =
        center + Offset(math.cos(headAngle), math.sin(headAngle)) * (radius - 12);
    final needlePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = stateColor;
    canvas.drawLine(tail, head, needlePaint);
    canvas.drawCircle(center, 5, needlePaint);
  }

  @override
  bool shouldRepaint(_GlowRingPainter old) =>
      old.needle != needle ||
      old.locked != locked ||
      old.near != near ||
      old.hasSignal != hasSignal;
}

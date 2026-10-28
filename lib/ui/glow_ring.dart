import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/kithara_theme.dart';

/// 发光环仪表：270° 圆弧，needle ∈ [-1,1] 映射弧上光点位置，
/// ±5¢ 对准区内整环泛 ok 绿辉光。
/// 光点 = 白色核心 + MaskFilter.blur 辉光层 + 短拖尾。
class GlowRing extends StatelessWidget {
  const GlowRing({
    super.key,
    required this.needle,
    required this.locked,
    required this.hasSignal,
    required this.theme,
    this.size = 280,
  });

  final double needle;
  final bool locked;
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
    required this.hasSignal,
    required this.t,
  });

  final double needle;
  final bool locked;
  final bool hasSignal;
  final KitharaTheme t;

  // 270° 弧，缺口朝下（-90° 起点为顶部，顺时针 270°）
  static const _sweep = math.pi * 1.5;
  static const _startAngle = math.pi * 0.75; // 左下缺口起点

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 14;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // 底环：暗轨
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = t.surface3;
    canvas.drawArc(rect, _startAngle, _sweep, false, track);

    // 对准区（±5¢ = needle ±0.1）：锁定时泛绿辉光扇区
    final inZoneSpan = 0.1 * _sweep; // ±0.1 (±5¢/±50¢)
    final zoneStart = _startAngle + _sweep * (0.5 - 0.05);
    if (locked) {
      final zoneGlow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..color = t.ok
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawArc(rect, zoneStart, inZoneSpan, false, zoneGlow);
    } else {
      final zone = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.butt
        ..color = t.borderStrong;
      canvas.drawArc(rect, zoneStart, inZoneSpan, false, zone);
    }

    if (hasSignal) {
      final n = needle.clamp(-1.0, 1.0);
      final headAngle = _startAngle + _sweep * (0.5 + n * 0.5);
      final color = locked ? t.ok : t.text;

      // 拖尾：光点后方 4 段渐弱短弧
      for (var i = 1; i <= 4; i++) {
        final tailAlpha = (0.30 - i * 0.06).clamp(0.0, 1.0);
        final tailPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (10 - i).toDouble()
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: locked ? tailAlpha : tailAlpha * 0.6)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 + i.toDouble());
        final span = 0.035 * _sweep;
        final from = headAngle - span * i;
        canvas.drawArc(rect, from, span, false, tailPaint);
      }

      // 光点头部：核心 + 双层辉光
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawArc(rect, headAngle - 0.02, 0.04, false, glow);

      final core = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawArc(rect, headAngle - 0.012, 0.024, false, core);
    }
  }

  @override
  bool shouldRepaint(_GlowRingPainter old) =>
      old.needle != needle ||
      old.locked != locked ||
      old.hasSignal != hasSignal;
}

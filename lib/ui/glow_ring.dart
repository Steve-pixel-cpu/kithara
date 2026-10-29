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
    this.showTicks = true,
    this.ticksInside = true,
    this.breathPhase = 0,
  });

  final double needle;
  final bool locked;
  final bool near;
  final bool hasSignal;
  final KitharaTheme theme;
  final double size;

  /// 表盘刻度（仪器感装饰）
  final bool showTicks;

  /// 刻度放弧内侧（默认，避开外圈视觉冲突）
  final bool ticksInside;

  /// 静止态呼吸相位 0..1（一个呼吸周期内的进度），仅影响底环透明度
  final double breathPhase;

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
          showTicks: showTicks,
          ticksInside: ticksInside,
          breathPhase: breathPhase,
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
    required this.showTicks,
    required this.ticksInside,
    required this.breathPhase,
  });

  final double needle;
  final bool locked;
  final bool near;
  final bool hasSignal;
  final KitharaTheme t;
  final bool showTicks;
  final bool ticksInside;
  final double breathPhase;

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

    // 底环（静止态呼吸：透明度 0.55~1.0 缓变）
    final breath = hasSignal
        ? 1.0
        : 0.55 + 0.45 * (0.5 + 0.5 * math.sin(breathPhase * 2 * math.pi));
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = t.surface3.withValues(alpha: breath);
    canvas.drawArc(rect, _startAngle, _sweep, false, track);

    // 表盘刻度：11 根沿弧分布（每 27°），主刻度（0/±50）长且粗；
    // 刻度在弧内侧（从弧线向圆心方向伸出）
    if (showTicks) {
      for (var i = 0; i <= 10; i++) {
        final isMajor = i == 0 || i == 5 || i == 10;
        final ang = _startAngle + _sweep * i / 10;
        final outer = radius - 3; // 从弧内缘起笔
        final inner = radius - (isMajor ? 14 : 9);
        final p1 = center +
            Offset(math.cos(ang), math.sin(ang)) * outer;
        final p2 = center +
            Offset(math.cos(ang), math.sin(ang)) * inner;
        final tick = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isMajor ? 2.5 : 1.5
          ..strokeCap = StrokeCap.round
          ..color = isMajor ? t.borderStrong : t.border;
        canvas.drawLine(p1, p2, tick);
      }
    }

    // 对准区（±5¢）：锁定时实心绿（锐利，无 blur）
    final zoneStart = _startAngle + _sweep * 0.45;
    final zoneSpan = _sweep * 0.1;
    final zonePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.butt
      ..color = locked ? t.ok : t.borderStrong;
    canvas.drawArc(rect, zoneStart, zoneSpan, false, zonePaint);

    // 指针常驻：无信号也画（停在 -1 满偏待命），只是不放光点辉光
    final n = needle.clamp(-1.0, 1.0);
    final headAngle = _startAngle + _sweep * (0.5 + n * 0.5);

    if (hasSignal) {
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
    }

    // 环心指针：细杆从中心外侧 55% 半径起笔到光点（常驻）
    final innerR = radius * 0.55;
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
  }

  @override
  bool shouldRepaint(_GlowRingPainter old) =>
      old.needle != needle ||
      old.locked != locked ||
      old.near != near ||
      old.hasSignal != hasSignal ||
      old.breathPhase != breathPhase;
}

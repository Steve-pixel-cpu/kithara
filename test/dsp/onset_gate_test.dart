import 'package:flutter_test/flutter_test.dart';
import 'package:kithara/dsp/onset_gate.dart';

void main() {
  group('OnsetGate 拨弦起振门', () {
    test('稳态噪声（恒定 RMS）永不触发，EMA 收敛到噪声水位', () {
      final g = OnsetGate();
      final t0 = DateTime(2026, 10, 31);
      var t = t0;
      // 恒定底噪 0.01，喂 200 帧
      var opened = 0;
      for (var i = 0; i < 200; i++) {
        if (g.accept(0.01, t)) opened++;
        t = t.add(const Duration(milliseconds: 50));
      }
      expect(opened, 0);
    });

    test('RMS 跳升 1.5x 触发开窗，窗口 400ms 内放行', () {
      final g = OnsetGate();
      final t0 = DateTime(2026, 10, 31);
      var t = t0;
      // 底噪收敛
      for (var i = 0; i < 100; i++) {
        g.accept(0.01, t);
        t = t.add(const Duration(milliseconds: 50));
      }
      // 拨弦: RMS 跳到 0.05（5x 底噪）
      expect(g.accept(0.05, t), isTrue, reason: '起振帧放行');
      // 窗口内（+100ms ~ +350ms）放行
      t = t.add(const Duration(milliseconds: 100));
      expect(g.accept(0.04, t), isTrue, reason: '窗口内放行');
      t = t.add(const Duration(milliseconds: 250));
      expect(g.accept(0.03, t), isTrue, reason: '窗口边缘（400ms 内）放行');
      // 窗口外（+500ms）且 RMS 回落到底噪水位 → 拒绝
      // （0.02 仍 > 底噪 EMA×1.5 会再触发——那是真实的"第二下拨弦"语义；
      //   这里回落到底噪本身）
      t = t.add(const Duration(milliseconds: 150));
      expect(g.accept(0.01, t), isFalse, reason: '窗口已关且未跳升');
    });

    test('拨弦帧不抬 EMA：连续拨弦每次都能再触发（EMA 只在关窗时更新）', () {
      final g = OnsetGate();
      final t0 = DateTime(2026, 10, 31);
      var t = t0;
      for (var i = 0; i < 100; i++) {
        g.accept(0.01, t);
        t = t.add(const Duration(milliseconds: 50));
      }
      // 第一次拨弦
      expect(g.accept(0.05, t), isTrue);
      t = t.add(const Duration(milliseconds: 500)); // 窗口已关
      // EMA 应仍在底噪水位（~0.01），第二次拨弦照常触发
      expect(g.accept(0.05, t), isTrue, reason: 'EMA 未被上次拨弦抬高');
    });

    test('绝对下限：微小信号的相对跳升不触发（远场微弱声）', () {
      final g = OnsetGate(minRms: 0.012);
      final t0 = DateTime(2026, 10, 31);
      var t = t0;
      for (var i = 0; i < 100; i++) {
        g.accept(0.0001, t);
        t = t.add(const Duration(milliseconds: 50));
      }
      // 10x 跳升但绝对值 0.001 << 0.012
      expect(g.accept(0.001, t), isFalse);
    });

    test('reset() 后 EMA 重新 seeded（模式切换/管线重建）', () {
      final g = OnsetGate();
      final t0 = DateTime(2026, 10, 31);
      var t = t0;
      for (var i = 0; i < 50; i++) {
        g.accept(0.01, t);
        t = t.add(const Duration(milliseconds: 50));
      }
      g.reset();
      // reset 后首帧重新 seeded，不判跳升
      expect(g.accept(0.05, t), isFalse);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:kithara/audio/ring_buffer.dart';

void main() {
  test('写入后 readWindow 返回最近 4096 样本且顺序正确', () {
    final rb = RingBuffer(8192);
    final data = List.generate(4096, (i) => i / 1000.0);
    rb.write(data);
    final win = rb.readWindow(4096);
    expect(win, isNotNull);
    expect(win, hasLength(4096));
    for (var i = 0; i < 4096; i++) {
      expect(win![i], closeTo(data[i], 1e-5), reason: 'i=$i'); // Float32 存储精度
    }
  });

  test('写入 <4096 样本返回 null', () {
    final rb = RingBuffer(8192);
    rb.write(List.filled(1000, 0.5));
    expect(rb.readWindow(4096), isNull);
  });

  test('溢出: 10000 样本写入 8192 容量 → 只保留最新 8192', () {
    final rb = RingBuffer(8192);
    rb.write(List.generate(10000, (i) => i.toDouble()));
    expect(rb.available, 8192);
    // 读 4096 窗口 → 应为样本 [5904..9999] 中最新 4096 = [5904..9999] 的最后段
    // available=8192: 最新 8192 样本 = [1808..9999]; 4096 窗口 = [5904..9999]
    final win = rb.readWindow(4096);
    expect(win![0], 5904.0);
    expect(win[4095], 9999.0);
    // 耗尽后再读 → null
    expect(rb.readWindow(4096), isNull);
  });
}

import 'dart:math' as math;


import 'package:flutter_test/flutter_test.dart';
import 'package:kithara/tuner/tuner_controller.dart';
import 'package:kithara/tuner/tuning_modes.dart';

void main() {
  late TunerController controller;

  setUp(() {
    controller = TunerController();
  });

  test('初始状态: standard 模式, a4=440, noSignal', () {
    expect(controller.state.mode.id, 'standard');
    expect(controller.state.a4, 440.0);
    expect(controller.state.hasSignal, isFalse);
    expect(controller.state.activeString, isNull);
  });

  test('onPitch: chromatic 模式显示音名+cents', () {
    controller.setMode(TuningModes.byId('chromatic'));
    // A4+10¢（稳定门限: 喂 3 帧唤醒）
    for (var i = 0; i < 3; i++) {
      controller.onPitch(440.0 * 1.0058, 0.95);
    }
    expect(controller.state.hasSignal, isTrue);
    expect(controller.state.noteLabel, 'A4');
    expect(controller.state.cents, closeTo(10.0, 0.5));
    expect(controller.state.activeString, isNull);
  });

  test('onPitch: 字符串模式吸附最近弦, ±5¢ 内 inTune', () {
    // A2 +3¢（3 帧稳定唤醒）
    for (var i = 0; i < 3; i++) {
      controller.onPitch(110.0 * 1.0017, 0.95);
    }
    expect(controller.state.activeString!.name, 'A2');
    expect(controller.state.inTune, isTrue);
    expect(controller.state.cents, closeTo(3.0, 0.5));
  });

  test('onPitch: 偏离 >5¢ 不 inTune', () {
    controller.onPitch(110.0 * 1.02, 0.95); // +34¢
    expect(controller.state.inTune, isFalse);
  });

  test('onPitch: 模式内无弦匹配 → hasSignal 但 activeString null', () {
    for (var i = 0; i < 3; i++) {
      controller.onPitch(500.0, 0.95);
    }
    expect(controller.state.hasSignal, isTrue);
    expect(controller.state.activeString, isNull);
  });

  test('onPitch(null): hasSignal=false, 音名/弦保留 (UI 平滑)', () {
    for (var i = 0; i < 3; i++) {
      controller.onPitch(110.0, 0.95); // 稳定唤醒
    }
    controller.onPitch(null, 0.9);
    expect(controller.state.hasSignal, isFalse);
    expect(controller.state.noteLabel, 'A2'); // 保留
  });

  test('音名滞回: 突变 >50¢ 需连续 2 帧确认才换音名（E4/E3 反复的 UI 根因）', () {
    final controller = TunerController();
    controller.setMode(TuningModes.chromatic);
    for (var i = 0; i < 3; i++) {
      controller.onPitch(329.63, 0.95); // E4 稳定唤醒
    }
    expect(controller.state.noteLabel, 'E4');
    // 突变到 E3（一帧噪声/误检）→ 不换
    controller.onPitch(164.81, 0.95);
    expect(controller.state.noteLabel, 'E4', reason: '单帧突变不换名');
    // 连续第二帧 E3 → 确认换名
    controller.onPitch(164.81, 0.95);
    expect(controller.state.noteLabel, 'E3');
  });

  test('稳定门限: 单帧/双帧不唤醒, 连续 3 帧稳定才 hasSignal（拒说话声）', () {
    // 模拟拨弦: 稳定 110Hz
    controller.onPitch(110.0, 0.95);
    expect(controller.state.hasSignal, isFalse, reason: '1 帧不唤醒');
    controller.onPitch(110.0, 0.95);
    expect(controller.state.hasSignal, isFalse, reason: '2 帧不唤醒');
    controller.onPitch(110.0, 0.95);
    expect(controller.state.hasSignal, isTrue, reason: '3 帧稳定唤醒');
  });

  test('稳定门限: 音高滑动的短音列（说话）不唤醒', () {
    // 模拟说话: 每帧音高滑 >40¢（带内), 或带间跳变重置计数
    final sliding = [110.0, 114.0, 119.0, 124.0, 129.0]; // 每帧 +60¢ 左右
    for (final f in sliding) {
      controller.onPitch(f, 0.95);
    }
    expect(controller.state.hasSignal, isFalse,
        reason: '说话音高持续滑动 → 唤不醒');
    // 同一音节内小幅颤动 <40¢ 但时长不足 3 帧
    final wobble = [220.0, 224.0];
    for (final f in wobble) {
      controller.onPitch(f, 0.95);
    }
    expect(controller.state.hasSignal, isFalse, reason: '不足 3 帧');
  });

  test('稳定门限: 唤醒后不再设卡, 音高缓滑正常跟随（拧弦场景）', () {
    for (var i = 0; i < 3; i++) {
      controller.onPitch(110.0, 0.95); // 稳定唤醒
    }
    expect(controller.state.hasSignal, isTrue);
    // 拧弦: 音高缓慢移动（每帧 +15¢, 中值滤波窗口滑过后正常跟随）
    for (var i = 0; i < 3; i++) {
      controller.onPitch(111.0, 0.95);
    }
    expect(controller.state.hasSignal, isTrue, reason: '唤醒后跟随');
    expect(controller.state.cents, greaterThan(0));
  });

  test('稳定门限: 带间跳变重置锚点, 乱序噪声不唤醒', () {
    // 前两帧 110Hz, 第三帧跳到 190Hz（>40¢ 带）→ 锚点重置
    controller.onPitch(110.0, 0.95);
    controller.onPitch(110.0, 0.95);
    controller.onPitch(190.0, 0.95);
    controller.onPitch(190.0, 0.95);
    expect(controller.state.hasSignal, isFalse, reason: '跳变重置计数');
    // 从新锚点稳定 3 帧 → 唤醒
    controller.onPitch(190.0, 0.95);
    expect(controller.state.hasSignal, isTrue, reason: '新锚点稳定 3 帧');
  });

  test('稳定门限: 信号丢失后重新计数（重复拨弦每次都需稳定）', () {
    for (var i = 0; i < 3; i++) {
      controller.onPitch(110.0, 0.95);
    }
    expect(controller.state.hasSignal, isTrue);
    controller.onPitch(null, 0.9); // 衰减静音
    expect(controller.state.hasSignal, isFalse);
    // 再次拨弦: 1 帧不唤醒（重新计数）
    controller.onPitch(110.0, 0.95);
    expect(controller.state.hasSignal, isFalse);
    for (var i = 0; i < 2; i++) {
      controller.onPitch(110.0, 0.95);
    }
    expect(controller.state.hasSignal, isTrue);
  });

  test('会话调准记忆: 调准过的弦保持 tuned 标记, 换弦不清, 切模式清', () {
    final controller = TunerController();
    // 调准 6 弦 E2
    for (var i = 0; i < 3; i++) {
      controller.onPitch(82.41 * 1.001, 0.95); // 稳定唤醒
    }
    expect(controller.state.tunedSemis, contains(-29), reason: 'E2 调准后记入');
    // 转去调 5 弦（不调准）—— E2 标记仍在
    for (var i = 0; i < 3; i++) {
      controller.onPitch(110.0 * 1.02, 0.95); // A2 偏 +34¢ 未准（已唤醒直接跟随）
    }
    expect(controller.state.tunedSemis, contains(-29), reason: '换弦不清记忆');
    expect(controller.state.tunedSemis, isNot(contains(-24)));
    // 调准 A2 → 两个标记
    for (var i = 0; i < 3; i++) {
      controller.onPitch(110.0 * 1.001, 0.95);
    }
    expect(controller.state.tunedSemis, containsAll([-29, -24]));
    // 切模式 → 清空
    controller.setMode(TuningModes.dropD);
    expect(controller.state.tunedSemis, isEmpty);
  });

  test('量程自适应: |cents|<=50 用 ±50 档, 大偏差自动扩档', () {
    final controller = TunerController();
    controller.selectString(-29); // 锁 E2
    expect(controller.state.range, 50);
    // 拧紧到 -180¢ → 扩 ±250 档, needle = -180/250 = -0.72
    for (var i = 0; i < 5; i++) {
      controller.onPitch(82.41 * math.pow(2, -180 / 1200), 0.95);
    }
    expect(controller.state.range, 250);
    expect(controller.state.needle, closeTo(-0.72, 0.02));
    // 更远 -400¢ → ±500 档
    for (var i = 0; i < 5; i++) {
      controller.onPitch(82.41 * math.pow(2, -400 / 1200), 0.95);
    }
    expect(controller.state.range, 500);
    expect(controller.state.needle, closeTo(-0.8, 0.02));
    // 拧回接近: -40¢ → 回 ±50 档
    for (var i = 0; i < 5; i++) {
      controller.onPitch(82.41 * math.pow(2, -40 / 1200), 0.95);
    }
    expect(controller.state.range, 50);
    expect(controller.state.needle, closeTo(-0.8, 0.02));
  });

  test('松弦八度归一: 锁 E2 后检测在基频/2倍泛音间交替, 偏差方向恒定不遍历', () {
    final controller = TunerController();
    controller.selectString(-29); // 锁 E2 = 82.41Hz
    // 模拟真实松弦序列: 基频 70Hz 与 2x 泛音 140Hz 交替
    final frames = [70.0, 140.0, 70.0, 140.0, 70.0, 140.0];
    for (final f in frames) {
      controller.onPitch(f, 0.95);
    }
    // 归一后: 70Hz→约-280¢(拧紧), 140Hz 降八度→70Hz→同样-280¢
    // 所有帧 cents 都应为负且一致(±30¢ 内), 绝不出现 +50 方向
    final cents = controller.state.cents;
    expect(cents, lessThan(-100), reason: '恒负偏差: got $cents');
    // 连续采样稳定性
    controller.onPitch(140.0, 0.95);
    final cents2 = controller.state.cents;
    expect((cents2 - cents).abs(), lessThan(30), reason: '帧间稳定: $cents vs $cents2');
  });

  test('松弦毛刺抑制: 检测帧间乱跳时中值滤波稳住读数（毛刺帧被丢弃）', () {
    final controller = TunerController();
    controller.selectString(-5); // 锁 E4
    // 模拟松弦的真实检测序列: 真值 ~250Hz, 混入毛刺帧 400/180
    final frames = [250.0, 400.0, 250.0, 250.0, 180.0, 250.0, 251.0, 249.0];
    final centsSeen = <double>[];
    for (final f in frames) {
      controller.onPitch(f, 0.95);
      centsSeen.add(controller.state.cents);
    }
    // 中值滤波后: 所有 cents 应稳定在 250Hz 的真实偏差附近（±20¢ 内）,
    // 而不是出现 400Hz(-316c 相对偏差更负) / 180Hz 的极端跳变
    final base = centsSeen.last;
    for (final c in centsSeen.skip(2)) {
      expect((c - base).abs(), lessThan(25),
          reason: 'cents 序列 ${centsSeen.map((e) => e.toStringAsFixed(0)).join(",")} 应平滑');
    }
    // needle 稳定为负（真实偏差方向）且被量程归一（非 -1 满偏乱跳）
    expect(controller.state.needle, lessThan(-0.3));
    expect(controller.state.needle, greaterThan(-1.01));
  });

  test('手动粘性锁: 弹任意音不丢锁定, 偏差相对目标弦（很松的弦也能看到 -50 满偏）', () {
    final controller = TunerController();
    controller.selectString(-5); // E4 = 1弦
    expect(controller.state.activeString!.name, 'E4');
    // 弦很松: 260Hz 距 E4 约 -410¢（B3 附近, 自动模式下会吸走/清锁）
    controller.onPitch(260.0, 0.95);
    expect(controller.state.activeString!.name, 'E4', reason: '粘性锁不被自动匹配覆盖');
    expect(controller.state.noteLabel, 'E4', reason: '显示目标音名而非检测音名');
    expect(controller.state.cents, lessThan(-350), reason: 'cents=${controller.state.cents} 应约 -410');
    expect(controller.state.needle, -1.0, reason: '满偏 -50 侧');
    expect(controller.state.inTune, isFalse);
    // 拧紧到 E4 附近 → inTune
    controller.onPitch(329.63 * 1.001, 0.95);
    expect(controller.state.inTune, isTrue);
    // 再点同一弦 → 解锁回自动
    controller.selectString(-5);
    controller.onPitch(260.0, 0.95);
    expect(controller.state.activeString, isNull, reason: '解锁后 260Hz 不吸附任何弦');
  });

  test('手动粘性锁: 换模式清除', () {
    final controller = TunerController();
    controller.selectString(-5); // E4
    controller.setMode(TuningModes.dropD);
    expect(controller.state.activeString, isNull);
    for (var i = 0; i < 3; i++) {
      controller.onPitch(329.63, 0.95);
    }
    // drop_d 里 E4 匹配 1 弦（半音距离 0）
    expect(controller.state.activeString!.name, 'E4');
  });

  test('锁弦: 字符串模式 2 次同弦才切换 activeString', () {
    // 先到 D3 附近（稳定门限 3 帧唤醒）
    for (var i = 0; i < 3; i++) {
      controller.onPitch(146.83, 0.95);
    }
    // 立刻跳到 A2 一次 → 不切换
    controller.onPitch(110.0, 0.95);
    expect(controller.state.activeString!.name, 'D3');
    // 第二次 A2 → 切换
    controller.onPitch(110.0, 0.95);
    expect(controller.state.activeString!.name, 'A2');
  });

  test('锁定保持窗口: 信号丢失 2s 内 inTune 保持, 过期释放', () {
    var now = DateTime(2026, 1, 1);
    final controller = TunerController()..nowForTest = () => now;
    for (var i = 0; i < 3; i++) {
      controller.onPitch(110.0 * 1.001, 0.95); // A2 锁定（稳定门限 3 帧唤醒）
    }
    controller.onPitch(null, 0.9); // 信号丢失 → 启动保持窗口
    expect(controller.state.inTune, isTrue, reason: '保持窗口内');
    now = now.add(const Duration(milliseconds: 1500));
    expect(controller.state.inTune, isTrue, reason: '1.5s 仍在窗口内');
    now = now.add(const Duration(milliseconds: 600)); // 累计 2.1s
    expect(controller.state.inTune, isFalse, reason: '过期释放');
  });

  test('信号滞回: 置信度 0.75~0.85 之间不闪烁（维持上一帧状态）', () {
    final controller = TunerController();
    controller.onPitch(110.0, 0.95); // 稳定检出 → hasSignal
    controller.onPitch(110.0, 0.95);
    controller.onPitch(110.0, 0.95);
    expect(controller.state.hasSignal, isTrue);
    // 边缘置信度: 高于维持门限 0.75 → 维持检出（帧数不重置, 已唤醒）
    controller.onPitch(110.0, 0.80);
    expect(controller.state.hasSignal, isTrue, reason: '滞回维持');
    // 低于维持门限 → 丢信号
    controller.onPitch(110.0, 0.70);
    expect(controller.state.hasSignal, isFalse);
    // 重新检出: 达触发门限但只 1 帧 → 稳定门限不唤醒
    controller.onPitch(110.0, 0.86);
    expect(controller.state.hasSignal, isFalse, reason: '重新唤醒需稳定 3 帧');
    controller.onPitch(110.0, 0.86);
    expect(controller.state.hasSignal, isFalse);
    controller.onPitch(110.0, 0.86);
    expect(controller.state.hasSignal, isTrue, reason: '稳定 3 帧唤醒');
  });

  // ---------- 2026-10 不对称弦锁 ----------

  test('不对称锁: 低置信不捕获新弦（首次锁定需高置信）', () {
    final c = TunerController();
    c.captureConfidence = 0.90; // 严格档
    // 帧序列：A2 频率，置信度 0.86（>信号触发 0.85，<捕获 0.90）
    for (var i = 0; i < 5; i++) {
      c.onPitch(110.0, 0.86);
    }
    // 唤醒照常（信号滞回门限 0.85→0.75 已过），但弦锁被捕获门拦下
    expect(c.state.hasSignal, isTrue, reason: '信号层滞回不受弦锁门限影响');
    expect(c.state.activeString, isNull, reason: '低置信帧不得捕获新弦');
  });

  test('不对称锁: 高置信正常捕获', () {
    final c = TunerController();
    c.captureConfidence = 0.90;
    for (var i = 0; i < 3; i++) {
      c.onPitch(110.0, 0.95);
    }
    expect(c.state.activeString, isNotNull);
    expect(c.state.activeString!.semitoneIndex, -24); // A2（相对 A4 的半音数）
  });

  test('不对称锁: 已锁定的弦在低置信帧不失锁（低置信只能续不能抢）', () {
    final c = TunerController();
    c.captureConfidence = 0.90;
    for (var i = 0; i < 3; i++) {
      c.onPitch(110.0, 0.95);
    }
    expect(c.state.activeString!.semitoneIndex, -24);
    // 低置信同弦帧：维持
    c.onPitch(110.5, 0.76);
    expect(c.state.activeString!.semitoneIndex, -24, reason: '同弦续锁宽松');
    // 低置信异弦帧（换弦企图）：不换锁（0.86 过信号门 0.85，不过捕获门 0.90）
    c.onPitch(146.83, 0.86); // D3
    c.onPitch(146.83, 0.86);
    expect(c.state.activeString!.semitoneIndex, -24,
        reason: '低置信帧不得换弦（连续 2 帧防抖也被门限拦住）');
    // 高置信异弦帧：正常换弦（2 帧防抖后）
    c.onPitch(146.83, 0.95);
    c.onPitch(146.83, 0.95);
    expect(c.state.activeString!.semitoneIndex, -19, reason: '高置信允许换弦');
  });

  test('setMode: 清锁弦计数, activeString 重置', () {
    for (var i = 0; i < 3; i++) {
      controller.onPitch(110.0, 0.95);
    }
    expect(controller.state.activeString, isNotNull);
    controller.setMode(TuningModes.byId('drop_d'));
    expect(controller.state.activeString, isNull);
    expect(controller.state.mode.id, 'drop_d');
  });

  test('setA4: 重建 mapper, A4=435 时 110Hz 显示 +19.6¢', () {
    controller.setA4(435.0);
    for (var i = 0; i < 3; i++) {
      controller.onPitch(110.0, 0.95);
    }
    // 110Hz 相对 A2@435(=108.335) 偏 +19.6¢
    expect(controller.state.cents, closeTo(19.6, 0.5));
    expect(controller.state.noteLabel, 'A2');
  });

  test('needle: -1..1 归一化, ±50¢ 映射满偏', () {
    controller.setMode(TuningModes.byId('chromatic'));
    // 滤波窗口 3 帧: 连发同值使窗口收敛后再断言
    for (var i = 0; i < 5; i++) {
      controller.onPitch(440.0 * math.pow(2, 50 / 1200), 0.95); // +50¢
    }
    // +50¢ 触发滞回扩档至 ±250: needle = 50/250 = 0.2（量程自适应）
    expect(controller.state.range, 250);
    expect(controller.state.needle, closeTo(0.2, 0.02));
    for (var i = 0; i < 5; i++) {
      controller.onPitch(440.0, 0.95);
    }
    expect(controller.state.needle, closeTo(0.0, 0.001));
    for (var i = 0; i < 5; i++) {
      controller.onPitch(440.0 * math.pow(2, -50 / 1200), 0.95); // -50¢
    }
    expect(controller.state.needle, closeTo(-0.2, 0.02));
  });
}

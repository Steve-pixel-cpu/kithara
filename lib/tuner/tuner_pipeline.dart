import '../audio/ring_buffer.dart';
import '../dsp/pitch_detector.dart';
import 'tuner_controller.dart';

/// 数据管线桥：MicStream→RingBuffer→PitchDetector→TunerController。
/// UI 每帧 tick 一次（约 60fps 下 4~5 帧驱动一次检测，见 spec §6 节流）。
class TunerPipeline {
  TunerPipeline({
    required this.ringBuffer,
    required this.detector,
    required this.controller,
    this.detectEveryNTicks = 1,
  });

  final RingBuffer ringBuffer;
  final PitchDetector detector;
  final TunerController controller;

  /// 节流：每 N 个 tick 跑一次检测（默认 1=每 tick；UI 侧可按 60fps 下 DSP 开销调大）。
  final int detectEveryNTicks;
  int _tickCount = 0;

  void tick() {
    _tickCount++;
    if (_tickCount % detectEveryNTicks != 0) return;
    final window = ringBuffer.readWindow(detector.window);
    if (window == null) return;
    controller.onPitch(detector.detect(window), detector.lastConfidence);
  }
}

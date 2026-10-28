import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'ring_buffer.dart';

/// 麦克风采集封装。44.1kHz 单声道 16-bit PCM → 归一化 double [-1,1]
/// → RingBuffer。UI 侧每 tick 调 readWindow(4096)。
class MicStream {
  MicStream({this.sampleRate = 44100, this.bufferCapacity = 16384})
      : ringBuffer = RingBuffer(bufferCapacity),
        _recorder = AudioRecorder();

  final int sampleRate;
  final int bufferCapacity;
  final RingBuffer ringBuffer;
  final AudioRecorder _recorder;
  StreamSubscription? _sub;

  /// 麦克风权限是否已授予。
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// 请求权限并开始采集。返回是否成功启动。
  Future<bool> start() async {
    if (await _recorder.isRecording()) return true;
    if (!await _recorder.hasPermission()) return false;
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        numChannels: 1,
        sampleRate: 44100,
      ),
    );
    _sub = stream.listen(_onChunk);
    return true;
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _recorder.stop();
    ringBuffer.clear();
  }

  /// 16-bit LE PCM → double [-1,1]，追加到 RingBuffer。
  void _onChunk(List<int> chunk) {
    final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
    final n = bytes.length ~/ 2;
    final samples = Float32List(n);
    final bd = ByteData.sublistView(bytes);
    for (var i = 0; i < n; i++) {
      samples[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
    }
    ringBuffer.write(samples);
  }

  void dispose() {
    _sub?.cancel();
    _recorder.dispose();
  }
}

import 'dart:typed_data';

/// 单写单读的环形音频缓冲。write 丢弃最旧样本保证不溢出；
/// readWindow 返回最新 n 个样本的副本（4096 窗口给 MPM）。
class RingBuffer {
  RingBuffer(this.capacity)
      : _data = Float32List(capacity),
        _start = 0,
        _count = 0;

  final int capacity;
  final Float32List _data;
  int _start; // 最旧样本下标
  int _count;

  int get available => _count;

  void write(List<double> samples) {
    var n = samples.length;
    if (n >= capacity) {
      // 只保留最新 capacity 个
      final offset = n - capacity;
      for (var i = 0; i < capacity; i++) {
        _data[i] = samples[offset + i];
      }
      _start = 0;
      _count = capacity;
      return;
    }
    // 若会溢出，先丢掉最旧 (n) 个
    if (_count + n > capacity) {
      final drop = _count + n - capacity;
      _start = (_start + drop) % capacity;
      _count -= drop;
    }
    var pos = (_start + _count) % capacity;
    for (var i = 0; i < n; i++) {
      _data[pos] = samples[i];
      pos = (pos + 1) % capacity;
      if (pos == capacity) pos = 0;
    }
    _count += n;
  }

  /// 返回最新 n 个样本；不足 n 返回 null。读取后清空已读部分（耗尽语义）。
  Float32List? readWindow(int n) {
    if (_count < n) return null;
    final out = Float32List(n);
    final startIdx = (_start + _count - n) % capacity;
    for (var i = 0; i < n; i++) {
      out[i] = _data[(startIdx + i) % capacity];
    }
    // 已读部分耗尽：保留剩余（本次实现按 spec"读后耗尽"直接清空）
    _start = (_start + _count) % capacity;
    _count = 0;
    return out;
  }

  void clear() {
    _start = 0;
    _count = 0;
  }
}

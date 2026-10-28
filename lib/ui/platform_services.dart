import 'dart:async';

import 'package:flutter/services.dart';

import '../audio/mic_stream.dart';

/// 权限抽象（测试注入用）。
abstract class MicPermission {
  Future<bool> ensure();
}

class MicPermissionImpl implements MicPermission {
  MicPermissionImpl(this._mic);

  final MicStream _mic;

  @override
  Future<bool> ensure() => _mic.hasPermission();
}

/// 触觉抽象（测试注入用）。
abstract class Haptics {
  void inTunePulse();
}

class HapticsImpl implements Haptics {
  @override
  void inTunePulse() => unawaited(HapticFeedback.mediumImpact());
}

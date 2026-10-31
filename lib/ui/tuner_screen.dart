
import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/mic_stream.dart';
import '../theme/kithara_theme.dart';
import '../tuner/tuner_controller.dart';
import '../tuner/tuning_modes.dart';
import 'glow_ring.dart';
import 'platform_services.dart';

/// 调音器主界面：仪表指针 + 音名大字 + 弦条 + 模式/参考音控件。
/// 生命周期：进入前台自动 start 麦克风；退后台 stop；权限拒绝显示引导页。
class TunerScreen extends StatefulWidget {
  const TunerScreen({
    super.key,
    required this.controller,
    required this.mic,
    this.micPermission,
    this.haptics,
    this.theme = KitharaTheme.dark,
    this.themeMode = 'dark',
    this.noisyMode = false,
    this.onThemeToggle,
    this.onNoisyModeChanged,
    this.onSelectString,
  });

  final TunerController controller;

  /// 由装配层传入的唯一 MicStream 实例。本组件只负责 start/stop 生命周期，
  /// 绝不自建实例（曾因自建第二实例导致管线读取空缓冲：拨弦无反应）。
  final MicStream mic;
  final MicPermission? micPermission;
  final Haptics? haptics;

  /// 设计令牌（aulos 设计语言，深浅两套）。
  final KitharaTheme theme;

  /// 主题模式：'system' 跟随系统亮度（覆盖 theme 字段），'light'/'dark' 固定。
  final String themeMode;

  /// 嘈杂环境调音开关（显示 + 修改回调）
  final bool noisyMode;
  final ValueChanged<bool>? onNoisyModeChanged;

  /// 主题切换回调（主题所有权在装配层/外部）。
  final VoidCallback? onThemeToggle;

  /// 点击弦条手动指定目标弦（参数为该弦音名对应的半音索引）。
  final ValueChanged<int>? onSelectString;

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  bool _micStarted = false;
  bool _permissionDenied = false;
  bool _wasInTune = false;
  String? _stringHint; // 选弦提示（6弦），2s 自动消失
  Timer? _stringHintTimer;

  // 静止态呼吸：底环透明度 3s 周期缓变
  late final AnimationController _breathCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  );
  // 指针平滑：读数（滤波+归一后的稳定值）变化时 150ms 过渡。
  // 关键区别于被删的弹簧系统: tween 只对显示值插值, 目标不追帧流——
  // 每帧重设也无所谓, controller 层已保证 target 稳定
  double _needleFrom = 0.0;
  double _needleTo = 0.0;
  late final AnimationController _needleTween = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
  );

  MicPermission get _perm =>
      widget.micPermission ?? MicPermissionImpl(widget.mic);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onState);
    _breathCtrl.repeat();
    // 呼吸动画常转: 搭车驱动"时间依赖状态"（保持窗口过期后指针回 -500）
    _breathCtrl.addListener(_syncNeedleTarget);
    _startup();
  }

  Future<void> _startup() async {
    final granted = await (widget.micPermission ?? _perm).ensure();
    if (!mounted) return;
    if (!granted) {
      setState(() => _permissionDenied = true);
      return;
    }
    await _startMic();
  }

  Future<void> _startMic() async {
    final ok = await widget.mic.start();
    if (!mounted) return;
    setState(() {
      _permissionDenied = !ok;
      _micStarted = ok;
    });
  }

  Future<void> _stopMic() async {
    if (!_micStarted) return;
    await widget.mic.stop();
    _micStarted = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startup();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _stopMic();
    }
  }

  @override
  void didUpdateWidget(covariant TunerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onState);
      widget.controller.addListener(_onState);
    }
  }

  /// 指针目标同步: state.needle 变化（含保持窗口过期这种纯时间事件）→ tween
  void _syncNeedleTarget() {
    final s = widget.controller.state;
    final newTarget = s.inTune ? 0.0 : s.needle;
    if ((newTarget - _needleTo).abs() > 0.001) {
      _needleFrom = _displayNeedleValue();
      _needleTo = newTarget;
      _needleTween.forward(from: 0);
    }
  }

  double _displayNeedleValue() {
    final t = Curves.easeOutCubic.transform(_needleTween.value);
    return _needleFrom + (_needleTo - _needleFrom) * t;
  }

  @override
  void dispose() {
    _stringHintTimer?.cancel();
    _needleTween.dispose();
    _breathCtrl.dispose();
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onState);
    _stopMic();
    super.dispose();
  }

  void _onState() {
    final s = widget.controller.state;
    // inTune 边沿 → 触觉脉冲 + 音名弹跳 + 弹簧目标切到 0（环心对准）
    if (s.inTune && !_wasInTune) {
      widget.haptics?.inTunePulse();
    }
    _wasInTune = s.inTune;
    _syncNeedleTarget();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.controller.state;
    // 'system' → 跟随平台亮度实时解析；'light'/'dark' 用传入 theme 的亮暗
    final KitharaTheme t;
    if (widget.themeMode == 'system') {
      final platformBright =
          MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.dark;
      t = platformBright == Brightness.light
          ? KitharaTheme.light
          : KitharaTheme.dark;
    } else {
      t = widget.theme;
    }
    final isChromatic = s.mode.semitones.isEmpty;

    if (_permissionDenied) {
      return Scaffold(
        backgroundColor: t.bg,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.mic_off, color: t.text3, size: 64),
              const SizedBox(height: 16),
              Text('需要麦克风权限',
                  style: TextStyle(color: t.text2, fontSize: 18)),
              const SizedBox(height: 24),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: t.surface2,
          foregroundColor: t.text,
          elevation: 0,
          onPressed: () {
            setState(() => _permissionDenied = false);
            _startup();
          },
          label: const Text('重试'),
          icon: const Icon(Icons.refresh),
        ),
      );
    }

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部：模式选择 + 参考音（surface-2 底 + 1px 边框, aulos 分层手法）
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: PopupMenuButton<TuningMode>(
                    color: t.popBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: t.border),
                    ),
                    onSelected: (m) {
                      widget.haptics?.selectionClick();
                      widget.controller.setMode(m);
                    },
                    constraints: const BoxConstraints(maxHeight: 420),
                    itemBuilder: (_) => [
                      for (final m in TuningModes.all)
                        PopupMenuItem(
                          value: m,
                          child: Text(m.label,
                              style: TextStyle(color: t.text)),
                        ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(s.mode.label,
                              style: TextStyle(
                                color: t.text2,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              )),
                          Icon(Icons.arrow_drop_down,
                              color: t.text3, size: 22),
                        ],
                      ),
                    ),
                  ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        key: const Key('settings_btn'),
                        onTap: () {
                          widget.haptics?.selectionClick();
                          _showSettingsDialog(context);
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(Icons.settings_outlined,
                              color: t.text3, size: 20),
                        ),
                      ),
                      InkWell(
                        key: const Key('theme_toggle'),
                        onTap: () {
                          widget.haptics?.selectionClick();
                          widget.onThemeToggle?.call();
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                          switch (widget.themeMode) {
                            'system' => Icons.brightness_auto_outlined,
                            'light' => Icons.dark_mode_outlined, // 当前浅色,点击切深色
                            _ => Icons.light_mode_outlined, // 当前深色,点击切浅色
                          },
                          color: t.text3,
                          size: 20,
                        ),
                        ),
                      ),
                      Flexible(
                        child: InkWell(
                          onTap: () {
                            widget.haptics?.selectionClick();
                            _showA4Dialog(context, s.a4);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Text(
                              'A4 ${s.a4.toStringAsFixed(1)}',
                              style: TextStyle(
                                color: t.text3,
                                fontSize: 16,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Spacer(flex: 2),
            // 发光环仪表：环心音名大字 + cents；弹簧插值 needle
            Center(
              child: AnimatedBuilder(
                animation: _needleTween,
                builder: (context, anim) {
                  // 指针 = state.needle（滤波+八度归一+滞回后的稳定值）
                  // 与引导语同源; 显示层只做 150ms 平滑（不追帧流）
                  final k = Curves.easeOutCubic.transform(_needleTween.value);
                  final display = _needleFrom + (_needleTo - _needleFrom) * k;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      GlowRing(
                        needle: display,
                        locked: s.inTune,
                        near: s.hasSignal &&
                            !s.inTune &&
                            s.cents.abs() <= 30,
                        hasSignal: s.hasSignal,
                        theme: t,
                        size: 300,
                        breathPhase: _breathCtrl.value,
                      ),
                      // 量程标注（弧两端 + 顶部）
                      Positioned(
                        left: 18,
                        bottom: 42,
                        child: Text('-${s.range}',
                            style: TextStyle(
                              color: t.text3,
                              fontSize: 11,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            )),
                      ),
                      Positioned(
                        right: 18,
                        bottom: 42,
                        child: Text('+${s.range}',
                            style: TextStyle(
                              color: t.text3,
                              fontSize: 11,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            )),
                      ),
                      // 环心音名：AnimatedSwitcher 淡入淡出治闪烁
                      // （置信度门限边缘抖动时，音名渐隐渐现而非瞬灭瞬现）
                      KeyedSubtree(
                        key: const Key('in_tune_indicator'),
                        child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: child,
                        ),
                        child: s.hasSignal
                            ? Column(
                                key: ValueKey(s.noteLabel),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    s.noteLabel,
                                    style: TextStyle(
                                      color: s.inTune
                                          ? t.ok
                                          : (s.cents.abs() <= 30
                                              ? t.warn
                                              : t.text),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 72,
                                      height: 1.0,
                                      letterSpacing: -2,
                                    ),
                                  ),
                                  // 音分数字: +23¢ 偏高(拧松) / -12¢ 偏低(拧紧) / ±0¢ 调准
                                  Text(
                                    _centsLabel(s),
                                    key: const Key('cents_display'),
                                    style: TextStyle(
                                      color: _centsColor(s, t),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : SizedBox(
                                key: const ValueKey('empty'),
                                width: 1,
                                height: 72,
                              ),
                      ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const Spacer(),
            // 品牌字标（环底部缺口处）
            Text(
              'K I T H A R A',
              style: const TextStyle(
                fontFamily: 'Montserrat',
                color: Color(0xFF85868F),
                fontSize: 11,
                letterSpacing: 6,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            // 状态引导语（内联弦号胶囊, 参考药丸样式, 不遮挡环心）
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 弦号胶囊（2s 自动消失）
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.centerLeft,
                  child: _stringHint != null
                      ? Container(
                          key: const Key('string_hint_chip'),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: t.okSoft, // 淡绿底, 无描边（参考样式）
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            _stringHint!,
                            style: TextStyle(
                              color: t.ok,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                Flexible(
                  child: Text(
                    _guidance(s),
                    style: TextStyle(
                      color: s.inTune
                          ? t.ok
                          : (s.hasSignal && s.cents.abs() <= 30
                              ? t.warn
                              : t.text3),
                      fontSize: 15,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            // 弦条
            if (!isChromatic)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final st in s.mode.strings)
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          // 大命中区上不画墨水框: 水波纹/高亮透明, 只保留触觉反馈
                          splashColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                          hoverColor: Colors.transparent,
                          onTap: () {
                            widget.haptics?.selectionClick();
                            widget.controller.selectString(st.semitoneIndex);
                            widget.onSelectString?.call(st.semitoneIndex);
                            _showStringHint(st);
                          },
                          child: _StringBar(
                            key: Key('led_${st.name}'),
                            target: st,
                            t: t,
                            active: s.activeString?.semitoneIndex ==
                                st.semitoneIndex,
                            inTune: s.activeString?.semitoneIndex ==
                                    st.semitoneIndex &&
                                s.inTune,
                            tuned: s.tunedSemis.contains(st.semitoneIndex),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 选弦提示浮层：显示「6弦」2 秒后淡出（初学者辅助）
  void _showStringHint(StringTarget target) {
    final s = widget.controller.state;
    final idx = s.mode.semitones.indexOf(target.semitoneIndex);
    if (idx < 0) return;
    final stringNo = s.mode.semitones.length - idx;
    setState(() => _stringHint = '$stringNo弦');
    _stringHintTimer?.cancel();
    _stringHintTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _stringHint = null);
    });
  }

  /// 环心音分数字: ±0¢ 调准（绿）; 其余带符号（+偏高拧松 / -偏低拧紧）
  String _centsLabel(TunerState s) {
    if (s.inTune) return '±0¢';
    final v = s.cents;
    final sign = v > 0 ? '+' : (v < 0 ? '-' : '');
    return '$sign${v.abs().round()}¢';
  }

  /// 音分数字颜色: 调准绿 / 近（≤30¢）黄 / 远中性
  Color _centsColor(TunerState s, KitharaTheme t) {
    if (s.inTune) return t.ok;
    if (s.hasSignal && s.cents.abs() <= 30) return t.warn;
    return t.text2;
  }

  /// 状态引导语：告诉用户下一步做什么，替代"未检测到信号"。
  String _guidance(TunerState s) {
    // 大偏差（粘性锁下弦很松）: 按符号给方向——cents<0 音低拧紧, cents>0 音高拧松
    if (s.hasSignal && s.activeString != null && s.cents.abs() > 50) {
      final dir = s.cents < 0 ? '偏低' : '偏高';
      return '$dir ${s.cents.abs().round()}¢，向 ${s.activeString!.name} ${s.cents < 0 ? '拧紧' : '拧松'}…';
    }
    if (s.mode.semitones.isEmpty) {
      // 半音阶：无目标弦
      if (!s.hasSignal) return '拨响任意弦开始调音';
      if (s.inTune) return '✓ ${s.noteLabel} 已调准';
      // cents>0 = 检测音高于目标 = 偏高要拧松; cents<0 = 偏低要拧紧
      return s.cents > 15
          ? '偏高 ${s.cents.abs().round()}¢，向 ${s.noteLabel} 拧松'
          : (s.cents < -15
              ? '偏低 ${s.cents.abs().round()}¢，向 ${s.noteLabel} 拧紧'
              : '微调…');
    }
    final target = s.activeString;
    if (!s.hasSignal) {
      return target == null ? '拨响任意弦开始调音' : '拨响 ${target.name} 弦';
    }
    if (s.inTune && target != null) return '✓ ${target.name} 已调准';
    if (target == null) return '音高偏离各弦，继续调整';
    final centsPart = s.cents.abs().round();
    return s.cents > 8
        ? '偏高 $centsPart¢，向 ${target.name} 拧松…'
        : (s.cents < -8 ? '偏低 $centsPart¢，向 ${target.name} 拧紧…' : '微调…');
  }


  void _showSettingsDialog(BuildContext context) {
    final t = widget.theme;
    // 弹窗是 Navigator 独立 overlay route；开关值读 widget（父 setState
    // 已实时下行），StatefulBuilder 仅用于 onChanged 后刷新弹窗。
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: t.popBg,
        title: Text('设置', style: TextStyle(color: t.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 嘈杂模式实时诊断（真机排障: 打开设置即可读链路各层状态）
            if (widget.noisyMode && widget.controller.diagnostics.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(widget.controller.diagnostics,
                    key: const Key('noisy_diagnostics'),
                    style: TextStyle(color: t.text3, fontSize: 10)),
              ),
            // 嘈杂环境调音开关（2026-10 取代降噪三档）
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('嘈杂环境调音',
                          style: TextStyle(color: t.text, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text('自动对准拨弦瞬间，嘈杂环境推荐开启',
                          style: TextStyle(
                              color: t.text2.withOpacity(0.7), fontSize: 11)),
                    ],
                  ),
                ),
                Switch(
                  key: const Key('noisy_mode_switch'),
                  value: widget.noisyMode,
                  activeColor: t.ok,
                  onChanged: (v) {
                    widget.haptics?.selectionClick();
                    setDialogState(() {}); // 触发弹窗刷新（开关值在 widget 上）
                    widget.onNoisyModeChanged?.call(v);
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              widget.haptics?.selectionClick();
              Navigator.pop(ctx);
            },
            child: Text('关闭', style: TextStyle(color: t.text2)),
          ),
        ],
      ),
      ),
    );
  }

  void _showA4Dialog(BuildContext context, double current) {
    final t = widget.theme;
    var value = current;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: t.popBg,
          title: Text('参考音 A4', style: TextStyle(color: t.text)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${value.toStringAsFixed(1)} Hz',
                  style: TextStyle(
                    color: t.text,
                    fontSize: 24,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: t.accent,
                  inactiveTrackColor: t.surface3,
                  thumbColor: t.text,
                  overlayColor: t.accentSoft,
                ),
                child: Slider(
                  value: value,
                  min: 430,
                  max: 450,
                  divisions: 20,
                  label: value.toStringAsFixed(1),
                  onChanged: (v) => setState(() => value = v),
                ),
              ),
            ],
          ),
          actions: [
            // 主操作放左（用户要求），取消弱化居右
            TextButton(
              onPressed: () {
                widget.haptics?.selectionClick();
                widget.controller.setA4(value);
                Navigator.pop(ctx);
              },
              child: Text('确定', style: TextStyle(color: t.accent)),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                widget.haptics?.selectionClick();
                Navigator.pop(ctx);
              },
              child: Text('取消', style: TextStyle(color: t.text2)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StringBar extends StatelessWidget {
  const _StringBar({
    super.key,
    required this.target,
    required this.t,
    required this.active,
    required this.inTune,
    this.tuned = false,
  });

  final StringTarget target;
  final KitharaTheme t;
  final bool active;
  final bool inTune;

  /// 会话内已调准（持久淡绿, 不随信号消失）
  final bool tuned;

  @override
  Widget build(BuildContext context) {
    // LED 四态: inTune 亮绿+辉光 > tuned 持久淡绿 > selected accent+辉光 > 灰
    // 选中表达 = 横线本身变粗（10→18）+ 变色 + 辉光; 调准绿优先。
    final selected = active;
    final ledOk = selected && (inTune || tuned);
    final ledColor = inTune
        ? t.ok
        : (tuned
            ? t.ok.withValues(alpha: 0.45)
            : (selected ? (ledOk ? t.ok : t.accent) : t.surface3));
    final glowColor = ledOk ? t.ok : t.accent;
    final labelColor = inTune || tuned
        ? t.ok
        : (selected ? (ledOk ? t.ok : t.accent) : t.text3);
    // 命中区 ≥52px（无障碍标准）: 空白向上延伸, 内容 bottom 对齐视觉不变
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: selected ? 18 : 10,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.bottomCenter,
          decoration: BoxDecoration(
            color: ledColor,
            borderRadius: BorderRadius.circular(9),
            boxShadow: inTune
                ? [BoxShadow(color: t.ok.withValues(alpha: 0.45), blurRadius: 10)]
                : (tuned
                    ? [BoxShadow(color: t.ok.withValues(alpha: 0.18), blurRadius: 5)]
                    : (selected
                        ? [BoxShadow(color: glowColor.withValues(alpha: 0.35), blurRadius: 8)]
                        : null)),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          target.name,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: labelColor,
            fontSize: 12,
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: selected || inTune || tuned
                ? FontWeight.w600
                : FontWeight.w400,
          ),
        ),
        ],
      ),
    );
  }
}

# 吉他调音器实施计划（Part 4/4：Task 9-11 持久化 + 真机清单 + 交付）

> 接 Part 3。Global Constraints / Review Focus 见 Part 1，全局适用。

---

### Task 9: TunerSettings 持久化 + UI 接线

**Files:**
- Create: `lib/tuner/tuner_settings.dart`
- Test: `test/tuner/tuner_settings_test.dart`
- Modify: `lib/ui/tuner_screen.dart`（启动 load 恢复 + 切换时 save）

**Interfaces:**
- Consumes: `TuningMode`（Task 4）；`SharedPreferences`（flutter pub add shared_preferences）
- Produces（Task 7 UI 按此消费）:

```dart
// lib/tuner/tuner_settings.dart
class TunerSettings {
  /// 读取 {mode, a4}；mode 非法/缺失 → standard；a4 缺失 → 440.0；
  /// a4 clamp 到 [430, 450]
  static Future<({TuningMode mode, double a4})> load();
  /// setString('mode', mode.name) + setDouble('a4', a4)
  static Future<void> save(TuningMode mode, double a4);
}
```

- [ ] **Step 1: 写失败测试**（`SharedPreferences.setMockInitialValues()`）

```dart
// test/tuner/tuner_settings_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:guitar_tuner/tuner/tuner_settings.dart';
import 'package:guitar_tuner/tuner/tuning_modes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('空存储 → (standard, 440.0)', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await TunerSettings.load();
    expect(s.mode, TuningMode.standard);
    expect(s.a4, 440.0);
  });

  test('已存值 → 原样读回', () async {
    SharedPreferences.setMockInitialValues({'mode': 'dropD', 'a4': 430.0});
    final s = await TunerSettings.load();
    expect(s.mode, TuningMode.dropD);
    expect(s.a4, 430.0);
  });

  test('非法 mode 字符串 → standard', () async {
    SharedPreferences.setMockInitialValues({'mode': 'garbage'});
    final s = await TunerSettings.load();
    expect(s.mode, TuningMode.standard);
  });

  test('a4 超范围 clamp: 999→450, 100→430', () async {
    SharedPreferences.setMockInitialValues({'a4': 999.0});
    expect((await TunerSettings.load()).a4, 450.0);
    SharedPreferences.setMockInitialValues({'a4': 100.0});
    expect((await TunerSettings.load()).a4, 430.0);
  });

  test('save → load 往返一致', () async {
    SharedPreferences.setMockInitialValues({});
    await TunerSettings.save(TuningMode.openG, 442.0);
    final s = await TunerSettings.load();
    expect(s.mode, TuningMode.openG);
    expect(s.a4, 442.0);
  });
}
```

- [ ] **Step 2: 确认失败** — FAIL（tuner_settings.dart 不存在）

- [ ] **Step 3: 实现 `lib/tuner/tuner_settings.dart`**（按 Produces 规格；`flutter pub add shared_preferences`）

- [ ] **Step 4: 确认通过** — `flutter test test/tuner/tuner_settings_test.dart` PASS

- [ ] **Step 5: UI 接线** — tuner_screen initState：`TunerSettings.load().then((s) { controller.setMode(s.mode); controller.setA4(s.a4); })`；ModeSheet 选择回调与 A4 滑块回调里 `TunerSettings.save(mode, a4)`

- [ ] **Step 6: `flutter analyze` 零警告 + Commit**

```bash
git add -A && git commit -m "feat(settings): persist mode + A4 via SharedPreferences with clamping"
```

---

### Task 10: 真机验收清单（人工执行，AI 准备清单文件）

**说明**：本任务是**人工任务**——需要真机 + 真吉他，AI 执行者无法独立完成。AI 交付物 = 清单文件；人类拿真机逐条验收。

**Files:**
- Create: `docs/smoke-checklist.md`（下方 12 条拷入）

- [ ] **Step 1: 创建清单文件**（内容 = 下方 12 条，逐条带 checkbox）

**真机冒烟清单（12 条）：**

1. 冷启动：从点图标到指针可响应拨弦 ≤ 2s（观察项，超预期记录数值）
2. 逐弦调音：6 弦逐一拨 2-3 次，自动锁定每根弦，指针稳定无跳动，无八度错误（低音弦重点观察）
3. 单帧野值：正常调音中敲一下琴体/说话，指针不跳变后立即回位
4. Drop D：6 弦从 E2 连续滑低到 D2（82.41→73.42），显示音名跟手（E2→D#2→D2），锁定弦跟随切换，最终正确锁定 D2
5. Open D / Open G / DADGAD：各调一轮，弦定义正确
6. Chromatic：口哨/哼唱 100–1200Hz 范围，音名跟随正确
7. 参考音：每弦播放听感接近拨弦、2s 自动停；播放中 mic 检测不被参考音拉走（同弦频率一致时 cents≈0 附近）
8. 后台/前台：退后台 mic 停（系统麦克风指示灯灭），回前台自动恢复检测
9. 来电/音频焦点：来电后回 App 恢复检测
10. 权限拒绝→恢复：系统设置关麦权限→App 显示权限拒绝页→去设置授权→回 App 自动恢复
11. A4=430 校准：拨 A 弦（110Hz 物理）显示 ≈ +36¢（人工核对）
12. iPhone 静音键：静音键开启时参考音仍出声；Android/iOS 双平台全部 12 条通过

- [ ] **Step 2: Commit**

```bash
git add docs/smoke-checklist.md
git commit -m "docs: real-device smoke checklist (12 items)"
```

---

### Task 11: 打包交付（APK + iOS 侧载说明）

**Files:**
- Create: `docs/delivery.md`

**说明**：个人工具不上架商店。Android = release APK 直接安装（flutter 模板 release buildType 默认 debug signing，无需改 gradle）；iOS = Xcode 直装或 AltStore 侧载。

- [ ] **Step 1: 构建 Android release APK 并验证可安装**

```bash
flutter build apk --release
# 产物: build/app/outputs/flutter-apk/app-release.apk
# 安装: adb install app-release.apk（或拷到手机点开安装）
```

- [ ] **Step 2: 写 `docs/delivery.md`**，内容规格：
  - Android：上述构建命令 + 产物路径 + 安装方式
  - iOS：Xcode 直装流程（`flutter run --release` 或 Xcode 打开 ios/Runner.xcworkspace → 选个人 team → 直装真机；免费账号 7 天过期重签，付费 $99/年 90 天）；AltStore/Sideloadly 免 Xcode 侧载概述
  - 显示名设置：iOS Info.plist `CFBundleDisplayName = Guitar Tuner` + Android `android:label = Guitar Tuner`
  - 图标更换：可选，个人工具低优先级（flutter_launcher_icons 包如需）

- [ ] **Step 3: Commit**

```bash
git add docs/delivery.md
git commit -m "docs: delivery notes (apk + ios sideload)"
```

---

## 计划自查记录（Self-Review，2026-10-28）

1. **Spec 覆盖**：§2 选型→T1/T5/T7/T9 pubspec；§3 架构→T4/T5/T6；§4 MPM 全参数→T3；§5 UI/交互→T7/T8/T9；§6 错误处理→T8+清单 8/9/10；§7 模式表→T4 规格含六模式全频率；§8 结构→各任务 Files；§9 测试策略→T2/T3/T4/T5/T6/T9（UI 冒烟按决策记录跳过）；§10 里程碑 M1=T2/T3、M2=T5/T6、M3=T7、M4=T8/T9、M5=T10/T11。**无缺口**。
2. **占位符扫描**：四份文件无 TBD/TODO/占位步骤；所有 code steps 含完整代码或文字规格+验收标准。
3. **类型一致性**：`NoteMapper`/`PitchDetector.detect→double?`/`TunerController.onPitch(double?)`/`RingBuffer.readWindow(4096)→Float32List?`/`TunerPipeline.addChunk(Float32List)`/`TunerSettings.load→({TuningMode,double})` 签名跨任务一致（onPitch 修正已传播到 T6 测试与规格）。
4. **Review Focus 五条**：430Hz→T2；73.42Hz→T3 场景2；野值→T4 规格6；交界粘滞→T2+T4；权限恢复→T8+清单10。

## 执行顺序与依赖

```
T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8 → T9 → T10(人工) → T11
```

严格线性依赖（T4 消费 T2/T3 接口；T6 消费 T3/T4/T5；T7 消费 T4/T5/T6）。T10 需要真机由人类执行；T11 的 iOS 构建需 macOS+Xcode（Windows 环境只做 Android APK + 文档）。

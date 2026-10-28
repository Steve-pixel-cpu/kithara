import 'package:flutter_test/flutter_test.dart';
import 'package:kithara/tuner/tuner_controller.dart';
import 'package:kithara/tuner/tuner_settings.dart';
import 'package:kithara/tuner/tuning_modes.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('保存/加载 roundtrip: modeId + a4', () async {
    SharedPreferences.setMockInitialValues({});
    final store = TunerSettings();
    await store.save('drop_d', 442.0);

    final loaded = await TunerSettings.load();
    expect(loaded.modeId, 'drop_d');
    expect(loaded.a4, 442.0);
  });

  test('首次启动无存储 → 默认 standard/440', () async {
    SharedPreferences.setMockInitialValues({});
    final loaded = await TunerSettings.load();
    expect(loaded.modeId, 'standard');
    expect(loaded.a4, 440.0);
  });

  test('controller 变更 → apply 到 controller 生效', () async {
    SharedPreferences.setMockInitialValues({'modeId': 'drop_d', 'a4': 442.0});
    final saved = await TunerSettings.load();
    final controller = TunerController();
    controller.setMode(TuningModes.byId(saved.modeId));
    controller.setA4(saved.a4);
    expect(controller.state.mode.id, 'drop_d');
    expect(controller.state.a4, 442.0);
  });

  test('非法存储值回退默认', () async {
    SharedPreferences.setMockInitialValues({'modeId': 'bogus', 'a4': 99999.0});
    final loaded = await TunerSettings.load();
    expect(loaded.modeId, 'standard');
    expect(loaded.a4, 440.0);
  });
}

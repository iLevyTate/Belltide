import 'package:material_ui/material_ui.dart';

import 'src/app.dart';
import 'src/data/key_value_store.dart';
import 'src/data/repositories.dart';
import 'src/engine/platform_timer_engine.dart';
import 'src/state/belltide_controller.dart';
import 'src/util/clock.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final clock = MonotonicClock();
  final store = SharedPreferencesStore();
  final controller = BelltideController(
    engine: PlatformTimerEngine(clock: clock),
    presets: PresetRepository(store),
    settings: SettingsRepository(store),
    clock: clock,
  );
  runApp(BelltideApp(controller: controller));
  controller.load();
}

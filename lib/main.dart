import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'src/app.dart';
import 'src/clickup/clickup_bridge.dart';
import 'src/clickup/clickup_controller.dart';
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
  final clickUp = ClickUpController(bridge: PlatformClickUpBridge(), store: store);
  // Keep linked task names current when ClickUp reports changes.
  clickUp.onLinkedTasksFetched = (tasks) => controller.applyTaskUpdates({
    for (final entry in tasks.entries) entry.key: entry.value.toLink(),
  });

  runApp(BelltideApp(controller: controller, clickUp: clickUp));
  unawaited(_load(controller, clickUp));
}

Future<void> _load(BelltideController controller, ClickUpController clickUp) async {
  await Future.wait([controller.load(), clickUp.load()]);
  if (!clickUp.connected) return;
  await clickUp.refreshLinked(controller.presets.map((p) => p.task).nonNulls);
  if (clickUp.syncStatus.pending > 0) await clickUp.syncNow();
}

import 'dart:async';

import 'package:belltide/src/clickup/clickup_controller.dart';
import 'package:belltide/src/data/key_value_store.dart';
import 'package:belltide/src/data/repositories.dart';
import 'package:belltide/src/engine/timer_engine.dart';
import 'package:belltide/src/model/app_settings.dart';
import 'package:belltide/src/model/audio_status.dart';
import 'package:belltide/src/model/chime_sound.dart';
import 'package:belltide/src/model/running_timer.dart';
import 'package:belltide/src/model/timer_preset.dart';
import 'package:belltide/src/state/belltide_controller.dart';
import 'package:belltide/src/util/clock.dart';

import 'clickup_fakes.dart';

/// A clock tests can move by hand.
class FakeClock implements MonotonicClock {
  Duration current = const Duration(seconds: 100);

  @override
  Duration now() => current;

  void advance(Duration d) => current += d;
}

/// Records calls and lets tests push engine states.
class FakeEngine implements TimerEngine {
  final StreamController<EngineState> _states = StreamController<EngineState>.broadcast();
  final List<String> calls = [];
  final List<TimerPreset> started = [];
  final List<ChimeSound> previewed = [];
  AppSettings? appliedSettings;
  bool notificationsGranted = false;
  bool grantOnRequest = true;
  bool batteryUnrestricted = false;
  AudioStatus audio = const AudioStatus(volume: 4, maxVolume: 7, ringer: RingerMode.normal);
  final StreamController<void> _audioChanges = StreamController<void>.broadcast();

  /// Changes what the phone reports and tells listeners, like a volume button press.
  void setAudio(AudioStatus status) {
    audio = status;
    _audioChanges.add(null);
  }

  @override
  Stream<EngineState> get states => _states.stream;

  void emit(EngineState state) => _states.add(state);

  @override
  Future<void> start(TimerPreset preset) async {
    calls.add('start:${preset.id}');
    started.add(preset);
  }

  @override
  Future<void> pause(String id) async => calls.add('pause:$id');

  @override
  Future<void> resume(String id) async => calls.add('resume:$id');

  @override
  Future<void> skip(String id) async => calls.add('skip:$id');

  @override
  Future<void> stop(String id) async => calls.add('stop:$id');

  @override
  Future<void> stopAll() async => calls.add('stopAll');

  @override
  Future<void> previewSound(ChimeSound sound) async => previewed.add(sound);

  @override
  Future<void> applySettings(AppSettings settings) async => appliedSettings = settings;

  @override
  Future<AudioStatus> audioStatus() async => audio;

  @override
  Stream<void> get audioChanges => _audioChanges.stream;

  @override
  Future<void> openVolumeSettings() async => calls.add('openVolumeSettings');

  @override
  Future<bool> notificationsAllowed() async => notificationsGranted;

  @override
  Future<bool> requestNotificationPermission() async {
    calls.add('requestNotifications');
    notificationsGranted = grantOnRequest;
    return notificationsGranted;
  }

  @override
  Future<void> openNotificationSettings() async => calls.add('openNotificationSettings');

  @override
  Future<bool> isIgnoringBatteryOptimizations() async => batteryUnrestricted;

  @override
  Future<void> openBatterySettings() async => calls.add('openBatterySettings');
}

/// A deterministic id generator: id-1, id-2, ...
String Function() sequentialIds() {
  var n = 0;
  return () => 'id-${++n}';
}

class Harness {
  Harness({Map<String, String>? stored})
    : store = MemoryStore(stored),
      engine = FakeEngine(),
      clock = FakeClock(),
      server = FakeClickUpServer(),
      bridge = FakeClickUpBridge() {
    controller = BelltideController(
      engine: engine,
      presets: PresetRepository(store),
      settings: SettingsRepository(store),
      clock: clock,
      idGenerator: sequentialIds(),
    );
    clickUp = ClickUpController(bridge: bridge, store: store, apiFactory: server.api);
  }

  final MemoryStore store;
  final FakeEngine engine;
  final FakeClock clock;
  final FakeClickUpServer server;
  final FakeClickUpBridge bridge;
  late final BelltideController controller;
  late final ClickUpController clickUp;

  /// Loads everything, optionally with ClickUp already connected.
  Future<void> load({bool connectClickUp = false}) async {
    await controller.load();
    await clickUp.load();
    if (connectClickUp) await clickUp.connect(server.validToken);
  }
}

RunningTimer runningTimer({
  required String id,
  String name = 'Timer',
  TimerKind kind = TimerKind.sequence,
  bool paused = false,
  bool inLeadIn = false,
  int stepIndex = 0,
  int stepCount = 2,
  String stepLabel = 'Hold',
  int round = 1,
  int rounds = 10,
  Duration stepDuration = const Duration(seconds: 10),
  Duration stepRemaining = const Duration(seconds: 7),
  Duration? totalRemaining = const Duration(minutes: 6),
  Duration receivedAt = const Duration(seconds: 100),
}) {
  return RunningTimer(
    id: id,
    name: name,
    kind: kind,
    paused: paused,
    inLeadIn: inLeadIn,
    stepIndex: stepIndex,
    stepCount: stepCount,
    stepLabel: stepLabel,
    round: round,
    rounds: rounds,
    stepDuration: stepDuration,
    stepRemaining: stepRemaining,
    totalRemaining: totalRemaining,
    receivedAt: receivedAt,
  );
}

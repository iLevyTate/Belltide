import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories.dart';
import '../data/sample_presets.dart';
import '../engine/timer_engine.dart';
import '../model/app_settings.dart';
import '../model/chime_sound.dart';
import '../model/running_timer.dart';
import '../model/task_link.dart';
import '../model/timer_preset.dart';
import '../util/clock.dart';
import '../util/ids.dart';

/// App state: saved timers, what the engine is running, and settings.
class BelltideController extends ChangeNotifier {
  BelltideController({
    required this._engine,
    required PresetRepository presets,
    required SettingsRepository settings,
    MonotonicClock? clock,
    String Function() idGenerator = newId,
  }) : _presetRepo = presets,
       _settingsRepo = settings,
       clock = clock ?? MonotonicClock(),
       _newId = idGenerator;

  /// How long a switch keeps showing the user's choice while the service catches up.
  static const Duration pendingWindow = Duration(seconds: 3);

  final TimerEngine _engine;
  final PresetRepository _presetRepo;
  final SettingsRepository _settingsRepo;
  final String Function() _newId;

  /// Shared with the UI so countdowns use the same clock as engine snapshots.
  final MonotonicClock clock;

  StreamSubscription<EngineState>? _subscription;
  final StreamController<String> _finished = StreamController<String>.broadcast();

  List<TimerPreset> _presets = const [];
  Map<String, RunningTimer> _running = const {};
  final Map<String, _Pending> _pending = {};
  AppSettings _settings = const AppSettings();
  bool _loaded = false;
  bool _askedForNotifications = false;

  bool get loaded => _loaded;
  List<TimerPreset> get presets => List.unmodifiable(_presets);
  AppSettings get settings => _settings;

  /// Display names of timers as they finish all their rounds.
  Stream<String> get finishedTimers => _finished.stream;

  TimerEngine get engine => _engine;

  Future<void> load() async {
    final stored = await _presetRepo.load();
    if (stored == null) {
      _presets = samplePresets(id: _newId);
      await _presetRepo.save(_presets);
    } else {
      _presets = stored;
    }
    _settings = await _settingsRepo.load();
    _loaded = true;
    notifyListeners();

    _subscription = _engine.states.listen(_onEngineState, onError: (Object e) {
      debugPrint('Belltide: engine state error: $e');
    });
    await _guard(() => _engine.applySettings(_settings));
  }

  TimerPreset? presetById(String id) {
    for (final p in _presets) {
      if (p.id == id) return p;
    }
    return null;
  }

  RunningTimer? runningTimer(String id) => _running[id];

  bool get anyRunning => _running.isNotEmpty;

  /// Whether a timer's switch should show as on.
  bool isOn(String id) {
    final pending = _pending[id];
    if (pending != null && clock.now() < pending.until) return pending.wantOn;
    return _running.containsKey(id);
  }

  void _onEngineState(EngineState state) {
    _running = {for (final t in state.timers) t.id: t};
    _pending.removeWhere(
      (id, p) => clock.now() >= p.until || _running.containsKey(id) == p.wantOn,
    );
    for (final id in state.finished) {
      final preset = presetById(id);
      if (preset != null) _finished.add(preset.displayName);
    }
    notifyListeners();
  }

  void _setPending(String id, bool wantOn) {
    _pending[id] = _Pending(wantOn, clock.now() + pendingWindow);
    notifyListeners();
  }

  Future<void> setRunning(TimerPreset preset, bool on) => on ? start(preset) : stop(preset.id);

  Future<void> start(TimerPreset preset) async {
    if (preset.validate() != null) return;
    _setPending(preset.id, true);
    if (!_askedForNotifications) {
      _askedForNotifications = true;
      // Timers ring either way; the notification adds lock-screen controls.
      await _guard(() async {
        if (!await _engine.notificationsAllowed()) {
          await _engine.requestNotificationPermission();
        }
      });
    }
    await _guard(() => _engine.start(preset));
  }

  Future<void> stop(String id) async {
    _setPending(id, false);
    await _guard(() => _engine.stop(id));
  }

  Future<void> pause(String id) => _guard(() => _engine.pause(id));

  Future<void> resume(String id) => _guard(() => _engine.resume(id));

  Future<void> skip(String id) => _guard(() => _engine.skip(id));

  Future<void> preview(ChimeSound sound) => _guard(() => _engine.previewSound(sound));

  /// A blank timer of [kind] for the editor. It is not saved until [savePreset].
  TimerPreset draft(TimerKind kind) {
    final id = _newId();
    if (kind == TimerKind.interval) {
      return TimerPreset.interval(
        id: id,
        name: '',
        every: const Duration(minutes: 5),
        sound: ChimeSound.bell,
      );
    }
    return TimerPreset(
      id: id,
      name: '',
      kind: TimerKind.sequence,
      steps: [
        TimerStep(id: _newId(), label: 'Hold', duration: const Duration(seconds: 10), sound: ChimeSound.bell),
        TimerStep(id: _newId(), label: 'Rest', duration: const Duration(seconds: 30), sound: ChimeSound.wood),
      ],
      rounds: 10,
      leadIn: const Duration(seconds: 5),
      startChime: true,
      finishSound: ChimeSound.rise,
    );
  }

  String newStepId() => _newId();

  /// Adds [preset], or replaces the saved timer with the same id.
  Future<void> savePreset(TimerPreset preset) async {
    final index = _presets.indexWhere((p) => p.id == preset.id);
    final next = [..._presets];
    if (index < 0) {
      next.add(preset);
    } else {
      next[index] = preset;
    }
    _presets = next;
    notifyListeners();
    await _presetRepo.save(_presets);
  }

  /// Removes a timer, stopping it first if it runs. Returns where it was, for undo.
  Future<int> deletePreset(String id) async {
    final index = _presets.indexWhere((p) => p.id == id);
    if (index < 0) return -1;
    if (isOn(id)) await stop(id);
    _presets = [..._presets]..removeAt(index);
    notifyListeners();
    await _presetRepo.save(_presets);
    return index;
  }

  /// Puts back a deleted timer at [index].
  Future<void> restorePreset(TimerPreset preset, int index) async {
    if (presetById(preset.id) != null) return;
    _presets = [..._presets]..insert(index.clamp(0, _presets.length), preset);
    notifyListeners();
    await _presetRepo.save(_presets);
  }

  Future<TimerPreset?> duplicatePreset(String id) async {
    final index = _presets.indexWhere((p) => p.id == id);
    if (index < 0) return null;
    final source = _presets[index];
    final copy = source.copyWith(
      id: _newId(),
      name: '${source.displayName} copy',
      steps: [for (final s in source.steps) TimerStep(id: _newId(), label: s.label, duration: s.duration, sound: s.sound)],
    );
    _presets = [..._presets]..insert(index + 1, copy);
    notifyListeners();
    await _presetRepo.save(_presets);
    return copy;
  }

  /// Saves a copy of [template] linked to [task], placed after the template.
  Future<TimerPreset> createLinkedCopy(TimerPreset template, TaskLink task) async {
    final copy = template.copyWith(
      id: _newId(),
      steps: [
        for (final s in template.steps)
          TimerStep(id: _newId(), label: s.label, duration: s.duration, sound: s.sound),
      ],
      task: task,
    );
    final index = _presets.indexWhere((p) => p.id == template.id);
    _presets = [..._presets]..insert(index < 0 ? _presets.length : index + 1, copy);
    notifyListeners();
    await _presetRepo.save(_presets);
    return copy;
  }

  /// Timers linked to the ClickUp task with [taskId].
  List<TimerPreset> presetsForTask(String taskId) =>
      _presets.where((p) => p.task?.taskId == taskId).toList();

  /// Keeps linked task names and links current after ClickUp reports changes.
  Future<void> applyTaskUpdates(Map<String, TaskLink> latest) async {
    var changed = false;
    final next = [
      for (final p in _presets)
        if (p.task case final link? when latest.containsKey(link.taskId))
          () {
            final fresh = latest[link.taskId]!;
            final updated = link.copyWith(name: fresh.name, url: fresh.url, customId: fresh.customId);
            if (updated == link) return p;
            changed = true;
            return p.copyWith(task: updated);
          }()
        else
          p,
    ];
    if (!changed) return;
    _presets = next;
    notifyListeners();
    await _presetRepo.save(_presets);
  }

  Future<void> updateSettings(AppSettings settings) async {
    if (settings == _settings) return;
    _settings = settings;
    notifyListeners();
    await _settingsRepo.save(settings);
    await _guard(() => _engine.applySettings(settings));
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('Belltide: engine call failed: $e');
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _finished.close();
    super.dispose();
  }
}

class _Pending {
  const _Pending(this.wantOn, this.until);

  final bool wantOn;
  final Duration until;
}

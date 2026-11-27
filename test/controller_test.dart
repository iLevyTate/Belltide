import 'dart:convert';

import 'package:belltide/src/data/repositories.dart';
import 'package:belltide/src/model/app_settings.dart';
import 'package:belltide/src/model/chime_sound.dart';
import 'package:belltide/src/model/running_timer.dart';
import 'package:belltide/src/model/timer_preset.dart';
import 'package:belltide/src/state/belltide_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  test('first launch adds and saves the sample timers', () async {
    final h = Harness();
    await h.controller.load();
    expect(h.controller.loaded, isTrue);
    expect(h.controller.presets.map((p) => p.name), ['Mindful bell', 'Stretch holds', 'Work and rest']);
    expect(h.store.values[PresetRepository.key], isNotNull);
    expect(h.engine.appliedSettings, const AppSettings());
  });

  test('later launches keep what the user saved, even an empty list', () async {
    final h = Harness(stored: {PresetRepository.key: jsonEncode({'version': 1, 'presets': []})});
    await h.controller.load();
    expect(h.controller.presets, isEmpty);
  });

  test('unreadable storage does not crash loading', () async {
    final h = Harness(stored: {PresetRepository.key: '{not json'});
    await h.controller.load();
    expect(h.controller.presets, isEmpty);
  });

  test('start asks for notifications once, then starts the engine', () async {
    final h = Harness();
    await h.controller.load();
    final p = h.controller.presets.first;
    await h.controller.start(p);
    await h.controller.start(p);
    expect(h.engine.calls.where((c) => c == 'requestNotifications'), hasLength(1));
    expect(h.engine.started.map((s) => s.id), [p.id, p.id]);
  });

  test('start skips the permission prompt when already allowed', () async {
    final h = Harness()..engine.notificationsGranted = true;
    await h.controller.load();
    await h.controller.start(h.controller.presets.first);
    expect(h.engine.calls, isNot(contains('requestNotifications')));
  });

  test('switch shows the requested state until the engine catches up', () async {
    final h = Harness()..engine.notificationsGranted = true;
    await h.controller.load();
    final p = h.controller.presets.first;

    await h.controller.start(p);
    expect(h.controller.isOn(p.id), isTrue);

    // An update that predates the start must not flip the switch back off.
    h.engine.emit(EngineState.empty);
    await pumpEventQueue();
    expect(h.controller.isOn(p.id), isTrue);

    h.engine.emit(EngineState(timers: [runningTimer(id: p.id)]));
    await pumpEventQueue();
    expect(h.controller.runningTimer(p.id), isNotNull);

    await h.controller.stop(p.id);
    expect(h.controller.isOn(p.id), isFalse);
    expect(h.engine.calls.last, 'stop:${p.id}');
  });

  test('a start the engine never confirms falls back after the pending window', () async {
    final h = Harness()..engine.notificationsGranted = true;
    await h.controller.load();
    final p = h.controller.presets.first;
    await h.controller.start(p);
    h.clock.advance(BelltideController.pendingWindow);
    expect(h.controller.isOn(p.id), isFalse);
  });

  test('invalid timers are not started', () async {
    final h = Harness();
    await h.controller.load();
    await h.controller.start(h.controller.presets.first.copyWith(steps: []));
    expect(h.engine.started, isEmpty);
  });

  test('finished timers are announced by name', () async {
    final h = Harness();
    await h.controller.load();
    final p = h.controller.presets[1];
    final names = <String>[];
    h.controller.finishedTimers.listen(names.add);
    h.engine.emit(EngineState(finished: [p.id, 'unknown']));
    await pumpEventQueue();
    expect(names, ['Stretch holds']);
  });

  test('controls forward to the engine', () async {
    final h = Harness();
    await h.controller.load();
    await h.controller.pause('a');
    await h.controller.resume('a');
    await h.controller.skip('a');
    await h.controller.preview(ChimeSound.gong);
    expect(h.engine.calls, ['pause:a', 'resume:a', 'skip:a']);
    expect(h.engine.previewed, [ChimeSound.gong]);
  });

  test('save adds new timers and replaces existing ones', () async {
    final h = Harness();
    await h.controller.load();
    final draft = h.controller.draft(TimerKind.interval).copyWith(name: 'Water');
    await h.controller.savePreset(draft);
    expect(h.controller.presets.last.name, 'Water');

    await h.controller.savePreset(draft.copyWith(name: 'Drink water'));
    expect(h.controller.presets.where((p) => p.id == draft.id).single.name, 'Drink water');

    final reloaded = await PresetRepository(h.store).load();
    expect(reloaded!.last.name, 'Drink water');
  });

  test('delete stops a running timer and can be undone in place', () async {
    final h = Harness()..engine.notificationsGranted = true;
    await h.controller.load();
    final p = h.controller.presets[1];
    h.engine.emit(EngineState(timers: [runningTimer(id: p.id)]));
    await pumpEventQueue();

    final index = await h.controller.deletePreset(p.id);
    expect(index, 1);
    expect(h.engine.calls, contains('stop:${p.id}'));
    expect(h.controller.presetById(p.id), isNull);

    await h.controller.restorePreset(p, index);
    expect(h.controller.presets[1].id, p.id);
  });

  test('duplicate inserts a copy with fresh ids after the original', () async {
    final h = Harness();
    await h.controller.load();
    final original = h.controller.presets[1];
    final copy = await h.controller.duplicatePreset(original.id);
    expect(copy, isNotNull);
    expect(h.controller.presets[2].id, copy!.id);
    expect(copy.name, 'Stretch holds copy');
    expect(copy.id, isNot(original.id));
    expect(copy.steps.map((s) => s.id).toSet().intersection(original.steps.map((s) => s.id).toSet()), isEmpty);
  });

  test('settings are saved and pushed to the engine', () async {
    final h = Harness();
    await h.controller.load();
    const next = AppSettings(volume: ChimeVolume.media, vibrate: true);
    await h.controller.updateSettings(next);
    expect(h.engine.appliedSettings, next);
    expect(await SettingsRepository(h.store).load(), next);
  });

  test('drafts are valid and use fresh ids', () async {
    final h = Harness();
    await h.controller.load();
    final interval = h.controller.draft(TimerKind.interval);
    final sequence = h.controller.draft(TimerKind.sequence);
    expect(interval.validate(), isNull);
    expect(sequence.validate(), isNull);
    expect(interval.id, isNot(sequence.id));
    expect(sequence.steps, hasLength(2));
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:belltide/src/model/app_settings.dart';
import 'package:belltide/src/model/chime_sound.dart';
import 'package:belltide/src/model/running_timer.dart';
import 'package:belltide/src/model/timer_preset.dart';
import 'package:flutter_test/flutter_test.dart';

TimerPreset stretchHolds() => const TimerPreset(
  id: 'stretch-holds',
  name: 'Stretch holds',
  kind: TimerKind.sequence,
  steps: [
    TimerStep(id: 's1', label: 'Hold', duration: Duration(seconds: 10), sound: ChimeSound.bell),
    TimerStep(id: 's2', label: 'Rest', duration: Duration(seconds: 30), sound: ChimeSound.wood),
  ],
  rounds: 10,
  leadIn: Duration(seconds: 5),
  startChime: true,
  finishSound: ChimeSound.rise,
);

void main() {
  group('ChimeSound', () {
    test('looks sounds up by id with a fallback', () {
      expect(ChimeSound.fromId('double'), ChimeSound.doubleBell);
      expect(ChimeSound.fromId('nope'), ChimeSound.bell);
      expect(ChimeSound.fromId(null, fallback: ChimeSound.none), ChimeSound.none);
    });

    test('audible list excludes silence', () {
      expect(ChimeSound.audible, isNot(contains(ChimeSound.none)));
      expect(ChimeSound.audible, hasLength(ChimeSound.values.length - 1));
    });
  });

  group('TimerPreset', () {
    test('computes cycle and total including the lead-in', () {
      final p = stretchHolds();
      expect(p.cycle, const Duration(seconds: 40));
      expect(p.total, const Duration(seconds: 405));
      expect(p.copyWith(rounds: 0).total, isNull);
    });

    test('round-trips through JSON', () {
      final p = stretchHolds();
      final decoded = TimerPreset.fromJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, Object?>);
      expect(decoded, p);
      expect(decoded.steps[1].sound, ChimeSound.wood);
    });

    test('engine JSON matches the shared wire-format fixture', () {
      final fixture = jsonDecode(File('test/fixtures/engine_config.json').readAsStringSync());
      expect(jsonDecode(jsonEncode(stretchHolds().toEngineJson())), fixture);
    });

    test('interval engine JSON finishes on its own chime and ignores lead-in', () {
      final p = TimerPreset.interval(
        id: 'i',
        name: 'Bell',
        every: const Duration(minutes: 5),
        sound: ChimeSound.bowl,
        chimes: 12,
      ).copyWith(leadIn: const Duration(seconds: 10), finishSound: ChimeSound.gong);
      final json = p.toEngineJson();
      expect(json['kind'], 'interval');
      expect(json['finishSound'], 'bowl');
      expect(json['leadInMs'], 0);
      expect(json['rounds'], 12);
      expect((json['steps'] as List).single, {'label': 'Interval', 'durationMs': 300000, 'sound': 'bowl'});
    });

    test('engine JSON fills in blank names and labels', () {
      final p = stretchHolds().copyWith(
        name: '  ',
        steps: [stretchHolds().steps.first.copyWith(label: '')],
      );
      final json = p.toEngineJson();
      expect(json['name'], 'Untitled timer');
      expect((json['steps'] as List).single['label'], 'Step');
    });

    test('validates step lengths and rounds', () {
      expect(stretchHolds().validate(), isNull);
      expect(stretchHolds().copyWith(steps: []).validate(), isNotNull);
      final tooShort = stretchHolds().copyWith(
        steps: [stretchHolds().steps.first.copyWith(duration: const Duration(milliseconds: 500))],
      );
      expect(tooShort.validate(), contains('at least 1 second'));
      expect(stretchHolds().copyWith(rounds: 1000).validate(), isNotNull);
    });

    test('reads older or partial JSON with defaults', () {
      final p = TimerPreset.fromJson({
        'id': 'x',
        'steps': [
          {'durationMs': 1000},
        ],
      });
      expect(p.kind, TimerKind.sequence);
      expect(p.rounds, 0);
      expect(p.finishSound, ChimeSound.none);
      expect(p.steps.single.sound, ChimeSound.bell);
    });
  });

  group('RunningTimer', () {
    final state = EngineState.fromJson(
      File('test/fixtures/engine_state.json').readAsStringSync(),
      const Duration(seconds: 50),
    );
    final timer = state.timers.single;

    test('parses the shared wire-format fixture', () {
      expect(timer.id, 'stretch-holds');
      expect(timer.paused, isFalse);
      expect(timer.stepLabel, 'Rest');
      expect(timer.stepIndex, 1);
      expect(timer.round, 1);
      expect(timer.rounds, 10);
      expect(timer.stepRemaining, const Duration(seconds: 28));
      expect(timer.totalRemaining, const Duration(seconds: 388));
      expect(state.finished, isEmpty);
    });

    test('counts down locally between updates', () {
      const later = Duration(seconds: 53);
      expect(timer.stepRemainingAt(later), const Duration(seconds: 25));
      expect(timer.totalRemainingAt(later), const Duration(seconds: 385));
      expect(timer.stepProgressAt(later), closeTo(5 / 30, 1e-9));
      expect(timer.stepRemainingAt(const Duration(hours: 1)), Duration.zero);
    });

    test('does not count down while paused', () {
      final paused = EngineState.fromJson(
        '{"timers":[{"id":"a","status":"paused","stepRemainingMs":4000,"stepDurationMs":10000,"totalRemainingMs":-1}]}',
        Duration.zero,
      ).timers.single;
      expect(paused.paused, isTrue);
      expect(paused.stepRemainingAt(const Duration(minutes: 5)), const Duration(seconds: 4));
      expect(paused.totalRemaining, isNull);
    });
  });

  test('AppSettings round-trips and defaults to the alarm stream', () {
    const settings = AppSettings(volume: ChimeVolume.media, vibrate: true);
    expect(AppSettings.fromJson(settings.toJson()), settings);
    expect(AppSettings.fromJson(const {}), const AppSettings());
    expect(const AppSettings().volume, ChimeVolume.alarm);
  });
}

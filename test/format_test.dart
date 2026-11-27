import 'package:belltide/src/model/chime_sound.dart';
import 'package:belltide/src/model/timer_preset.dart';
import 'package:belltide/src/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatClock rounds up to whole seconds', () {
    expect(formatClock(Duration.zero), '0:00');
    expect(formatClock(const Duration(milliseconds: 1)), '0:01');
    expect(formatClock(const Duration(milliseconds: 6200)), '0:07');
    expect(formatClock(const Duration(seconds: 7)), '0:07');
    expect(formatClock(const Duration(minutes: 12)), '12:00');
    expect(formatClock(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    expect(formatClock(const Duration(seconds: -5)), '0:00');
  });

  test('formatSpan reads naturally', () {
    expect(formatSpan(const Duration(seconds: 10)), '10 s');
    expect(formatSpan(const Duration(minutes: 5)), '5 min');
    expect(formatSpan(const Duration(seconds: 90)), '1 min 30 s');
    expect(formatSpan(const Duration(hours: 1, minutes: 5)), '1 h 5 min');
    expect(formatSpan(Duration.zero), '0 s');
  });

  group('summaries', () {
    final interval = TimerPreset.interval(
      id: 'a',
      name: 'Bell',
      every: const Duration(minutes: 5),
      sound: ChimeSound.bowl,
    );

    test('interval', () {
      expect(presetSummary(interval), 'Every 5 min · Singing bowl');
      expect(presetDetail(interval), 'Repeats until stopped');
      expect(presetDetail(interval.copyWith(rounds: 12)), '12 chimes · 1 h total');
      expect(presetDetail(interval.copyWith(rounds: 1)), '1 chime · 5 min total');
    });

    test('sequence lists the first steps', () {
      TimerStep step(String label, int seconds) =>
          TimerStep(id: label, label: label, duration: Duration(seconds: seconds), sound: ChimeSound.bell);
      final seq = TimerPreset(
        id: 'b',
        name: 'Seq',
        kind: TimerKind.sequence,
        steps: [step('Hold', 10), step('Rest', 30)],
        rounds: 10,
      );
      expect(presetSummary(seq), 'Hold 10 s · Rest 30 s');
      expect(presetDetail(seq), '10 rounds · 6 min 40 s total');

      final long = seq.copyWith(
        steps: [step('A', 1), step('B', 2), step('C', 3), step('D', 4), step('', 5)],
      );
      expect(presetSummary(long), 'A 1 s · B 2 s · C 3 s · +2 more');
    });
  });
}

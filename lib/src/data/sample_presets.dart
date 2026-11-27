import '../model/chime_sound.dart';
import '../model/timer_preset.dart';
import '../util/ids.dart';

/// Timers added on first launch, one for each kind of rhythm Belltide is for.
List<TimerPreset> samplePresets({String Function() id = newId}) {
  TimerStep step(String label, Duration duration, ChimeSound sound) =>
      TimerStep(id: id(), label: label, duration: duration, sound: sound);

  return [
    TimerPreset.interval(
      id: id(),
      name: 'Mindful bell',
      every: const Duration(minutes: 5),
      sound: ChimeSound.bowl,
    ),
    TimerPreset(
      id: id(),
      name: 'Stretch holds',
      kind: TimerKind.sequence,
      steps: [
        step('Hold', const Duration(seconds: 10), ChimeSound.bell),
        step('Rest', const Duration(seconds: 30), ChimeSound.wood),
      ],
      rounds: 10,
      leadIn: const Duration(seconds: 5),
      startChime: true,
      finishSound: ChimeSound.rise,
    ),
    TimerPreset(
      id: id(),
      name: 'Work and rest',
      kind: TimerKind.sequence,
      steps: [
        step('Work', const Duration(minutes: 50), ChimeSound.bell),
        step('Break', const Duration(minutes: 10), ChimeSound.doubleBell),
      ],
      startChime: true,
      finishSound: ChimeSound.gong,
    ),
  ];
}

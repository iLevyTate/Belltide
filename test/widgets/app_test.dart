import 'package:belltide/src/app.dart';
import 'package:belltide/src/model/app_settings.dart';
import 'package:belltide/src/model/audio_status.dart';
import 'package:belltide/src/model/chime_sound.dart';
import 'package:belltide/src/model/running_timer.dart';
import 'package:belltide/src/model/timer_preset.dart';
import 'package:belltide/src/ui/brand_mark.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fakes.dart';

Future<Harness> pumpApp(WidgetTester tester, {Harness? harness, bool connectClickUp = false}) async {
  final h = harness ?? Harness();
  h.engine.notificationsGranted = true;
  await h.load(connectClickUp: connectClickUp);
  await tester.pumpWidget(BelltideApp(controller: h.controller, clickUp: h.clickUp));
  await tester.pump();
  return h;
}

/// Lets route transitions finish without waiting on running tickers.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Opens Settings from the home screen.
Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Settings'));
  await settle(tester);
}

/// Scrolls the screen's list until [finder] is on screen.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
  await tester.pump();
}

void main() {
  testWidgets('home lists the sample timers with summaries', (tester) async {
    await pumpApp(tester);
    expect(find.text('Belltide'), findsOneWidget);
    expect(find.byType(BrandMark), findsOneWidget);
    expect(find.text('Mindful bell'), findsOneWidget);
    expect(find.text('Every 5 min · Singing bowl'), findsOneWidget);
    expect(find.text('Stretch holds'), findsOneWidget);
    expect(find.text('Hold 10 s · Rest 30 s'), findsOneWidget);
    expect(find.text('10 rounds · 6 min 45 s total'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(3));
  });

  testWidgets('turning a switch on starts that timer', (tester) async {
    final h = await pumpApp(tester);
    await tester.tap(find.byType(Switch).at(1));
    await tester.pump();
    expect(h.engine.started.single.name, 'Stretch holds');
    expect(tester.widget<Switch>(find.byType(Switch).at(1)).value, isTrue);
  });

  testWidgets('a running timer shows its step, countdown and controls', (tester) async {
    final h = await pumpApp(tester);
    final preset = h.controller.presets[1];
    h.engine.emit(
      EngineState(
        timers: [
          runningTimer(
            id: preset.id,
            stepLabel: 'Hold',
            stepRemaining: const Duration(seconds: 7),
            round: 2,
            rounds: 10,
            receivedAt: h.clock.now(),
          ),
        ],
      ),
    );
    await settle(tester);

    expect(find.text('Hold'), findsOneWidget);
    expect(find.text('0:07'), findsOneWidget);
    expect(find.text('Step 1 of 2 · Round 2 of 10'), findsOneWidget);
    expect(find.text('6:00 left'), findsOneWidget);

    // The countdown follows the monotonic clock between engine updates.
    h.clock.advance(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('0:05'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    expect(h.engine.calls, containsAll(['pause:${preset.id}', 'skip:${preset.id}']));

    // Stop the ticker before the test ends.
    h.engine.emit(EngineState.empty);
    await settle(tester);
  });

  testWidgets('a paused interval timer says so and offers resume', (tester) async {
    final h = await pumpApp(tester);
    final preset = h.controller.presets.first;
    h.engine.emit(
      EngineState(
        timers: [
          runningTimer(
            id: preset.id,
            kind: TimerKind.interval,
            paused: true,
            stepCount: 1,
            rounds: 0,
            stepDuration: const Duration(minutes: 5),
            stepRemaining: const Duration(minutes: 3, seconds: 12),
            totalRemaining: null,
          ),
        ],
      ),
    );
    await settle(tester);
    expect(find.text('Paused · Next chime in'), findsOneWidget);
    expect(find.text('3:12'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    expect(h.engine.calls.last, 'resume:${preset.id}');
  });

  testWidgets('finishing a timer shows a snackbar', (tester) async {
    final h = await pumpApp(tester);
    h.engine.emit(EngineState(finished: [h.controller.presets[1].id]));
    await tester.pump();
    await tester.pump();
    expect(find.text('Stretch holds finished'), findsOneWidget);
  });

  testWidgets('create an interval chime from the new timer sheet', (tester) async {
    final h = await pumpApp(tester);
    await tester.tap(find.text('New timer'));
    await settle(tester);
    await tester.tap(find.text('Interval chime'));
    await settle(tester);

    expect(find.text('New interval chime'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Water');
    await tester.tap(find.text('Repeat until stopped'));
    await tester.pump();
    expect(find.text('Number of chimes'), findsOneWidget);
    await tester.tap(find.byTooltip('More'));
    await tester.pump();

    await tester.tap(find.text('Save'));
    await settle(tester);

    final saved = h.controller.presets.last;
    expect(saved.name, 'Water');
    expect(saved.isInterval, isTrue);
    expect(saved.rounds, 13);
    expect(find.text('Water'), findsOneWidget);
  });

  testWidgets('build a sequence with an extra step', (tester) async {
    final h = await pumpApp(tester);
    await tester.tap(find.text('New timer'));
    await settle(tester);
    await tester.tap(find.text('Sequence'));
    await settle(tester);

    await tester.enterText(find.byType(TextField).first, 'Physio');
    await tester.tap(find.text('Add step'));
    await tester.pump();
    expect(find.text('Step 3'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await settle(tester);

    final saved = h.controller.presets.last;
    expect(saved.name, 'Physio');
    expect(saved.steps.map((s) => s.label), ['Hold', 'Rest', 'Step 3']);
    expect(saved.steps[2].sound.id, 'chime');
  });

  testWidgets('leaving the editor with changes asks first', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Stretch holds'));
    await settle(tester);
    expect(find.text('Edit timer'), findsOneWidget);

    // Editing only a step label still counts as a change.
    await tester.enterText(find.byType(TextField).at(1), 'Hold longer');
    await tester.pump();
    await tester.pageBack();
    await settle(tester);
    expect(find.text('Discard changes?'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await settle(tester);
    expect(find.text('Edit timer'), findsNothing);
    expect(find.text('Stretch holds'), findsOneWidget);
  });

  testWidgets('delete from the menu can be undone', (tester) async {
    final h = await pumpApp(tester);
    await tester.tap(find.byTooltip('More for Mindful bell'));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(find.text('Mindful bell'), findsNothing);
    expect(h.controller.presets, hasLength(2));

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(h.controller.presets.first.name, 'Mindful bell');
  });

  testWidgets('settings change the chime volume and vibration', (tester) async {
    final h = await pumpApp(tester);
    await openSettings(tester);

    await reveal(tester, find.text('Media volume'));
    await tester.tap(find.text('Media volume'));
    await tester.pump();
    await reveal(tester, find.text('Vibrate with each chime'));
    await tester.tap(find.text('Vibrate with each chime'));
    await tester.pump();
    await reveal(tester, find.text('Battery optimization'));
    expect(find.text('Battery optimization'), findsOneWidget);

    expect(h.controller.settings.volume.name, 'media');
    expect(h.controller.settings.vibrate, isTrue);
    expect(h.engine.appliedSettings?.vibrate, isTrue);
  });

  testWidgets('the chime volume slider sets the level and plays a bell', (tester) async {
    final h = await pumpApp(tester);
    await openSettings(tester);
    expect(find.text('100%'), findsOneWidget);

    await tester.drag(find.byType(Slider), const Offset(-150, 0));
    await settle(tester);

    final level = h.controller.settings.level;
    expect(level, inExclusiveRange(0, 1));
    expect(h.engine.appliedSettings?.level, level);
    expect(h.engine.previewed, [ChimeSound.bell]);
    expect(find.text('${(level * 100).round()}%'), findsOneWidget);
  });

  testWidgets('the chime volume slider can mute chimes without a preview', (tester) async {
    final h = await pumpApp(tester);
    await openSettings(tester);

    await tester.drag(find.byType(Slider), const Offset(-700, 0));
    await settle(tester);

    expect(h.controller.settings.level, 0);
    expect(h.engine.previewed, isEmpty);
    expect(find.text('Muted'), findsOneWidget);
  });

  testWidgets('settings show the phone volume and follow the volume buttons', (tester) async {
    final h = await pumpApp(tester);
    await openSettings(tester);

    expect(find.text('Phone alarm volume'), findsOneWidget);
    expect(find.textContaining('4 of 7'), findsOneWidget);
    await tester.tap(find.text('Adjust'));
    await tester.pump();
    expect(h.engine.calls, contains('openVolumeSettings'));

    h.engine.setAudio(const AudioStatus(volume: 0, maxVolume: 7, ringer: RingerMode.normal));
    await settle(tester);
    expect(find.textContaining('Chimes can\'t be heard'), findsOneWidget);

    await reveal(tester, find.text('Media volume'));
    await tester.tap(find.text('Media volume'));
    await settle(tester);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 600));
    await tester.pump();
    expect(find.text('Phone media volume'), findsOneWidget);
  });

  testWidgets('settings show the media volume while headphones are connected', (tester) async {
    final h = await pumpApp(tester);
    h.engine.audio = const AudioStatus(
      volume: 12,
      maxVolume: 25,
      ringer: RingerMode.vibrate,
      headphones: true,
    );
    await openSettings(tester);

    expect(h.controller.settings.volume, ChimeVolume.alarm);
    expect(find.text('Phone media volume'), findsOneWidget);
    expect(find.textContaining('12 of 25. Used while headphones'), findsOneWidget);
    await reveal(tester, find.text('Phone is on vibrate'));
    expect(find.text('Chimes still play, at your media volume.'), findsOneWidget);

    // Unplugged: back to the alarm volume that was chosen.
    h.engine.setAudio(const AudioStatus(volume: 4, maxVolume: 7, ringer: RingerMode.normal));
    await settle(tester);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 600));
    await tester.pump();
    expect(find.text('Phone alarm volume'), findsOneWidget);
    expect(find.textContaining('Used while headphones'), findsNothing);
  });

  testWidgets('lowering other audio can be turned off', (tester) async {
    final h = await pumpApp(tester);
    await openSettings(tester);
    expect(h.controller.settings.duckOthers, isTrue);

    await reveal(tester, find.text('Lower other audio during chimes'));
    await tester.tap(find.text('Lower other audio during chimes'));
    await tester.pump();
    expect(h.controller.settings.duckOthers, isFalse);
    expect(h.engine.appliedSettings?.duckOthers, isFalse);
  });

  testWidgets('settings say what chimes do while the phone is on vibrate', (tester) async {
    final h = await pumpApp(tester);
    h.engine.audio = const AudioStatus(volume: 4, maxVolume: 7, ringer: RingerMode.vibrate);
    await openSettings(tester);

    await reveal(tester, find.text('Phone is on vibrate'));
    expect(find.text('Chimes still play, at your alarm volume.'), findsOneWidget);

    await reveal(tester, find.text('Vibrate instead when silenced'));
    await tester.tap(find.text('Vibrate instead when silenced'));
    await tester.pump();
    expect(h.controller.settings.vibrateWhenSilenced, isTrue);
    expect(h.engine.appliedSettings?.vibrateWhenSilenced, isTrue);
    // The notice sits just above the switches.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 200));
    await tester.pump();
    expect(find.text('Chimes buzz and make no sound.'), findsOneWidget);

    h.engine.setAudio(const AudioStatus(volume: 4, maxVolume: 7, ringer: RingerMode.normal));
    await settle(tester);
    expect(find.text('Phone is on vibrate'), findsNothing);
  });

  testWidgets('the sound picker groups sounds and plays them before one is chosen', (tester) async {
    final h = await pumpApp(tester);
    await tester.tap(find.text('Mindful bell'));
    await settle(tester);
    await tester.tap(find.text('Sound'));
    await settle(tester);

    for (final group in ChimeGroup.values) {
      expect(find.text(group.label), findsOneWidget);
    }
    expect(find.text('Silent'), findsNothing);
    expect(find.text('Use Singing bowl'), findsOneWidget);

    await tester.ensureVisible(find.text('Gong'));
    await tester.pump();
    await tester.tap(find.text('Gong'));
    await tester.pump();
    expect(h.engine.previewed, [ChimeSound.gong]);
    expect(find.text('Use Gong'), findsOneWidget);

    await tester.ensureVisible(find.text('Kalimba'));
    await tester.pump();
    await tester.tap(find.text('Kalimba'));
    await tester.pump();
    expect(h.engine.previewed, [ChimeSound.gong, ChimeSound.kalimba]);

    await tester.tap(find.text('Use Kalimba'));
    await settle(tester);
    await tester.tap(find.text('Save'));
    await settle(tester);
    final saved = h.controller.presets.first;
    expect(saved.intervalSound, ChimeSound.kalimba);
    expect(saved.finishSound, ChimeSound.kalimba);
  });

  testWidgets('closing the sound picker without choosing keeps the sound', (tester) async {
    final h = await pumpApp(tester);
    final before = h.controller.presets[1].finishSound;
    await tester.tap(find.text('Stretch holds'));
    await settle(tester);
    await reveal(tester, find.text('Finish sound'));
    await tester.tap(find.text('Finish sound'));
    await settle(tester);

    expect(find.text('Silent'), findsOneWidget);
    await tester.ensureVisible(find.text('Temple bell'));
    await tester.pump();
    await tester.tap(find.text('Temple bell'));
    await tester.pump();
    expect(h.engine.previewed, [ChimeSound.temple]);
    expect(find.text('Use Temple bell'), findsOneWidget);

    // Tapping the scrim above the sheet dismisses it.
    await tester.tapAt(const Offset(400, 10));
    await settle(tester);
    expect(find.text('Use Temple bell'), findsNothing);
    await tester.pageBack();
    await settle(tester);
    expect(find.text('Discard changes?'), findsNothing);
    expect(h.controller.presets[1].finishSound, before);
  });

  testWidgets('settings offer to turn notifications on when they are off', (tester) async {
    final h = Harness();
    await h.load();
    h.engine.notificationsGranted = false;
    h.engine.grantOnRequest = false;
    await tester.pumpWidget(BelltideApp(controller: h.controller, clickUp: h.clickUp));
    await openSettings(tester);

    await reveal(tester, find.text('Turn on'));
    await tester.tap(find.text('Turn on'));
    await settle(tester);
    expect(h.engine.calls, containsAll(['requestNotifications', 'openNotificationSettings']));
  });
}

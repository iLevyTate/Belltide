import 'package:belltide/src/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fakes.dart';

Future<Harness> pumpApp(WidgetTester tester, {bool connect = false}) async {
  final h = Harness()..engine.notificationsGranted = true;
  await h.load(connectClickUp: connect);
  await tester.pumpWidget(BelltideApp(controller: h.controller, clickUp: h.clickUp));
  await tester.pump();
  return h;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('connect ClickUp from Settings with a personal token', (tester) async {
    final h = await pumpApp(tester);
    expect(find.byTooltip('ClickUp tasks'), findsNothing);

    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('ClickUp'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('ClickUp'));
    await settle(tester);
    expect(find.text('Link timers to ClickUp tasks'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'pk_wrong');
    await tester.tap(find.text('Connect'));
    await settle(tester);
    expect(find.textContaining('didn\'t accept'), findsOneWidget);
    expect(h.bridge.token, isNull);

    await tester.enterText(find.byType(TextField), 'pk_valid');
    await tester.tap(find.text('Connect'));
    await settle(tester);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('Workspace: Home'), findsOneWidget);
    expect(find.text('Log time to linked tasks'), findsOneWidget);
    expect(h.bridge.token, 'pk_valid');

    await tester.tap(find.text('Disconnect ClickUp'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Disconnect'));
    await settle(tester);
    expect(find.text('Link timers to ClickUp tasks'), findsOneWidget);
    expect(h.bridge.token, isNull);
  });

  testWidgets('link a task to a timer in the editor', (tester) async {
    final h = await pumpApp(tester, connect: true);
    await tester.tap(find.text('Stretch holds'));
    await settle(tester);

    await tester.scrollUntilVisible(find.text('Link a task'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Link a task'));
    await settle(tester);
    expect(find.text('Link a ClickUp task'), findsOneWidget);
    expect(find.text('Quad sets'), findsOneWidget);
    expect(find.textContaining('Subtask of Knee rehab'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'quad');
    await tester.pump();
    expect(find.text('Write report'), findsNothing);
    await tester.tap(find.text('Quad sets'));
    await settle(tester);

    expect(find.text('Quad sets'), findsOneWidget);
    expect(find.text('Time is logged when the timer pauses, stops or finishes'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await settle(tester);

    final saved = h.controller.presets[1];
    expect(saved.task!.taskId, '86a2');
    expect(saved.task!.teamId, '9001');
    // The card shows the linked task.
    expect(find.text('Quad sets'), findsOneWidget);
    await tester.tap(find.text('Quad sets'));
    expect(h.bridge.calls.last, 'open:https://app.clickup.com/t/86a2');
  });

  testWidgets('start a timer for a task from task search', (tester) async {
    final h = await pumpApp(tester, connect: true);
    await tester.tap(find.byTooltip('ClickUp tasks'));
    await settle(tester);
    expect(find.text('ClickUp tasks'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'knee');
    await tester.pump();
    await tester.tap(find.text('Knee rehab'));
    await settle(tester);

    expect(find.text('Start with one of your timers'), findsOneWidget);
    await tester.tap(find.text('Stretch holds').last);
    await settle(tester);

    final copy = h.controller.presetsForTask('86a1').single;
    expect(copy.name, 'Stretch holds');
    expect(h.engine.started.single.id, copy.id);
    expect(h.engine.started.single.toEngineJson()['task'], {'id': '86a1', 'teamId': '9001', 'name': 'Knee rehab'});
    // Back on the home screen with a confirmation.
    expect(find.text('Started Stretch holds for Knee rehab'), findsOneWidget);
    expect(find.text('Knee rehab'), findsOneWidget);
  });

  testWidgets('a pasted task link that is not loaded is looked up', (tester) async {
    final h = await pumpApp(tester, connect: true);
    h.server.extraTasks['86old1'] = {
      'id': '86old1',
      'name': 'Archived plan',
      'status': {'status': 'complete', 'type': 'closed', 'color': '#6bc950'},
      'url': 'https://app.clickup.com/t/86old1',
    };
    await tester.tap(find.byTooltip('ClickUp tasks'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'https://app.clickup.com/t/86old1');
    await tester.pump();
    await tester.tap(find.textContaining('Find task'));
    await settle(tester);
    expect(find.text('Archived plan'), findsOneWidget);
    expect(find.text('COMPLETE'), findsOneWidget);
  });
}

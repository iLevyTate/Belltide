import 'dart:convert';

import 'package:belltide/src/clickup/clickup_api.dart';
import 'package:belltide/src/clickup/clickup_controller.dart';
import 'package:belltide/src/clickup/clickup_models.dart';
import 'package:belltide/src/data/key_value_store.dart';
import 'package:belltide/src/model/task_link.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/clickup_fakes.dart';

void main() {
  late FakeClickUpServer server;
  late FakeClickUpBridge bridge;
  late MemoryStore store;
  var now = DateTime(2026, 11, 27, 9);

  ClickUpController make() =>
      ClickUpController(bridge: bridge, store: store, apiFactory: server.api, now: () => now);

  setUp(() {
    server = FakeClickUpServer();
    bridge = FakeClickUpBridge();
    store = MemoryStore();
    now = DateTime(2026, 11, 27, 9);
  });

  test('starts disconnected', () async {
    final c = make();
    await c.load();
    expect(c.connected, isFalse);
    expect(c.account, isNull);
  });

  test('connecting with one workspace selects it and stores the token natively', () async {
    final c = make();
    await c.load();
    final workspaces = await c.connect('  pk_valid ');
    expect(workspaces, hasLength(1));
    expect(c.connected, isTrue);
    expect(c.account!.username, 'Sam');
    expect(c.account!.userId, 42);
    expect(c.account!.workspaceId, '9001');
    expect(bridge.token, 'pk_valid');
    // The token itself never lands in shared preferences.
    expect(store.values[ClickUpController.storeKey], isNot(contains('pk_valid')));
  });

  test('with several workspaces the user chooses one', () async {
    server.workspaces = [
      {'id': '1', 'name': 'Home'},
      {'id': '2', 'name': 'Work'},
    ];
    final c = make();
    await c.load();
    final workspaces = await c.connect('pk_valid');
    expect(workspaces, hasLength(2));
    expect(c.connected, isFalse);
    await c.selectWorkspace(const ClickUpWorkspace(id: '2', name: 'Work'));
    expect(c.connected, isTrue);
    expect(c.account!.workspaceName, 'Work');
    expect(c.account!.username, 'Sam');
  });

  test('a rejected token is not stored', () async {
    final c = make();
    await c.load();
    await expectLater(c.connect('pk_wrong'), throwsA(isA<ClickUpException>()));
    expect(bridge.token, isNull);
    expect(c.connected, isFalse);
  });

  test('reconnects on the next launch, or forgets the account if the token is gone', () async {
    final first = make();
    await first.load();
    await first.connect('pk_valid');

    final second = make();
    await second.load();
    expect(second.connected, isTrue);
    expect(second.account!.workspaceName, 'Home');

    bridge.token = null;
    final third = make();
    await third.load();
    expect(third.connected, isFalse);
  });

  test('loads several pages of my tasks until the last page', () async {
    server.taskPages = [
      [taskJson('a', 'One')],
      [taskJson('b', 'Two')],
      [taskJson('c', 'Three')],
      [taskJson('d', 'Four')],
    ];
    final c = make();
    await c.load();
    await c.connect('pk_valid');
    await c.loadTasks();
    expect(c.tasks.map((t) => t.id), ['a', 'b', 'c']);
    expect(c.hasMoreTasks, isTrue);
    expect(server.requests.where((r) => r.url.path.endsWith('/task')).every(
      (r) => r.url.queryParametersAll['assignees[]']?.single == '42',
    ), isTrue);

    await c.loadMoreTasks();
    expect(c.tasks.map((t) => t.id), ['a', 'b', 'c', 'd']);
    expect(c.hasMoreTasks, isFalse);
  });

  test('turning off "only mine" reloads without the assignee filter', () async {
    final c = make();
    await c.load();
    await c.connect('pk_valid');
    await c.loadTasks();
    server.requests.clear();
    await c.setOnlyMine(false);
    final request = server.requests.single;
    expect(request.url.queryParametersAll['assignees[]'], isNull);
  });

  test('search runs over loaded tasks and finds parents of subtasks', () async {
    final c = make();
    await c.load();
    await c.connect('pk_valid');
    await c.loadTasks();
    final results = c.search('knee');
    expect(results.map((t) => t.name), ['Knee rehab', 'Quad sets']);
    expect(c.parentOf(results[1])!.name, 'Knee rehab');
  });

  test('a pasted link or custom id is looked up directly', () async {
    server.extraTasks['86zz99'] = taskJson('86zz99', 'Old task');
    final c = make();
    await c.load();
    await c.connect('pk_valid');
    expect((await c.lookup('https://app.clickup.com/t/86zz99'))!.name, 'Old task');
    expect((await c.lookup('DEV-42'))!.name, 'Write report');
    expect(await c.lookup('just words'), isNull);
  });

  test('refreshes linked tasks, reports renames, and flags deleted tasks', () async {
    final c = make();
    await c.load();
    await c.connect('pk_valid');
    Map<String, ClickUpTask>? reported;
    c.onLinkedTasksFetched = (tasks) => reported = tasks;
    const links = [
      TaskLink(taskId: '86a1', teamId: '9001', name: 'Old name'),
      TaskLink(taskId: 'gone11', teamId: '9001', name: 'Deleted'),
    ];
    await c.refreshLinked(links);
    expect(c.linkedTask('86a1')!.name, 'Knee rehab');
    expect(c.isMissing('gone11'), isTrue);
    expect(reported!.keys, ['86a1']);

    // Throttled until the interval passes.
    server.requests.clear();
    await c.refreshLinked(links);
    expect(server.requests, isEmpty);
    now = now.add(ClickUpController.linkedRefreshInterval);
    await c.refreshLinked(links);
    expect(server.requests, hasLength(2));
  });

  test('settings persist and logging is pushed to the service', () async {
    final c = make();
    await c.load();
    await c.connect('pk_valid');
    await c.setLogTime(false);
    expect(bridge.logging, isFalse);
    final saved = jsonDecode(store.values[ClickUpController.storeKey]!) as Map<String, Object?>;
    expect(saved['logTime'], isFalse);
  });

  test('sync status comes from the service', () async {
    bridge.status = const SyncStatus(pending: 2, lastError: 'offline');
    bridge.afterSync = const SyncStatus(pending: 0);
    final c = make();
    await c.load();
    await c.connect('pk_valid');
    await c.refreshSyncStatus();
    expect(c.syncStatus.pending, 2);
    await c.syncNow();
    expect(c.syncStatus.pending, 0);
  });

  test('disconnect forgets the token, the queue and the account', () async {
    final c = make();
    await c.load();
    await c.connect('pk_valid');
    await c.loadTasks();
    await c.disconnect();
    expect(c.connected, isFalse);
    expect(c.tasks, isEmpty);
    expect(bridge.token, isNull);
    expect(bridge.calls, containsAll(['clearToken', 'clearQueue']));
    final reloaded = make();
    await reloaded.load();
    expect(reloaded.account, isNull);
  });

  test('opens tasks by their link, or builds one from the id', () async {
    final c = make();
    await c.load();
    await c.openTask(const TaskLink(taskId: 'abc123', teamId: '1', name: 'x'));
    expect(bridge.calls.last, 'open:https://app.clickup.com/t/abc123');
  });
}

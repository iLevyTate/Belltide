import 'dart:convert';

import 'package:belltide/src/clickup/clickup_api.dart';
import 'package:belltide/src/clickup/clickup_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/clickup_fakes.dart';

void main() {
  late FakeClickUpServer server;
  setUp(() => server = FakeClickUpServer());

  test('sends the personal token as-is in the Authorization header', () async {
    final user = await server.api('pk_valid').getUser();
    expect(user.id, 42);
    expect(user.username, 'Sam');
    final request = server.requests.single;
    expect(request.headers['Authorization'], 'pk_valid');
    expect(request.url.toString(), 'https://api.clickup.com/api/v2/user');
  });

  test('lists workspaces', () async {
    final workspaces = await server.api('pk_valid').getWorkspaces();
    expect(workspaces.single.id, '9001');
    expect(workspaces.single.name, 'Home');
  });

  test('filtered task request uses the documented parameters', () async {
    final page = await server.api('pk_valid').getTasks('9001', page: 2, assigneeId: 42);
    final url = server.requests.single.url;
    expect(url.path, '/api/v2/team/9001/task');
    expect(url.queryParameters['page'], '2');
    expect(url.queryParameters['order_by'], 'updated');
    expect(url.queryParameters['subtasks'], 'true');
    expect(url.queryParameters['include_closed'], 'false');
    expect(url.queryParametersAll['assignees[]'], ['42']);
    expect(url.query, contains('assignees%5B%5D=42'));
    expect(page.tasks, isEmpty);
    expect(page.lastPage, isTrue);
  });

  test('parses tasks, subtasks and locations', () async {
    final page = await server.api('pk_valid').getTasks('9001');
    expect(page.tasks.map((t) => t.name), ['Knee rehab', 'Quad sets', 'Write report']);
    final sub = page.tasks[1];
    expect(sub.isSubtask, isTrue);
    expect(sub.parentId, '86a1');
    expect(sub.location, 'Health › Physio');
    expect(sub.dateUpdated, 2000);
    expect(sub.status, 'to do');
    expect(sub.statusColor, '#d3d3d3');
    expect(page.tasks[2].customId, 'DEV-42');
  });

  test('without last_page, a short page means the end', () async {
    final client = MockClient((_) async => http.Response('{"tasks":[]}', 200));
    final page = await ClickUpApi(token: 'pk', client: client).getTasks('1');
    expect(page.lastPage, isTrue);
  });

  test('task names keep accents, symbols and emoji', () async {
    final client = MockClient((_) async => http.Response.bytes(
      utf8.encode(jsonEncode({
        'tasks': [
          {'id': 'u1', 'name': 'Quad sets, 3 × 10 🦵', 'list': {'name': 'Rééducation'}},
        ],
      })),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    ));
    final page = await ClickUpApi(token: 'pk', client: client).getTasks('1');
    expect(page.tasks.single.name, 'Quad sets, 3 × 10 🦵');
    expect(page.tasks.single.listName, 'Rééducation');
  });

  test('hidden folders are left out of the location', () {
    final task = ClickUpTask.fromJson({
      'id': 'x',
      'name': 'T',
      'list': {'name': 'Inbox'},
      'folder': {'name': 'hidden', 'hidden': true},
    }, teamId: '1');
    expect(task.location, 'Inbox');
    expect(task.teamId, '1');
  });

  test('custom task ids are looked up with the workspace id', () async {
    final task = await server.api('pk_valid').getTask('DEV-42', customIdTeam: '9001');
    expect(task.name, 'Write report');
    final url = server.requests.single.url;
    expect(url.queryParameters['custom_task_ids'], 'true');
    expect(url.queryParameters['team_id'], '9001');
  });

  test('a bad token gives an unauthorized error with a helpful message', () async {
    await expectLater(
      server.api('pk_wrong').getUser(),
      throwsA(isA<ClickUpException>()
          .having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)
          .having((e) => e.code, 'code', 'OAUTH_025')
          .having((e) => e.message, 'message', contains('didn\'t accept'))),
    );
  });

  test('a missing task is reported as not found with ClickUp\'s message', () async {
    await expectLater(
      server.api('pk_valid').getTask('nope99'),
      throwsA(isA<ClickUpException>()
          .having((e) => e.isNotFound, 'isNotFound', isTrue)
          .having((e) => e.message, 'message', 'Task not found, deleted')),
    );
  });

  test('rate limits, server errors and network failures read clearly', () async {
    Future<ClickUpException> failWith(http.Client client) async {
      try {
        await ClickUpApi(token: 'pk', client: client).getUser();
      } on ClickUpException catch (e) {
        return e;
      }
      fail('expected an error');
    }

    expect((await failWith(MockClient((_) async => http.Response('', 429)))).message, contains('Too many'));
    expect((await failWith(MockClient((_) async => http.Response('oops', 502)))).message, contains('trouble'));
    expect(
      (await failWith(MockClient((_) async => throw http.ClientException('Failed host lookup')))).message,
      contains('Couldn\'t reach'),
    );
    expect(
      (await failWith(MockClient((_) async => http.Response('<html>', 200)))).message,
      contains('unexpected'),
    );
  });

  group('TaskReference.parse', () {
    TaskReference? parse(String s) => TaskReference.parse(s, teamId: '9001');

    test('task links', () {
      expect(parse('https://app.clickup.com/t/86a1b2c3')!.id, '86a1b2c3');
      final custom = parse('https://app.clickup.com/t/9001/DEV-42')!;
      expect(custom.id, 'DEV-42');
      expect(custom.customIdTeam, '9001');
    });

    test('bare and custom ids', () {
      expect(parse('86a1b2c3')!.customIdTeam, isNull);
      expect(parse('#86a1b2c3')!.id, '86a1b2c3');
      final custom = parse('dev-42')!;
      expect(custom.id, 'DEV-42');
      expect(custom.customIdTeam, '9001');
    });

    test('ordinary search text is not a reference', () {
      expect(parse('knee'), isNull);
      expect(parse('knee rehab'), isNull);
      expect(parse('stretching'), isNull);
      expect(parse(''), isNull);
      expect(parse('https://example.com/t/86a1b2c3'), isNull, reason: 'only ClickUp links count');
    });
  });
}

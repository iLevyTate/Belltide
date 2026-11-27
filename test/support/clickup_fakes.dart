import 'dart:convert';

import 'package:belltide/src/clickup/clickup_api.dart';
import 'package:belltide/src/clickup/clickup_bridge.dart';
import 'package:belltide/src/clickup/clickup_models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Builds a task the way ClickUp's API returns it.
Map<String, Object?> taskJson(
  String id,
  String name, {
  String status = 'to do',
  String statusType = 'open',
  String? parent,
  String list = 'Physio',
  String folder = 'Health',
  int updated = 1000,
  String? customId,
}) => {
  'id': id,
  'custom_id': customId,
  'name': name,
  'status': {'status': status, 'color': '#d3d3d3', 'type': statusType, 'orderindex': 0},
  'parent': parent,
  'list': {'id': 'l1', 'name': list, 'access': true},
  'folder': {'id': 'f1', 'name': folder, 'hidden': false, 'access': true},
  'space': {'id': 's1'},
  'url': 'https://app.clickup.com/t/$id',
  'date_updated': '$updated',
  'team_id': '9001',
};

/// An in-memory stand-in for api.clickup.com.
class FakeClickUpServer {
  String validToken = 'pk_valid';
  List<Map<String, Object?>> workspaces = [
    {'id': '9001', 'name': 'Home', 'color': '#7b68ee', 'avatar': null, 'members': []},
  ];
  Map<String, Object?> user = {'id': 42, 'username': 'Sam', 'email': 'sam@example.com'};

  /// Pages of tasks returned by "Get Filtered Team Tasks".
  List<List<Map<String, Object?>>> taskPages = [
    [
      taskJson('86a1', 'Knee rehab', updated: 3000),
      taskJson('86a2', 'Quad sets', parent: '86a1', updated: 2000),
      taskJson('86a3', 'Write report', list: 'Work', folder: 'Office', updated: 1000, customId: 'DEV-42'),
    ],
  ];

  /// Tasks reachable through "Get Task" that aren't in the pages.
  final Map<String, Map<String, Object?>> extraTasks = {};
  final List<http.Request> requests = [];

  http.Client client() => MockClient((request) async {
    requests.add(request);
    if (request.headers['Authorization'] != validToken) {
      return http.Response(jsonEncode({'err': 'Token invalid', 'ECODE': 'OAUTH_025'}), 401);
    }
    final path = request.url.path;
    if (path == '/api/v2/user') return _json({'user': user});
    if (path == '/api/v2/team') return _json({'teams': workspaces});
    final list = RegExp(r'^/api/v2/team/(\w+)/task$').firstMatch(path);
    if (list != null) {
      final page = int.parse(request.url.queryParameters['page'] ?? '0');
      final tasks = page < taskPages.length ? taskPages[page] : <Map<String, Object?>>[];
      return _json({'tasks': tasks, 'last_page': page >= taskPages.length - 1});
    }
    final one = RegExp(r'^/api/v2/task/(.+)$').firstMatch(path);
    if (one != null) {
      final id = Uri.decodeComponent(one.group(1)!);
      final all = [...taskPages.expand((p) => p), ...extraTasks.values];
      for (final t in all) {
        if (t['id'] == id || t['custom_id'] == id) return _json(t);
      }
      return http.Response(jsonEncode({'err': 'Task not found, deleted', 'ECODE': 'ITEM_013'}), 404);
    }
    return http.Response('{"err":"Route not found"}', 404);
  });

  ClickUpApi api(String token) => ClickUpApi(token: token, client: client());

  http.Response _json(Object body) =>
      http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
}

class FakeClickUpBridge implements ClickUpBridge {
  String? token;
  bool logging = true;
  SyncStatus status = SyncStatus.empty;
  SyncStatus? afterSync;
  final List<String> calls = [];

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String? token) async {
    calls.add(token == null ? 'clearToken' : 'saveToken');
    this.token = token;
  }

  @override
  Future<void> setLogging(bool enabled) async => logging = enabled;

  @override
  Future<SyncStatus> syncStatus() async => status;

  @override
  Future<SyncStatus> syncNow() async {
    calls.add('syncNow');
    status = afterSync ?? status;
    return status;
  }

  @override
  Future<void> clearQueue() async {
    calls.add('clearQueue');
    status = SyncStatus.empty;
  }

  @override
  Future<void> openUrl(String url) async => calls.add('open:$url');
}

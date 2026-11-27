import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'clickup_models.dart';

/// A failed ClickUp call, with a message fit to show the user.
class ClickUpException implements Exception {
  const ClickUpException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;

  /// ClickUp's `ECODE`, when it sent one.
  final String? code;

  bool get isUnauthorized => statusCode == 401;
  bool get isNotFound => statusCode == 404;

  @override
  String toString() => 'ClickUpException($statusCode, $code): $message';
}

/// The parts of the ClickUp REST API (v2) Belltide uses. Calls go straight from
/// the phone to api.clickup.com with the user's personal token.
///
/// The public API has no text search for tasks, so searching is done on the
/// device over pages from "Get Filtered Team Tasks" (see task_search.dart).
class ClickUpApi {
  ClickUpApi({required this._token, http.Client? client, this.host = 'api.clickup.com'})
    : _client = client ?? http.Client();

  static const int pageSize = 100;
  static const Duration timeout = Duration(seconds: 20);

  final String _token;
  final http.Client _client;
  final String host;

  Future<ClickUpUser> getUser() async {
    final json = await _get('/api/v2/user');
    final user = json['user'];
    if (user is! Map<String, Object?>) throw const ClickUpException('ClickUp sent an unexpected reply.');
    return ClickUpUser.fromJson(user);
  }

  Future<List<ClickUpWorkspace>> getWorkspaces() async {
    final json = await _get('/api/v2/team');
    return (json['teams'] as List<Object?>? ?? const [])
        .whereType<Map<String, Object?>>()
        .map(ClickUpWorkspace.fromJson)
        .toList();
  }

  /// One page (up to 100) of a workspace's tasks, most recently updated first.
  Future<TaskPage> getTasks(
    String teamId, {
    int page = 0,
    int? assigneeId,
    bool includeClosed = false,
    bool subtasks = true,
  }) async {
    final json = await _get('/api/v2/team/$teamId/task', {
      'page': '$page',
      'order_by': 'updated',
      'subtasks': '$subtasks',
      'include_closed': '$includeClosed',
      if (assigneeId != null) 'assignees[]': ['$assigneeId'],
    });
    final tasks = (json['tasks'] as List<Object?>? ?? const [])
        .whereType<Map<String, Object?>>()
        .map((t) => ClickUpTask.fromJson(t, teamId: teamId))
        .where((t) => t.id.isNotEmpty)
        .toList();
    final lastPage = json['last_page'] as bool? ?? tasks.length < pageSize;
    return TaskPage(tasks: tasks, lastPage: lastPage);
  }

  /// A task by id, or by custom id (like `DEV-42`) when [teamId] is given.
  Future<ClickUpTask> getTask(String id, {String? customIdTeam}) async {
    final json = await _get('/api/v2/task/${Uri.encodeComponent(id)}', {
      if (customIdTeam != null) ...{'custom_task_ids': 'true', 'team_id': customIdTeam},
    });
    return ClickUpTask.fromJson(json, teamId: customIdTeam);
  }

  Future<Map<String, Object?>> _get(String path, [Map<String, Object>? query]) async {
    final uri = Uri.https(host, path, query?.isEmpty ?? true ? null : query);
    final http.Response response;
    try {
      response = await _client.get(uri, headers: {'Authorization': _token}).timeout(timeout);
    } on TimeoutException {
      throw const ClickUpException('ClickUp took too long to answer. Try again.');
    } on Exception {
      // http reports socket and TLS failures as ClientException.
      throw const ClickUpException('Couldn\'t reach ClickUp. Check your connection.');
    }

    Object? body;
    try {
      // ClickUp sends UTF-8; a stray invalid byte shouldn't hide a whole page of tasks.
      body = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
    } on FormatException {
      body = null;
    }
    final map = body is Map<String, Object?> ? body : const <String, Object?>{};

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (body is! Map<String, Object?>) throw const ClickUpException('ClickUp sent an unexpected reply.');
      return map;
    }
    final err = map['err'] as String?;
    final code = map['ECODE'] as String?;
    final message = switch (response.statusCode) {
      401 => 'ClickUp didn\'t accept that token. Check it and try again.',
      404 => err ?? 'Not found in ClickUp.',
      429 => 'Too many requests to ClickUp. Wait a minute and try again.',
      >= 500 => 'ClickUp is having trouble right now. Try again later.',
      _ => err ?? 'ClickUp returned an error (HTTP ${response.statusCode}).',
    };
    throw ClickUpException(message, statusCode: response.statusCode, code: code);
  }

  void close() => _client.close();
}

/// What a pasted task link or id refers to.
class TaskReference {
  const TaskReference(this.id, {this.customIdTeam});

  final String id;

  /// Set when [id] is a custom task id (like `DEV-42`) in this workspace.
  final String? customIdTeam;

  /// Recognizes `https://app.clickup.com/t/86abc`, `.../t/9001/DEV-42`, a bare task
  /// id, or a custom id. Returns null for ordinary search text.
  static TaskReference? parse(String input, {required String teamId}) {
    final text = input.trim();
    if (text.isEmpty || text.contains(' ')) return null;
    final uri = Uri.tryParse(text);
    if (uri != null && uri.host.endsWith('clickup.com')) {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      final t = segments.indexOf('t');
      if (t < 0 || t + 1 >= segments.length) return null;
      final rest = segments.sublist(t + 1);
      if (rest.length >= 2) return TaskReference(rest[1], customIdTeam: rest[0]);
      return _fromId(rest[0], teamId);
    }
    if (text.startsWith('#')) return _fromId(text.substring(1), teamId);
    return _fromId(text, teamId);
  }

  static final RegExp _customId = RegExp(r'^[A-Za-z][A-Za-z0-9]*-\d+$');
  static final RegExp _taskId = RegExp(r'^(?=.*\d)[a-z0-9]{6,12}$');

  static TaskReference? _fromId(String id, String teamId) {
    if (_customId.hasMatch(id)) return TaskReference(id.toUpperCase(), customIdTeam: teamId);
    if (_taskId.hasMatch(id)) return TaskReference(id);
    return null;
  }
}

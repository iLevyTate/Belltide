import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/key_value_store.dart';
import '../model/task_link.dart';
import 'clickup_api.dart';
import 'clickup_bridge.dart';
import 'clickup_models.dart';
import 'task_search.dart';

/// The connected account: who the token belongs to and which workspace to use.
@immutable
class ClickUpAccount {
  const ClickUpAccount({
    required this.userId,
    required this.username,
    required this.workspaceId,
    required this.workspaceName,
  });

  final int userId;
  final String username;
  final String workspaceId;
  final String workspaceName;

  Map<String, Object?> toJson() => {
    'userId': userId,
    'username': username,
    'workspaceId': workspaceId,
    'workspaceName': workspaceName,
  };

  static ClickUpAccount? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final workspaceId = json['workspaceId'] as String?;
    if (workspaceId == null || workspaceId.isEmpty) return null;
    return ClickUpAccount(
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      username: json['username'] as String? ?? '',
      workspaceId: workspaceId,
      workspaceName: json['workspaceName'] as String? ?? '',
    );
  }
}

/// Opt-in ClickUp integration: connection, task search, and linked-task status.
/// Time logging itself happens in the Android timer service.
class ClickUpController extends ChangeNotifier {
  ClickUpController({
    required this._bridge,
    required this._store,
    ClickUpApi Function(String token)? apiFactory,
    DateTime Function()? now,
  }) : _apiFactory = apiFactory ?? ((token) => ClickUpApi(token: token)),
       _now = now ?? DateTime.now;

  static const String storeKey = 'clickup.v1';

  /// Pages fetched when the task list first loads (100 tasks each).
  static const int initialPages = 3;

  /// How long linked-task details are trusted before refreshing.
  static const Duration linkedRefreshInterval = Duration(minutes: 2);

  final ClickUpBridge _bridge;
  final KeyValueStore _store;
  final ClickUpApi Function(String token) _apiFactory;
  final DateTime Function() _now;

  ClickUpApi? _api;
  ClickUpAccount? _account;
  ClickUpUser? _pendingUser;
  bool _logTime = true;
  bool _onlyMine = true;
  bool _includeClosed = false;

  List<ClickUpTask> _tasks = const [];
  bool _loadingTasks = false;
  String? _tasksError;
  int _nextPage = 0;
  bool _hasMore = true;

  final Map<String, ClickUpTask> _linked = {};
  final Set<String> _missing = {};
  DateTime? _linkedRefreshedAt;
  SyncStatus _sync = SyncStatus.empty;

  /// Called with fresh details of linked tasks, so saved timers can keep names in sync.
  void Function(Map<String, ClickUpTask> tasks)? onLinkedTasksFetched;

  bool get connected => _api != null && _account != null;
  ClickUpAccount? get account => _account;
  bool get logTime => _logTime;
  bool get onlyMine => _onlyMine;
  bool get includeClosed => _includeClosed;
  List<ClickUpTask> get tasks => _tasks;
  bool get loadingTasks => _loadingTasks;
  String? get tasksError => _tasksError;
  bool get hasMoreTasks => _hasMore;
  bool get tasksLoaded => _nextPage > 0;
  SyncStatus get syncStatus => _sync;

  ClickUpTask? linkedTask(String taskId) => _linked[taskId];
  bool isMissing(String taskId) => _missing.contains(taskId);

  Future<void> load() async {
    final raw = await _store.getString(storeKey);
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, Object?>;
        _account = ClickUpAccount.fromJson(json['account']);
        _logTime = json['logTime'] as bool? ?? true;
        _onlyMine = json['onlyMine'] as bool? ?? true;
        _includeClosed = json['includeClosed'] as bool? ?? false;
      } on FormatException {
        _account = null;
      }
    }
    if (_account != null) {
      final token = await _guard(_bridge.readToken);
      if (token == null || token.isEmpty) {
        // The token can be lost (for example after restoring a backup on a new phone).
        _account = null;
      } else {
        _api = _apiFactory(token);
        unawaited(refreshSyncStatus());
      }
    }
    notifyListeners();
  }

  Future<void> _save() => _store.setString(
    storeKey,
    jsonEncode({
      'account': _account?.toJson(),
      'logTime': _logTime,
      'onlyMine': _onlyMine,
      'includeClosed': _includeClosed,
    }),
  );

  /// Checks [token] with ClickUp and stores it. Returns the user's workspaces; if
  /// there is exactly one it is selected, otherwise call [selectWorkspace].
  Future<List<ClickUpWorkspace>> connect(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) throw const ClickUpException('Paste your ClickUp API token first.');
    final api = _apiFactory(trimmed);
    final user = await api.getUser();
    final workspaces = await api.getWorkspaces();
    if (workspaces.isEmpty) {
      throw const ClickUpException('This ClickUp account has no workspaces.');
    }
    await _bridge.saveToken(trimmed);
    await _guard(() => _bridge.setLogging(_logTime));
    _api = api;
    _pendingUser = user;
    _resetTasks();
    if (workspaces.length == 1) {
      await selectWorkspace(workspaces.single);
    } else {
      notifyListeners();
    }
    return workspaces;
  }

  /// The workspaces the connected token can see, for switching workspace.
  Future<List<ClickUpWorkspace>> workspaces() async {
    final api = _api;
    if (api == null) return const [];
    return api.getWorkspaces();
  }

  Future<void> selectWorkspace(ClickUpWorkspace workspace) async {
    final user = _pendingUser;
    _account = ClickUpAccount(
      userId: user?.id ?? _account?.userId ?? 0,
      username: user?.username ?? _account?.username ?? '',
      workspaceId: workspace.id,
      workspaceName: workspace.name,
    );
    _pendingUser = null;
    _resetTasks();
    notifyListeners();
    await _save();
  }

  /// Forgets the token and any time entries that haven't been sent yet.
  Future<void> disconnect() async {
    await _guard(() => _bridge.saveToken(null));
    await _guard(_bridge.clearQueue);
    _api?.close();
    _api = null;
    _account = null;
    _pendingUser = null;
    _linked.clear();
    _missing.clear();
    _sync = SyncStatus.empty;
    _resetTasks();
    notifyListeners();
    await _save();
  }

  Future<void> setLogTime(bool value) async {
    _logTime = value;
    notifyListeners();
    await _guard(() => _bridge.setLogging(value));
    await _save();
  }

  Future<void> setOnlyMine(bool value) async {
    if (value == _onlyMine) return;
    _onlyMine = value;
    _resetTasks();
    notifyListeners();
    await _save();
    await loadTasks();
  }

  Future<void> setIncludeClosed(bool value) async {
    if (value == _includeClosed) return;
    _includeClosed = value;
    _resetTasks();
    notifyListeners();
    await _save();
    await loadTasks();
  }

  void _resetTasks() {
    _tasks = const [];
    _nextPage = 0;
    _hasMore = true;
    _tasksError = null;
  }

  /// Loads the first pages of tasks (or reloads them with [refresh]).
  Future<void> loadTasks({bool refresh = false}) async {
    if (!connected || _loadingTasks) return;
    if (refresh) _resetTasks();
    if (tasksLoaded) return;
    await _fetchPages(initialPages);
  }

  /// Loads the next page, for searches that need older tasks.
  Future<void> loadMoreTasks() async {
    if (!connected || _loadingTasks || !_hasMore) return;
    await _fetchPages(1);
  }

  Future<void> _fetchPages(int count) async {
    final api = _api!;
    final account = _account!;
    _loadingTasks = true;
    _tasksError = null;
    notifyListeners();
    try {
      for (var i = 0; i < count && _hasMore; i++) {
        final page = await api.getTasks(
          account.workspaceId,
          page: _nextPage,
          assigneeId: _onlyMine && account.userId != 0 ? account.userId : null,
          includeClosed: _includeClosed,
        );
        final seen = {for (final t in _tasks) t.id};
        _tasks = [..._tasks, ...page.tasks.where((t) => !seen.contains(t.id))];
        _nextPage++;
        _hasMore = !page.lastPage;
      }
    } on ClickUpException catch (e) {
      _tasksError = e.message;
    } finally {
      _loadingTasks = false;
      notifyListeners();
    }
  }

  List<ClickUpTask> search(String query) => searchTasks(_tasks, query);

  /// The parent of a subtask, if it's among the loaded tasks.
  ClickUpTask? parentOf(ClickUpTask task) {
    final id = task.parentId;
    if (id == null) return null;
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return _linked[id];
  }

  /// Fetches the task a pasted link or id points to, or null if [input] isn't one.
  Future<ClickUpTask?> lookup(String input) async {
    final api = _api;
    final account = _account;
    if (api == null || account == null) return null;
    final ref = TaskReference.parse(input, teamId: account.workspaceId);
    if (ref == null) return null;
    final task = await api.getTask(ref.id, customIdTeam: ref.customIdTeam);
    return task.teamId.isEmpty ? _withTeam(task, account.workspaceId) : task;
  }

  ClickUpTask _withTeam(ClickUpTask t, String teamId) => ClickUpTask(
    id: t.id,
    name: t.name,
    teamId: teamId,
    customId: t.customId,
    status: t.status,
    statusColor: t.statusColor,
    statusType: t.statusType,
    parentId: t.parentId,
    listName: t.listName,
    folderName: t.folderName,
    url: t.url,
    dateUpdated: t.dateUpdated,
  );

  /// Refreshes name and status of the tasks timers are linked to.
  Future<void> refreshLinked(Iterable<TaskLink> links, {bool force = false}) async {
    final api = _api;
    if (api == null) return;
    final now = _now();
    final last = _linkedRefreshedAt;
    if (!force && last != null && now.difference(last) < linkedRefreshInterval) return;
    _linkedRefreshedAt = now;

    final fetched = <String, ClickUpTask>{};
    final ids = links.map((l) => l.taskId).toSet().take(25);
    for (final id in ids) {
      try {
        final task = await api.getTask(id);
        _linked[id] = task;
        _missing.remove(id);
        fetched[id] = task;
      } on ClickUpException catch (e) {
        if (e.isNotFound) _missing.add(id);
        if (e.isUnauthorized || e.statusCode == 429) break;
      }
    }
    notifyListeners();
    if (fetched.isNotEmpty) onLinkedTasksFetched?.call(fetched);
  }

  /// Remembers a task picked in search so its status shows right away.
  void rememberTask(ClickUpTask task) {
    _linked[task.id] = task;
    _missing.remove(task.id);
    notifyListeners();
  }

  Future<void> refreshSyncStatus() async {
    final status = await _guard(_bridge.syncStatus);
    if (status == null) return;
    _sync = status;
    notifyListeners();
  }

  Future<void> syncNow() async {
    final status = await _guard(_bridge.syncNow);
    if (status == null) return;
    _sync = status;
    notifyListeners();
  }

  Future<void> openTask(TaskLink link) async {
    final url = link.url ?? 'https://app.clickup.com/t/${link.taskId}';
    await _guard(() => _bridge.openUrl(url));
  }

  Future<T?> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      debugPrint('Belltide: ClickUp bridge call failed: $e');
      return null;
    }
  }

  @override
  void dispose() {
    _api?.close();
    super.dispose();
  }
}

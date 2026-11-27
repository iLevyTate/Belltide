import 'package:flutter/foundation.dart';

import '../model/task_link.dart';

@immutable
class ClickUpUser {
  const ClickUpUser({required this.id, required this.username, this.email});

  final int id;
  final String username;
  final String? email;

  factory ClickUpUser.fromJson(Map<String, Object?> json) => ClickUpUser(
    id: (json['id'] as num?)?.toInt() ?? 0,
    username: json['username'] as String? ?? '',
    email: json['email'] as String?,
  );
}

/// A ClickUp workspace. The v2 API calls these "teams".
@immutable
class ClickUpWorkspace {
  const ClickUpWorkspace({required this.id, required this.name, this.color});

  final String id;
  final String name;
  final String? color;

  factory ClickUpWorkspace.fromJson(Map<String, Object?> json) => ClickUpWorkspace(
    id: '${json['id'] ?? ''}',
    name: json['name'] as String? ?? 'Workspace',
    color: json['color'] as String?,
  );
}

@immutable
class ClickUpTask {
  const ClickUpTask({
    required this.id,
    required this.name,
    required this.teamId,
    this.customId,
    this.status = '',
    this.statusColor,
    this.statusType,
    this.parentId,
    this.listName,
    this.folderName,
    this.url,
    this.dateUpdated = 0,
  });

  final String id;
  final String? customId;
  final String name;
  final String teamId;
  final String status;

  /// Hex color such as `#d3d3d3`.
  final String? statusColor;

  /// `open`, `custom`, `done` or `closed`.
  final String? statusType;

  /// Set for subtasks: the id of the parent task.
  final String? parentId;
  final String? listName;
  final String? folderName;
  final String? url;

  /// Last change, in Unix milliseconds.
  final int dateUpdated;

  bool get isSubtask => parentId != null;
  bool get isClosed => statusType == 'closed' || statusType == 'done';

  /// "Folder › List", or whichever part is known.
  String get location =>
      [folderName, listName].whereType<String>().where((s) => s.isNotEmpty && s != 'hidden').join(' › ');

  TaskLink toLink() => TaskLink(taskId: id, teamId: teamId, name: name, url: url, customId: customId);

  factory ClickUpTask.fromJson(Map<String, Object?> json, {String? teamId}) {
    String? nameOf(Object? ref) => ref is Map<String, Object?> ? ref['name'] as String? : null;
    final status = json['status'];
    final statusMap = status is Map<String, Object?> ? status : const <String, Object?>{};
    final folder = json['folder'];
    final folderHidden = folder is Map<String, Object?> && folder['hidden'] == true;
    return ClickUpTask(
      id: json['id'] as String? ?? '',
      customId: json['custom_id'] as String?,
      name: (json['name'] as String?)?.trim() ?? '',
      teamId: json['team_id'] as String? ?? teamId ?? '',
      status: statusMap['status'] as String? ?? '',
      statusColor: statusMap['color'] as String?,
      statusType: statusMap['type'] as String?,
      parentId: json['parent'] as String?,
      listName: nameOf(json['list']),
      folderName: folderHidden ? null : nameOf(folder),
      url: json['url'] as String?,
      dateUpdated: int.tryParse('${json['date_updated'] ?? ''}') ?? 0,
    );
  }
}

/// One page of tasks from "Get Filtered Team Tasks".
@immutable
class TaskPage {
  const TaskPage({required this.tasks, required this.lastPage});

  final List<ClickUpTask> tasks;
  final bool lastPage;
}

/// Time-entry upload state reported by the Android service.
@immutable
class SyncStatus {
  const SyncStatus({this.pending = 0, this.lastError, this.lastSyncedAt});

  static const SyncStatus empty = SyncStatus();

  final int pending;
  final String? lastError;
  final DateTime? lastSyncedAt;

  factory SyncStatus.fromMap(Map<Object?, Object?>? map) {
    if (map == null) return empty;
    final synced = (map['lastSyncedAt'] as num?)?.toInt() ?? 0;
    return SyncStatus(
      pending: (map['pending'] as num?)?.toInt() ?? 0,
      lastError: map['lastError'] as String?,
      lastSyncedAt: synced > 0 ? DateTime.fromMillisecondsSinceEpoch(synced) : null,
    );
  }
}

import 'package:flutter/foundation.dart';

/// The ClickUp task a timer logs its running time to.
@immutable
class TaskLink {
  const TaskLink({
    required this.taskId,
    required this.teamId,
    required this.name,
    this.url,
    this.customId,
  });

  final String taskId;

  /// The ClickUp workspace (called "team" in the API).
  final String teamId;

  /// The task name when it was linked or last refreshed.
  final String name;
  final String? url;
  final String? customId;

  TaskLink copyWith({String? name, String? url, String? customId}) => TaskLink(
    taskId: taskId,
    teamId: teamId,
    name: name ?? this.name,
    url: url ?? this.url,
    customId: customId ?? this.customId,
  );

  Map<String, Object?> toJson() => {
    'taskId': taskId,
    'teamId': teamId,
    'name': name,
    if (url != null) 'url': url,
    if (customId != null) 'customId': customId,
  };

  static TaskLink? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final taskId = json['taskId'];
    final teamId = json['teamId'];
    if (taskId is! String || teamId is! String || taskId.isEmpty) return null;
    return TaskLink(
      taskId: taskId,
      teamId: teamId,
      name: json['name'] as String? ?? '',
      url: json['url'] as String?,
      customId: json['customId'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TaskLink &&
      other.taskId == taskId &&
      other.teamId == teamId &&
      other.name == name &&
      other.url == url &&
      other.customId == customId;

  @override
  int get hashCode => Object.hash(taskId, teamId, name, url, customId);
}

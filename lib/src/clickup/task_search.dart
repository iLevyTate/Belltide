import 'clickup_models.dart';

/// Filters tasks on the device, since ClickUp's public API has no text search.
///
/// Every word in [query] must appear somewhere in the task: its name, custom id,
/// list, folder, status, or its parent task's name (so typing a parent finds its
/// subtasks). Name matches rank first, then the most recently updated.
List<ClickUpTask> searchTasks(List<ClickUpTask> tasks, String query) {
  final byId = {for (final t in tasks) t.id: t};
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) {
    return [...tasks]..sort((a, b) => b.dateUpdated.compareTo(a.dateUpdated));
  }

  final scored = <(ClickUpTask, int)>[];
  for (final task in tasks) {
    final name = task.name.toLowerCase();
    final parent = task.parentId == null ? '' : (byId[task.parentId]?.name.toLowerCase() ?? '');
    final haystack = [
      name,
      task.customId?.toLowerCase() ?? '',
      task.listName?.toLowerCase() ?? '',
      task.folderName?.toLowerCase() ?? '',
      task.status.toLowerCase(),
      parent,
    ].join('\n');
    if (!words.every(haystack.contains)) continue;

    final phrase = words.join(' ');
    var score = 0;
    if (name == phrase) {
      score = 4;
    } else if (name.startsWith(phrase)) {
      score = 3;
    } else if (words.every(name.contains)) {
      score = 2;
    } else if (task.customId?.toLowerCase() == phrase) {
      score = 4;
    } else {
      score = 1;
    }
    scored.add((task, score));
  }
  scored.sort((a, b) {
    final byScore = b.$2.compareTo(a.$2);
    return byScore != 0 ? byScore : b.$1.dateUpdated.compareTo(a.$1.dateUpdated);
  });
  return [for (final (task, _) in scored) task];
}

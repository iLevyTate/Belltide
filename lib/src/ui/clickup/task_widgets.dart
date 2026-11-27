import 'package:material_ui/material_ui.dart';

import '../../clickup/clickup_models.dart';
import '../../model/task_link.dart';
import '../../state/clickup_scope.dart';

Color? _parseHex(String? hex) {
  if (hex == null) return null;
  final digits = hex.replaceFirst('#', '');
  if (digits.length != 6) return null;
  final value = int.tryParse(digits, radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}

/// A ClickUp status in its own color, like ClickUp shows it.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status, this.color, this.dense = false});

  final String status;
  final String? color;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = _parseHex(color) ?? scheme.outline;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: dense ? 1 : 3),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: base.withValues(alpha: 0.6)),
      ),
      child: Text(
        status.toUpperCase(),
        style: (dense ? Theme.of(context).textTheme.labelSmall : Theme.of(context).textTheme.labelMedium)
            ?.copyWith(color: scheme.onSurface, letterSpacing: 0.3),
      ),
    );
  }
}

/// A row in task search results.
class TaskTile extends StatelessWidget {
  const TaskTile({super.key, required this.task, this.parent, required this.onTap, this.trailing});

  final ClickUpTask task;
  final ClickUpTask? parent;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = <String>[
      if (task.isSubtask) parent == null ? 'Subtask' : 'Subtask of ${parent!.name}',
      if (task.location.isNotEmpty) task.location,
      if (task.customId != null) task.customId!,
    ];
    return ListTile(
      leading: Icon(task.isSubtask ? Icons.subdirectory_arrow_right_rounded : Icons.task_alt_rounded),
      title: Text(task.name.isEmpty ? '(untitled task)' : task.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: details.isEmpty
          ? null
          : Text(
              details.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
      trailing: trailing ?? (task.status.isEmpty ? null : StatusChip(status: task.status, color: task.statusColor, dense: true)),
      onTap: onTap,
    );
  }
}

/// The linked task under a timer's summary. Tapping it opens the task in ClickUp.
class LinkedTaskRow extends StatelessWidget {
  const LinkedTaskRow({super.key, required this.link});

  final TaskLink link;

  @override
  Widget build(BuildContext context) {
    final clickUp = ClickUpScope.of(context);
    final theme = Theme.of(context);
    final task = clickUp.linkedTask(link.taskId);
    final missing = clickUp.isMissing(link.taskId);
    final name = task?.name ?? link.name;
    return Semantics(
      button: true,
      label: 'Open ClickUp task $name',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => clickUp.openTask(link),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(missing ? Icons.link_off_rounded : Icons.task_alt_rounded, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  missing ? '$name (not found in ClickUp)' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                ),
              ),
              if (task != null && task.status.isNotEmpty && !missing) ...[
                const SizedBox(width: 8),
                StatusChip(status: task.status, color: task.statusColor, dense: true),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

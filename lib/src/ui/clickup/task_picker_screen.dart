import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../clickup/clickup_api.dart';
import '../../clickup/clickup_models.dart';
import '../../model/timer_preset.dart';
import '../../state/belltide_scope.dart';
import '../../state/clickup_scope.dart';
import '../../util/format.dart';
import 'task_widgets.dart';

enum TaskPickerMode {
  /// Choose a task to link to a timer; the screen returns it.
  pick,

  /// Browse tasks and start a timer for one.
  browse,
}

Future<ClickUpTask?> pickClickUpTask(BuildContext context) => Navigator.of(context).push<ClickUpTask>(
  MaterialPageRoute(builder: (_) => const TaskPickerScreen(mode: TaskPickerMode.pick)),
);

Future<void> browseClickUpTasks(BuildContext context) => Navigator.of(context).push<void>(
  MaterialPageRoute(builder: (_) => const TaskPickerScreen(mode: TaskPickerMode.browse)),
);

/// Searches the user's ClickUp tasks and subtasks.
class TaskPickerScreen extends StatefulWidget {
  const TaskPickerScreen({super.key, required this.mode});

  final TaskPickerMode mode;

  @override
  State<TaskPickerScreen> createState() => _TaskPickerScreenState();
}

class _TaskPickerScreenState extends State<TaskPickerScreen> {
  final TextEditingController _query = TextEditingController();
  ClickUpTask? _lookedUp;
  String? _lookupError;
  bool _lookingUp = false;

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {
      _lookedUp = null;
      _lookupError = null;
    }));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ClickUpScope.read(context).loadTasks());
    });
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final clickUp = ClickUpScope.read(context);
    setState(() {
      _lookingUp = true;
      _lookupError = null;
    });
    try {
      final task = await clickUp.lookup(_query.text);
      if (!mounted) return;
      setState(() {
        _lookedUp = task;
        if (task == null) _lookupError = 'That doesn\'t look like a ClickUp task link or id.';
      });
    } on ClickUpException catch (e) {
      if (!mounted) return;
      setState(() => _lookupError = e.isNotFound ? 'No task with that id in ClickUp.' : e.message);
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  void _select(ClickUpTask task) {
    final clickUp = ClickUpScope.read(context);
    clickUp.rememberTask(task);
    if (widget.mode == TaskPickerMode.pick) {
      Navigator.pop(context, task);
    } else {
      showStartForTaskSheet(context, task);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clickUp = ClickUpScope.of(context);
    final theme = Theme.of(context);
    final query = _query.text;
    final results = clickUp.search(query);
    final workspaceId = clickUp.account?.workspaceId ?? '';
    final canLookup = TaskReference.parse(query, teamId: workspaceId) != null;

    final children = <Widget>[
      if (canLookup)
        ListTile(
          leading: _lookingUp
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.open_in_new_rounded),
          title: Text('Find task "${query.trim()}" in ClickUp'),
          subtitle: _lookupError == null ? const Text('Looks up a pasted task link or id directly') : Text(_lookupError!),
          onTap: _lookingUp ? null : _lookup,
        ),
      if (_lookedUp != null) TaskTile(task: _lookedUp!, parent: clickUp.parentOf(_lookedUp!), onTap: () => _select(_lookedUp!)),
      if (clickUp.tasksError != null)
        _Notice(icon: Icons.error_outline, text: clickUp.tasksError!, color: theme.colorScheme.error),
      for (final task in results)
        TaskTile(key: ValueKey(task.id), task: task, parent: clickUp.parentOf(task), onTap: () => _select(task)),
      if (clickUp.loadingTasks)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
      else if (clickUp.tasksLoaded) ...[
        if (results.isEmpty && clickUp.tasksError == null)
          _Notice(
            icon: Icons.search_off_rounded,
            text: query.trim().isEmpty
                ? (clickUp.onlyMine ? 'No open tasks are assigned to you.' : 'No open tasks in this workspace.')
                : 'No match in the ${clickUp.tasks.length} tasks loaded. Load more, turn off "Assigned to me", '
                      'or paste a task link.',
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Searching ${clickUp.tasks.length} tasks and subtasks, most recently updated first',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              if (clickUp.hasMoreTasks)
                TextButton(onPressed: clickUp.loadMoreTasks, child: const Text('Load more')),
            ],
          ),
        ),
      ],
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.mode == TaskPickerMode.pick ? 'Link a ClickUp task' : 'ClickUp tasks'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(116),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _query,
                  autofocus: widget.mode == TaskPickerMode.pick,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) {
                    if (canLookup && results.isEmpty) _lookup();
                  },
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search tasks, or paste a task link',
                    isDense: true,
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.clear),
                            onPressed: _query.clear,
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('Assigned to me'),
                        selected: clickUp.onlyMine,
                        onSelected: clickUp.setOnlyMine,
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('Include closed'),
                        selected: clickUp.includeClosed,
                        onSelected: clickUp.setIncludeClosed,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => clickUp.loadTasks(refresh: true),
        child: ListView(children: children),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color ?? theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: color))),
        ],
      ),
    );
  }
}

/// Starts a timer for [task]: an existing linked timer, or a linked copy of one
/// of the saved timers. Several tasks can each have a timer running at once.
Future<void> showStartForTaskSheet(BuildContext context, ClickUpTask task) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final controller = BelltideScope.of(sheetContext);
      final clickUp = ClickUpScope.read(sheetContext);
      final theme = Theme.of(sheetContext);
      final linked = controller.presetsForTask(task.id);
      final templates = controller.presets.where((p) => p.task == null).toList();
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);

      Future<void> startAndReturn(TimerPreset preset) async {
        await controller.start(preset);
        navigator.popUntil((route) => route.isFirst);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Started ${preset.displayName} for ${task.name}')));
      }

      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scroll) => ListView(
          controller: scroll,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
              child: Text(task.name, style: theme.textTheme.titleLarge),
            ),
            if (task.location.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(task.location, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => clickUp.openTask(task.toLink()),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open in ClickUp'),
                ),
              ),
            ),
            if (linked.isNotEmpty) ...[
              const _SheetHeader('Timers for this task'),
              for (final preset in linked)
                ListTile(
                  leading: Icon(preset.isInterval ? Icons.notifications_active_outlined : Icons.repeat_rounded),
                  title: Text(preset.displayName),
                  subtitle: Text(presetSummary(preset), maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: controller.isOn(preset.id)
                      ? const Text('Running')
                      : FilledButton.tonal(onPressed: () => startAndReturn(preset), child: const Text('Start')),
                ),
            ],
            const _SheetHeader('Start with one of your timers'),
            if (templates.isEmpty)
              const ListTile(title: Text('Create a timer first, then come back to link it.'))
            else
              for (final template in templates)
                ListTile(
                  leading: Icon(template.isInterval ? Icons.notifications_active_outlined : Icons.repeat_rounded),
                  title: Text(template.displayName),
                  subtitle: Text(presetSummary(template), maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.play_arrow_rounded),
                  onTap: () async {
                    final copy = await controller.createLinkedCopy(template, task.toLink());
                    await startAndReturn(copy);
                  },
                ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Text(
                'Starting from one of your timers saves a copy linked to this task. '
                'Its running time is logged to the task when it pauses, stops or finishes.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
      child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}

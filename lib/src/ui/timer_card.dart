import 'package:material_ui/material_ui.dart';

import '../model/timer_preset.dart';
import '../state/belltide_scope.dart';
import '../util/format.dart';
import 'clickup/task_widgets.dart';
import 'editor_screen.dart';
import 'running_panel.dart';

/// A saved timer on the home screen, with its on/off switch and live status.
class TimerCard extends StatelessWidget {
  const TimerCard({super.key, required this.preset});

  final TimerPreset preset;

  @override
  Widget build(BuildContext context) {
    final controller = BelltideScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final running = controller.runningTimer(preset.id);
    final on = controller.isOn(preset.id);

    return Card(
      clipBehavior: Clip.antiAlias,
      color: on ? scheme.secondaryContainer : null,
      child: InkWell(
        onTap: () => openEditor(context, preset),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    preset.isInterval ? Icons.notifications_active_outlined : Icons.repeat_rounded,
                    color: on ? scheme.onSecondaryContainer : scheme.primary,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(preset.displayName, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          presetSummary(preset),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        Text(
                          presetDetail(preset),
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        if (preset.task case final link?) LinkedTaskRow(link: link),
                      ],
                    ),
                  ),
                  _CardMenu(preset: preset),
                  Semantics(
                    label: on ? 'Stop ${preset.displayName}' : 'Start ${preset.displayName}',
                    child: Switch(
                      value: on,
                      onChanged: (value) => controller.setRunning(preset, value),
                    ),
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: running == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: RunningPanel(timer: running),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _MenuAction { duplicate, delete }

class _CardMenu extends StatelessWidget {
  const _CardMenu({required this.preset});

  final TimerPreset preset;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_MenuAction>(
      tooltip: 'More for ${preset.displayName}',
      icon: const Icon(Icons.more_vert),
      onSelected: (action) async {
        final controller = BelltideScope.read(context);
        final messenger = ScaffoldMessenger.of(context);
        switch (action) {
          case _MenuAction.duplicate:
            await controller.duplicatePreset(preset.id);
          case _MenuAction.delete:
            final index = await controller.deletePreset(preset.id);
            if (index < 0) return;
            messenger
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text('Deleted ${preset.displayName}'),
                  action: SnackBarAction(
                    label: 'Undo',
                    onPressed: () => controller.restorePreset(preset, index),
                  ),
                ),
              );
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: _MenuAction.duplicate, child: Text('Duplicate')),
        PopupMenuItem(value: _MenuAction.delete, child: Text('Delete')),
      ],
    );
  }
}

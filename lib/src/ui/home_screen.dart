import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../model/timer_preset.dart';
import '../state/belltide_scope.dart';
import 'editor_screen.dart';
import 'settings_screen.dart';
import 'timer_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription<String>? _finished;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _finished ??= BelltideScope.read(context).finishedTimers.listen((name) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$name finished')));
    });
  }

  @override
  void dispose() {
    _finished?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = BelltideScope.of(context);
    final presets = controller.presets;

    final Widget body;
    if (!controller.loaded) {
      body = const Center(child: CircularProgressIndicator());
    } else if (presets.isEmpty) {
      body = _EmptyState(onCreate: (kind) => _create(context, kind));
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
        itemCount: presets.length,
        itemBuilder: (context, i) => TimerCard(key: ValueKey(presets[i].id), preset: presets[i]),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Belltide'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: body,
      floatingActionButton: presets.isEmpty && controller.loaded
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _chooseKind(context),
              icon: const Icon(Icons.add),
              label: const Text('New timer'),
            ),
    );
  }

  Future<void> _chooseKind(BuildContext context) async {
    final kind = await showModalBottomSheet<TimerKind>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('New timer', style: Theme.of(context).textTheme.titleLarge),
            ),
            for (final kind in TimerKind.values)
              ListTile(
                leading: Icon(_kindIcon(kind)),
                title: Text(_kindTitle(kind)),
                subtitle: Text(_kindDescription(kind)),
                onTap: () => Navigator.pop(context, kind),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (kind != null && context.mounted) await _create(context, kind);
  }

  Future<void> _create(BuildContext context, TimerKind kind) {
    final draft = BelltideScope.read(context).draft(kind);
    return openEditor(context, draft, isNew: true);
  }
}

IconData _kindIcon(TimerKind kind) =>
    kind == TimerKind.interval ? Icons.notifications_active_outlined : Icons.repeat_rounded;

String _kindTitle(TimerKind kind) => kind == TimerKind.interval ? 'Interval chime' : 'Sequence';

String _kindDescription(TimerKind kind) => kind == TimerKind.interval
    ? 'A chime every few minutes, until you stop it or for a set count.'
    : 'Steps like hold and rest, each with its own sound, repeated for rounds.';

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final ValueChanged<TimerKind> onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none_rounded, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('No timers yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Create a chime that rings on an interval, or a sequence of steps with their own sounds.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            for (final kind in TimerKind.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton.tonalIcon(
                  onPressed: () => onCreate(kind),
                  icon: Icon(_kindIcon(kind)),
                  label: Text(_kindTitle(kind)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

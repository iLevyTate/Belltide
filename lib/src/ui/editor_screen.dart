import 'package:material_ui/material_ui.dart';

import '../model/chime_sound.dart';
import '../model/timer_preset.dart';
import '../state/belltide_controller.dart';
import '../state/belltide_scope.dart';
import '../util/format.dart';
import 'common.dart';
import 'duration_picker.dart';
import 'sound_picker.dart';

Future<void> openEditor(BuildContext context, TimerPreset preset, {bool isNew = false}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => EditorScreen(initial: preset, isNew: isNew)),
  );
}

/// Creates or edits an interval chime or a sequence.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.initial, this.isNew = false});

  final TimerPreset initial;
  final bool isNew;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final TextEditingController _name = TextEditingController(text: widget.initial.name);
  late TimerPreset _draft = widget.initial;
  final Map<String, TextEditingController> _labels = {};

  static const List<ChimeSound> _stepSoundRotation = [
    ChimeSound.bell,
    ChimeSound.wood,
    ChimeSound.chime,
    ChimeSound.doubleBell,
    ChimeSound.bowl,
    ChimeSound.beep,
  ];

  static const List<Duration> _leadInChoices = [
    Duration.zero,
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  /// Whether the back button should ask before discarding; see [_onTextChanged].
  bool _shownDirty = false;

  BelltideController get _controller => BelltideScope.read(context);

  @override
  void initState() {
    super.initState();
    _name.addListener(_onTextChanged);
  }

  /// Text edits don't go through [_update], so rebuild when they first make the
  /// draft differ from the saved timer (or stop doing so).
  void _onTextChanged() {
    final dirty = _dirty;
    if (dirty != _shownDirty) setState(() => _shownDirty = dirty);
  }

  @override
  void dispose() {
    _name.dispose();
    for (final c in _labels.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _labelFor(TimerStep step) => _labels.putIfAbsent(
    step.id,
    () => TextEditingController(text: step.label)..addListener(_onTextChanged),
  );

  /// The draft with the latest text from the name and step label fields.
  TimerPreset get _current => _draft.copyWith(
    name: _name.text.trim(),
    steps: [for (final s in _draft.steps) s.copyWith(label: _labels[s.id]?.text.trim() ?? s.label)],
  );

  bool get _dirty => _current != widget.initial;

  void _update(TimerPreset Function(TimerPreset p) change) => setState(() {
    _draft = change(_draft);
    _shownDirty = _dirty;
  });

  void _updateStep(int index, TimerStep Function(TimerStep s) change) => _update(
    (p) => p.copyWith(steps: [...p.steps]..[index] = change(p.steps[index])),
  );

  void _preview(ChimeSound sound) => _controller.preview(sound);

  @override
  Widget build(BuildContext context) {
    final p = _draft;
    final title = widget.isNew
        ? (p.isInterval ? 'New interval chime' : 'New sequence')
        : 'Edit timer';

    return PopScope(
      canPop: !_shownDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            if (!widget.isNew)
              IconButton(
                tooltip: 'Delete timer',
                icon: const Icon(Icons.delete_outline),
                onPressed: _delete,
              ),
          ],
        ),
        body: p.isInterval ? _intervalBody(p) : _sequenceBody(p),
        bottomNavigationBar: _SaveBar(summary: _summary(p), onSave: _save),
      ),
    );
  }

  Widget _nameField(String hint) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: TextField(
      controller: _name,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(labelText: 'Name', hintText: hint),
    ),
  );

  Widget _intervalBody(TimerPreset p) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _nameField('Mindful bell'),
        const SectionHeader('Chime'),
        ValueTile(
          icon: Icons.timer_outlined,
          title: 'Every',
          value: formatSpan(p.every),
          onTap: () async {
            final picked = await showDurationPicker(
              context,
              initial: p.every,
              title: 'Chime every',
              quickPicks: intervalQuickPicks,
            );
            if (picked != null) _updateStep(0, (s) => s.copyWith(duration: picked));
          },
        ),
        SoundTile(
          title: 'Sound',
          sound: p.intervalSound,
          allowSilent: false,
          onPreview: _preview,
          onChanged: (sound) => _update(
            (p) => p.copyWith(steps: [p.steps.first.copyWith(sound: sound)], finishSound: sound),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.play_circle_outline),
          title: const Text('Chime when started'),
          subtitle: const Text('Ring once as soon as you turn it on'),
          value: p.startChime,
          onChanged: (v) => _update((p) => p.copyWith(startChime: v)),
        ),
        const SectionHeader('Length'),
        SwitchListTile(
          secondary: const Icon(Icons.all_inclusive),
          title: const Text('Repeat until stopped'),
          value: p.repeatsForever,
          onChanged: (v) => _update((p) => p.copyWith(rounds: v ? 0 : 12)),
        ),
        if (!p.repeatsForever)
          CountTile(
            icon: Icons.tag,
            title: 'Number of chimes',
            value: p.rounds,
            max: TimerPreset.maxRounds,
            onChanged: (v) => _update((p) => p.copyWith(rounds: v)),
          ),
      ],
    );
  }

  Widget _sequenceBody(TimerPreset p) {
    final theme = Theme.of(context);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _nameField('Stretch holds'),
              SectionHeader('Steps', trailing: '${formatSpan(p.cycle)} per round'),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverReorderableList(
            itemCount: p.steps.length,
            onReorderItem: (from, to) => _update((p) {
              final steps = [...p.steps];
              steps.insert(to, steps.removeAt(from));
              return p.copyWith(steps: steps);
            }),
            proxyDecorator: (child, index, animation) => Material(
              elevation: 4,
              color: Colors.transparent,
              shadowColor: theme.colorScheme.shadow,
              borderRadius: BorderRadius.circular(20),
              child: child,
            ),
            itemBuilder: (context, i) {
              final step = p.steps[i];
              return _StepCard(
                key: ValueKey(step.id),
                index: i,
                step: step,
                label: _labelFor(step),
                canRemove: p.steps.length > 1,
                onPickDuration: () async {
                  final picked = await showDurationPicker(
                    context,
                    initial: step.duration,
                    title: '${_labelFor(step).text.trim().isEmpty ? 'Step' : _labelFor(step).text.trim()} length',
                  );
                  if (picked != null) _updateStep(i, (s) => s.copyWith(duration: picked));
                },
                onSoundChanged: (sound) => _updateStep(i, (s) => s.copyWith(sound: sound)),
                onPreview: _preview,
                onRemove: () => _update((p) => p.copyWith(steps: [...p.steps]..removeAt(i))),
              );
            },
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: OutlinedButton.icon(
              onPressed: _addStep,
              icon: const Icon(Icons.add),
              label: const Text('Add step'),
            ),
          ),
        ),
        SliverList.list(
          children: [
            const SectionHeader('Rounds'),
            SwitchListTile(
              secondary: const Icon(Icons.all_inclusive),
              title: const Text('Repeat until stopped'),
              value: p.repeatsForever,
              onChanged: (v) => _update((p) => p.copyWith(rounds: v ? 0 : 10)),
            ),
            if (!p.repeatsForever)
              CountTile(
                icon: Icons.repeat_rounded,
                title: 'Rounds',
                value: p.rounds,
                max: TimerPreset.maxRounds,
                onChanged: (v) => _update((p) => p.copyWith(rounds: v)),
              ),
            const SectionHeader('Start and finish'),
            ValueTile(
              icon: Icons.hourglass_top_rounded,
              title: 'Get ready countdown',
              value: p.leadIn == Duration.zero ? 'Off' : formatSpan(p.leadIn),
              onTap: _pickLeadIn,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.play_circle_outline),
              title: const Text('Chime when the first step starts'),
              value: p.startChime,
              onChanged: (v) => _update((p) => p.copyWith(startChime: v)),
            ),
            if (!p.repeatsForever)
              SoundTile(
                title: 'Finish sound',
                sound: p.finishSound,
                onPreview: _preview,
                onChanged: (sound) => _update((p) => p.copyWith(finishSound: sound)),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ],
    );
  }

  void _addStep() {
    final steps = _draft.steps;
    final last = steps.last;
    final sound = _stepSoundRotation[steps.length % _stepSoundRotation.length];
    _update(
      (p) => p.copyWith(
        steps: [
          ...p.steps,
          TimerStep(
            id: _controller.newStepId(),
            label: 'Step ${steps.length + 1}',
            duration: last.duration,
            sound: sound,
          ),
        ],
      ),
    );
  }

  Future<void> _pickLeadIn() async {
    final picked = await showModalBottomSheet<Duration>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('Get ready countdown', style: Theme.of(context).textTheme.titleLarge),
            ),
            for (final d in _leadInChoices)
              ListTile(
                leading: Icon(
                  d == _draft.leadIn ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                ),
                title: Text(d == Duration.zero ? 'Off' : formatSpan(d)),
                onTap: () => Navigator.pop(context, d),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) _update((p) => p.copyWith(leadIn: picked));
  }

  String _summary(TimerPreset p) {
    if (p.isInterval) {
      return p.repeatsForever
          ? 'Rings every ${formatSpan(p.every)} until you stop it'
          : '${p.rounds} ${p.rounds == 1 ? 'chime' : 'chimes'} · ${formatSpan(p.total!)} total';
    }
    if (p.repeatsForever) return '${formatSpan(p.cycle)} per round · repeats until stopped';
    return presetDetail(p);
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your changes to this timer will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep editing')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
        ],
      ),
    );
    return discard ?? false;
  }

  Future<void> _save() async {
    final preset = _current;
    final messenger = ScaffoldMessenger.of(context);
    final error = preset.validate();
    if (error != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final controller = _controller;
    final navigator = Navigator.of(context);
    final wasRunning = controller.isOn(preset.id);
    final changed = preset != widget.initial;
    await controller.savePreset(preset);
    if (!mounted) return;
    // Navigator.pop is not blocked by PopScope, so no discard prompt appears.
    navigator.pop();
    if (wasRunning && changed) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Saved. ${preset.displayName} keeps its old pattern until restarted.'),
            action: SnackBarAction(label: 'Restart', onPressed: () => controller.start(preset)),
          ),
        );
    }
  }

  Future<void> _delete() async {
    final preset = widget.initial;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${preset.displayName}?'),
        content: const Text('If it is running, it stops.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final controller = _controller;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final index = await controller.deletePreset(preset.id);
    if (!mounted) return;
    navigator.pop();
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
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    super.key,
    required this.index,
    required this.step,
    required this.label,
    required this.canRemove,
    required this.onPickDuration,
    required this.onSoundChanged,
    required this.onPreview,
    required this.onRemove,
  });

  final int index;
  final TimerStep step;
  final TextEditingController label;
  final bool canRemove;
  final VoidCallback onPickDuration;
  final ValueChanged<ChimeSound> onSoundChanged;
  final ValueChanged<ChimeSound> onPreview;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Semantics(
                    label: 'Reorder step ${index + 1}',
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.drag_indicator),
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: label,
                    textCapitalization: TextCapitalization.sentences,
                    style: theme.textTheme.titleMedium,
                    decoration: InputDecoration(
                      hintText: 'Step ${index + 1} name',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                if (canRemove)
                  IconButton(
                    tooltip: 'Remove step',
                    icon: const Icon(Icons.close),
                    onPressed: onRemove,
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.timer_outlined, size: 18),
                    label: Text(formatSpan(step.duration)),
                    tooltip: 'Change length',
                    onPressed: onPickDuration,
                  ),
                  ActionChip(
                    avatar: Icon(
                      step.sound.isSilent ? Icons.volume_off_outlined : Icons.music_note_outlined,
                      size: 18,
                    ),
                    label: Text(step.sound.label),
                    tooltip: 'Change sound',
                    onPressed: () async {
                      final picked = await showSoundPickerFor(context, step.sound, onPreview);
                      if (picked != null) onSoundChanged(picked);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.summary, required this.onSave});

  final String summary;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  summary,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.check),
                label: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

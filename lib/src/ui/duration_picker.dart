import 'package:material_ui/material_ui.dart';

import '../util/format.dart';
import 'theme.dart';

const List<Duration> stepQuickPicks = [
  Duration(seconds: 5),
  Duration(seconds: 10),
  Duration(seconds: 30),
  Duration(minutes: 1),
  Duration(minutes: 5),
  Duration(minutes: 25),
];

const List<Duration> intervalQuickPicks = [
  Duration(minutes: 1),
  Duration(minutes: 5),
  Duration(minutes: 10),
  Duration(minutes: 15),
  Duration(minutes: 30),
  Duration(hours: 1),
];

/// Hours, minutes and seconds wheels with a row of common lengths.
Future<Duration?> showDurationPicker(
  BuildContext context, {
  required Duration initial,
  String title = 'Length',
  List<Duration> quickPicks = stepQuickPicks,
}) {
  return showModalBottomSheet<Duration>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _DurationPickerSheet(initial: initial, title: title, quickPicks: quickPicks),
  );
}

class _DurationPickerSheet extends StatefulWidget {
  const _DurationPickerSheet({required this.initial, required this.title, required this.quickPicks});

  final Duration initial;
  final String title;
  final List<Duration> quickPicks;

  @override
  State<_DurationPickerSheet> createState() => _DurationPickerSheetState();
}

class _DurationPickerSheetState extends State<_DurationPickerSheet> {
  late int _h = widget.initial.inHours.clamp(0, 23);
  late int _m = widget.initial.inMinutes % 60;
  late int _s = widget.initial.inSeconds % 60;
  late final _hours = FixedExtentScrollController(initialItem: _h);
  late final _minutes = FixedExtentScrollController(initialItem: _m);
  late final _seconds = FixedExtentScrollController(initialItem: _s);

  Duration get _value => Duration(hours: _h, minutes: _m, seconds: _s);

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    _seconds.dispose();
    super.dispose();
  }

  void _setQuick(Duration d) {
    setState(() {
      _h = d.inHours.clamp(0, 23);
      _m = d.inMinutes % 60;
      _s = d.inSeconds % 60;
    });
    const curve = Curves.easeOutCubic;
    const duration = Duration(milliseconds: 250);
    _hours.animateToItem(_h, duration: duration, curve: curve);
    _minutes.animateToItem(_m, duration: duration, curve: curve);
    _seconds.animateToItem(_s, duration: duration, curve: curve);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valid = _value >= const Duration(seconds: 1);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final d in widget.quickPicks)
                  ChoiceChip(
                    label: Text(formatSpan(d)),
                    selected: d == _value,
                    onSelected: (_) => _setQuick(d),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Wheel(
                        controller: _hours,
                        count: 24,
                        unit: 'h',
                        semanticsLabel: 'Hours',
                        onChanged: (v) => setState(() => _h = v),
                      ),
                      _Wheel(
                        controller: _minutes,
                        count: 60,
                        unit: 'min',
                        semanticsLabel: 'Minutes',
                        onChanged: (v) => setState(() => _m = v),
                      ),
                      _Wheel(
                        controller: _seconds,
                        count: 60,
                        unit: 's',
                        semanticsLabel: 'Seconds',
                        onChanged: (v) => setState(() => _s = v),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    valid ? formatSpan(_value) : 'Pick at least 1 second',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: valid ? theme.colorScheme.onSurface : theme.colorScheme.error,
                    ),
                  ),
                ),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: valid ? () => Navigator.pop(context, _value) : null,
                  child: const Text('Set'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Wheel extends StatelessWidget {
  const _Wheel({
    required this.controller,
    required this.count,
    required this.unit,
    required this.semanticsLabel,
    required this.onChanged,
  });

  final FixedExtentScrollController controller;
  final int count;
  final String unit;
  final String semanticsLabel;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.headlineSmall?.copyWith(fontFeatures: tabularFigures);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 56,
          child: Semantics(
            label: semanticsLabel,
            child: ListWheelScrollView.useDelegate(
              controller: controller,
              itemExtent: 48,
              diameterRatio: 1.5,
              overAndUnderCenterOpacity: 0.4,
              physics: const FixedExtentScrollPhysics(),
              onSelectedItemChanged: onChanged,
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: count,
                builder: (context, i) => Center(child: Text(i.toString().padLeft(2, '0'), style: style)),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(unit, style: theme.textTheme.bodyMedium),
        ),
      ],
    );
  }
}

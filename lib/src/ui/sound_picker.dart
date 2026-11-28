import 'package:material_ui/material_ui.dart';

import '../model/chime_sound.dart';

/// Lets the user choose a chime. Tapping a sound plays it, so several can be
/// compared; the button at the bottom confirms the choice. Returns null when
/// the sheet is dismissed without choosing.
Future<ChimeSound?> showSoundPicker(
  BuildContext context, {
  required ChimeSound current,
  required ValueChanged<ChimeSound> onPreview,
  bool allowSilent = true,
}) {
  return showModalBottomSheet<ChimeSound>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) =>
        _SoundPickerSheet(current: current, onPreview: onPreview, allowSilent: allowSilent),
  );
}

/// [showSoundPicker] for a sequence step, where silence is allowed.
Future<ChimeSound?> showSoundPickerFor(
  BuildContext context,
  ChimeSound current,
  ValueChanged<ChimeSound> onPreview,
) => showSoundPicker(context, current: current, onPreview: onPreview);

class _SoundPickerSheet extends StatefulWidget {
  const _SoundPickerSheet({
    required this.current,
    required this.onPreview,
    required this.allowSilent,
  });

  final ChimeSound current;
  final ValueChanged<ChimeSound> onPreview;
  final bool allowSilent;

  @override
  State<_SoundPickerSheet> createState() => _SoundPickerSheetState();
}

class _SoundPickerSheetState extends State<_SoundPickerSheet> {
  late ChimeSound _selected = widget.current;
  final GlobalKey _currentKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Open with the current sound in view, wherever it is in the list.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _currentKey.currentContext;
      if (row != null) Scrollable.ensureVisible(row, alignment: 0.3);
    });
  }

  void _select(ChimeSound sound) {
    setState(() => _selected = sound);
    if (!sound.isSilent) widget.onPreview(sound);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget row(ChimeSound sound) {
      final selected = sound == _selected;
      return Padding(
        key: sound == widget.current ? _currentKey : null,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          selected: selected,
          selectedTileColor: scheme.secondaryContainer,
          selectedColor: scheme.onSecondaryContainer,
          leading: Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          ),
          title: Text(sound.label),
          subtitle: Text(sound.description),
          trailing: sound.isSilent
              ? const Icon(Icons.volume_off_outlined)
              : Icon(
                  selected ? Icons.volume_up_rounded : Icons.play_arrow_rounded,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  semanticLabel: selected ? 'Play again' : 'Play',
                ),
          onTap: () => _select(sound),
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
            child: Text('Sound', style: theme.textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Tap a sound to hear it.',
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final group in ChimeGroup.values) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 6),
                      child: Semantics(
                        header: true,
                        child: Text(
                          group.label,
                          style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary),
                        ),
                      ),
                    ),
                    for (final sound in ChimeSound.inGroup(group)) row(sound),
                  ],
                  if (widget.allowSilent) ...[
                    const Divider(height: 24, indent: 24, endIndent: 24),
                    row(ChimeSound.none),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () => Navigator.pop(context, _selected),
              child: Text('Use ${_selected.label}'),
            ),
          ),
        ],
      ),
    );
  }
}

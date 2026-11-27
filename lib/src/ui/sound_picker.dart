import 'package:material_ui/material_ui.dart';

import '../model/chime_sound.dart';

/// Lets the user choose a chime. Choosing one also plays it.
Future<ChimeSound?> showSoundPicker(
  BuildContext context, {
  required ChimeSound current,
  required ValueChanged<ChimeSound> onPreview,
  bool allowSilent = true,
}) {
  final options = [...ChimeSound.audible, if (allowSilent) ChimeSound.none];
  return showModalBottomSheet<ChimeSound>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('Sound', style: Theme.of(context).textTheme.titleLarge),
            ),
            for (final sound in options)
              ListTile(
                leading: Icon(
                  sound == current ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: sound == current ? scheme.primary : scheme.onSurfaceVariant,
                ),
                title: Text(sound.label),
                selected: sound == current,
                trailing: sound.isSilent
                    ? null
                    : IconButton(
                        tooltip: 'Play ${sound.label}',
                        icon: const Icon(Icons.play_circle_outline),
                        onPressed: () => onPreview(sound),
                      ),
                onTap: () {
                  if (!sound.isSilent) onPreview(sound);
                  Navigator.pop(context, sound);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// [showSoundPicker] for a sequence step, where silence is allowed.
Future<ChimeSound?> showSoundPickerFor(
  BuildContext context,
  ChimeSound current,
  ValueChanged<ChimeSound> onPreview,
) => showSoundPicker(context, current: current, onPreview: onPreview);

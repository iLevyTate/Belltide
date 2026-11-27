import 'package:material_ui/material_ui.dart';

import '../model/chime_sound.dart';
import 'sound_picker.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

/// A row that shows a value and opens a picker when tapped.
class ValueTile extends StatelessWidget {
  const ValueTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String value;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: Text(
        value,
        style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary),
      ),
      onTap: onTap,
    );
  }
}

/// Picks a chime, with a preview button.
class SoundTile extends StatelessWidget {
  const SoundTile({
    super.key,
    required this.title,
    required this.sound,
    required this.onChanged,
    required this.onPreview,
    this.allowSilent = true,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final ChimeSound sound;
  final bool allowSilent;
  final ValueChanged<ChimeSound> onChanged;
  final ValueChanged<ChimeSound> onPreview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(sound.isSilent ? Icons.volume_off_outlined : Icons.music_note_outlined),
      title: Text(title),
      subtitle: Text(subtitle ?? sound.label),
      trailing: sound.isSilent
          ? null
          : IconButton(
              tooltip: 'Play ${sound.label}',
              icon: Icon(Icons.play_circle_outline, color: theme.colorScheme.primary),
              onPressed: () => onPreview(sound),
            ),
      onTap: () async {
        final picked = await showSoundPicker(
          context,
          current: sound,
          allowSilent: allowSilent,
          onPreview: onPreview,
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

/// A number with minus and plus buttons. Tapping the number lets the user type it.
class CountTile extends StatelessWidget {
  const CountTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 999,
  });

  final IconData icon;
  final String title;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Fewer',
            icon: const Icon(Icons.remove),
            onPressed: value > min ? () => onChanged(value - 1) : null,
          ),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _typeValue(context),
            child: Container(
              constraints: const BoxConstraints(minWidth: 44),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              alignment: Alignment.center,
              child: Text(
                '$value',
                style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary),
              ),
            ),
          ),
          IconButton(
            tooltip: 'More',
            icon: const Icon(Icons.add),
            onPressed: value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }

  Future<void> _typeValue(BuildContext context) async {
    final controller = TextEditingController(text: '$value');
    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        void submit() {
          final parsed = int.tryParse(controller.text.trim());
          if (parsed != null) Navigator.pop(context, parsed.clamp(min, max));
        }

        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(helperText: 'From $min to $max'),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: submit, child: const Text('Set')),
          ],
        );
      },
    );
    controller.dispose();
    if (result != null) onChanged(result);
  }
}

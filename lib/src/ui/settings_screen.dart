import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app_info.dart';
import '../model/app_settings.dart';
import '../model/audio_status.dart';
import '../model/chime_sound.dart';
import '../state/belltide_scope.dart';
import '../state/clickup_scope.dart';
import 'brand_mark.dart';
import 'clickup/clickup_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _notificationsAllowed;
  bool? _batteryUnrestricted;
  AudioStatus? _audio;
  StreamSubscription<void>? _audioChanges;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The volume buttons and the ringer switch work while this screen is open.
    _audioChanges ??= BelltideScope.read(context).engine.audioChanges.listen((_) => _refreshAudio());
  }

  @override
  void dispose() {
    _audioChanges?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  /// Permission state can change in system settings while the app is open.
  Future<void> _refresh() async {
    final engine = BelltideScope.read(context).engine;
    bool? notifications;
    bool? battery;
    try {
      notifications = await engine.notificationsAllowed();
      battery = await engine.isIgnoringBatteryOptimizations();
    } catch (_) {
      // Leave unknown; the tiles explain both states.
    }
    if (!mounted) return;
    setState(() {
      _notificationsAllowed = notifications;
      _batteryUnrestricted = battery;
    });
    await _refreshAudio();
  }

  Future<void> _refreshAudio() async {
    AudioStatus? audio;
    try {
      audio = await BelltideScope.read(context).engine.audioStatus();
    } catch (_) {
      // Leave unknown; the volume tile still opens the phone's sliders.
    }
    if (!mounted) return;
    setState(() => _audio = audio);
  }

  Future<void> _enableNotifications() async {
    final engine = BelltideScope.read(context).engine;
    final granted = await engine.requestNotificationPermission();
    // After two refusals Android stops asking; send the user to settings instead.
    if (!granted) await engine.openNotificationSettings();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final controller = BelltideScope.of(context);
    final settings = controller.settings;
    final theme = Theme.of(context);
    final audio = _audio;
    // Through headphones chimes use the media volume, whichever one was chosen.
    final volumeNow = audio?.volumeFor(settings.volume) ?? settings.volume;
    final viaHeadphones = audio != null && audio.headphones && settings.volume != volumeNow;
    final volumeHint = viaHeadphones
        ? 'Used while headphones or a speaker are connected. The volume buttons change it '
              'while Belltide is open.'
        : 'The volume buttons change it while Belltide is open.';

    Widget volumeOption(ChimeVolume volume, String title, String subtitle) {
      final selected = settings.volume == volume;
      return ListTile(
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: selected ? theme.colorScheme.primary : null,
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        onTap: () async {
          await controller.updateSettings(settings.copyWith(volume: volume));
          // The phone volume shown above belongs to the volume just chosen.
          await _refreshAudio();
        },
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const _Header('Chime volume'),
          _LevelTile(
            level: settings.level,
            onChanged: (level) async {
              await controller.updateSettings(settings.copyWith(level: level));
              if (level > 0) await controller.preview(ChimeSound.bell);
            },
          ),
          ListTile(
            leading: Icon(audio?.muted == true ? Icons.volume_off_outlined : Icons.tune_rounded),
            title: Text('Phone ${volumeNow.label}'),
            subtitle: Text(switch (audio) {
              null => volumeHint,
              AudioStatus(muted: true) => 'Off. Chimes can\'t be heard until you turn it up.',
              _ => '${audio.volume} of ${audio.maxVolume}. $volumeHint',
            }),
            trailing: TextButton(
              onPressed: () => controller.engine.openVolumeSettings(),
              child: const Text('Adjust'),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.graphic_eq_rounded),
            title: const Text('Lower other audio during chimes'),
            subtitle: const Text(
              'Music and videos dip for a moment so a chime is easy to hear, then come '
              'back. Some apps pause instead.',
            ),
            value: settings.duckOthers,
            onChanged: (v) => controller.updateSettings(settings.copyWith(duckOthers: v)),
          ),
          const _Header('Chimes follow'),
          volumeOption(
            ChimeVolume.alarm,
            'Alarm volume',
            'Uses your alarm volume on the phone speaker. Through headphones or a '
                'Bluetooth speaker, chimes use your media volume so they mix with what '
                'you are listening to.',
          ),
          volumeOption(
            ChimeVolume.media,
            'Media volume',
            'Always uses your media volume, on the phone speaker too.',
          ),
          const _Header('Vibrate and silent'),
          if (audio != null && audio.silenced)
            _RingerNotice(
              ringer: audio.ringer,
              message: settings.vibrateWhenSilenced
                  ? 'Chimes buzz and make no sound.'
                  : 'Chimes still play, at your ${volumeNow.label}.',
            ),
          SwitchListTile(
            secondary: const Icon(Icons.vibration),
            title: const Text('Vibrate with each chime'),
            subtitle: const Text('A short double buzz along with the sound.'),
            value: settings.vibrate,
            onChanged: (v) => controller.updateSettings(settings.copyWith(vibrate: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_paused_outlined),
            title: const Text('Vibrate instead when silenced'),
            subtitle: const Text(
              'While the phone is on vibrate or silent, chimes buzz and make no sound.',
            ),
            value: settings.vibrateWhenSilenced,
            onChanged: (v) => controller.updateSettings(settings.copyWith(vibrateWhenSilenced: v)),
          ),
          const _Header('Screen off'),
          ListTile(
            leading: Icon(
              _notificationsAllowed == false
                  ? Icons.notifications_off_outlined
                  : Icons.notifications_outlined,
            ),
            title: const Text('Notifications'),
            subtitle: Text(
              _notificationsAllowed == false
                  ? 'Off. Timers still ring, but their pause, skip and stop controls '
                        'won\'t appear in the notification shade or on the lock screen.'
                  : 'On. Running timers show their controls in the notification shade '
                        'and on the lock screen.',
            ),
            trailing: _notificationsAllowed == false
                ? TextButton(onPressed: _enableNotifications, child: const Text('Turn on'))
                : null,
          ),
          ListTile(
            leading: const Icon(Icons.battery_saver_outlined),
            title: const Text('Battery optimization'),
            subtitle: Text(
              _batteryUnrestricted == true
                  ? 'Unrestricted. Android won\'t limit Belltide in the background.'
                  : 'Optimized. Timers run in a foreground service, which most phones '
                        'leave alone. If chimes stop while the screen is off, set Belltide '
                        'to Unrestricted.',
            ),
            trailing: _batteryUnrestricted == true
                ? null
                : TextButton(
                    onPressed: () => controller.engine.openBatterySettings(),
                    child: const Text('Open'),
                  ),
          ),
          const _Header('Integrations'),
          Builder(
            builder: (context) {
              final clickUp = ClickUpScope.of(context);
              final account = clickUp.account;
              return ListTile(
                leading: const Icon(Icons.task_alt_rounded),
                title: const Text('ClickUp'),
                subtitle: Text(
                  clickUp.connected && account != null
                      ? 'Connected to ${account.workspaceName}'
                      : 'Optional. Link timers to tasks and log the time they run.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openClickUpSettings(context),
              );
            },
          ),
          const _Header('About'),
          ListTile(
            leading: const BrandMark(size: 32),
            title: const Text('Belltide'),
            subtitle: const Text('Version $appVersion · MIT License'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Belltide',
              applicationVersion: appVersion,
              applicationIcon: const Padding(
                padding: EdgeInsets.all(12),
                child: BrandMark(size: 72),
              ),
              applicationLegalese: 'Copyright (c) 2026 Ben Kennedy. Released under the MIT License.',
            ),
          ),
        ],
      ),
    );
  }
}

/// The in-app chime volume: a slider that plays a bell when it is let go.
class _LevelTile extends StatefulWidget {
  const _LevelTile({required this.level, required this.onChanged});

  final double level;

  /// Called once with the final value when the user lets go of the slider.
  final ValueChanged<double> onChanged;

  @override
  State<_LevelTile> createState() => _LevelTileState();
}

class _LevelTileState extends State<_LevelTile> {
  /// The slider's position while a finger is on it; null follows the setting.
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final level = _dragging ?? widget.level;
    final percent = (level * 100).round();
    final label = percent == 0 ? 'Muted' : '$percent%';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                percent == 0
                    ? Icons.volume_off_outlined
                    : percent < 50
                    ? Icons.volume_down_outlined
                    : Icons.volume_up_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 16),
              Expanded(child: Text('Chime volume', style: theme.textTheme.bodyLarge)),
              Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary),
              ),
            ],
          ),
          Slider(
            value: level,
            divisions: 20,
            label: label,
            semanticFormatterCallback: (v) => v == 0 ? 'Muted' : '${(v * 100).round()} percent',
            onChanged: (v) => setState(() => _dragging = v),
            onChangeEnd: (v) {
              setState(() => _dragging = null);
              widget.onChanged(v);
            },
          ),
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: Text(
              'How loud chimes are compared with everything else on the phone.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// Says what chimes do while the phone is on vibrate or silent.
class _RingerNotice extends StatelessWidget {
  const _RingerNotice({required this.ringer, required this.message});

  final RingerMode ringer;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onVibrate = ringer == RingerMode.vibrate;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        tileColor: scheme.secondaryContainer,
        textColor: scheme.onSecondaryContainer,
        iconColor: scheme.onSecondaryContainer,
        leading: Icon(onVibrate ? Icons.vibration : Icons.notifications_off_outlined),
        title: Text(onVibrate ? 'Phone is on vibrate' : 'Phone is on silent'),
        subtitle: Text(message),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Semantics(
        header: true,
        child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
      ),
    );
  }
}

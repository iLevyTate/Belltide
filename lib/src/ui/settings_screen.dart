import 'package:material_ui/material_ui.dart';

import '../app_info.dart';
import '../model/app_settings.dart';
import '../state/belltide_scope.dart';
import '../state/clickup_scope.dart';
import 'clickup/clickup_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _notificationsAllowed;
  bool? _batteryUnrestricted;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
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

    Widget volumeOption(ChimeVolume volume, String title, String subtitle) {
      final selected = settings.volume == volume;
      return ListTile(
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: selected ? theme.colorScheme.primary : null,
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        onTap: () => controller.updateSettings(settings.copyWith(volume: volume)),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const _Header('Chimes'),
          volumeOption(
            ChimeVolume.alarm,
            'Alarm volume',
            'Uses your alarm volume. On most phones alarms also play through the '
                'speaker when headphones are connected.',
          ),
          volumeOption(
            ChimeVolume.media,
            'Media volume',
            'Uses your media volume and plays through headphones when they are connected.',
          ),
          SwitchListTile(
            secondary: const Icon(Icons.vibration),
            title: const Text('Vibrate with each chime'),
            value: settings.vibrate,
            onChanged: (v) => controller.updateSettings(settings.copyWith(vibrate: v)),
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
            leading: const Icon(Icons.info_outline),
            title: const Text('Belltide'),
            subtitle: const Text('Version $appVersion · MIT License'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Belltide',
              applicationVersion: appVersion,
              applicationLegalese: 'Copyright (c) 2026 Ben Kennedy. Released under the MIT License.',
            ),
          ),
        ],
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

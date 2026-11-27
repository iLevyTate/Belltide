import 'package:material_ui/material_ui.dart';

import '../../clickup/clickup_api.dart';
import '../../clickup/clickup_controller.dart';
import '../../clickup/clickup_models.dart';
import '../../state/clickup_scope.dart';

Future<void> openClickUpSettings(BuildContext context) => Navigator.of(context).push<void>(
  MaterialPageRoute(builder: (_) => const ClickUpSettingsScreen()),
);

/// Connect, configure or disconnect the optional ClickUp integration.
class ClickUpSettingsScreen extends StatefulWidget {
  const ClickUpSettingsScreen({super.key});

  @override
  State<ClickUpSettingsScreen> createState() => _ClickUpSettingsScreenState();
}

class _ClickUpSettingsScreenState extends State<ClickUpSettingsScreen> {
  final TextEditingController _token = TextEditingController();
  bool _busy = false;
  bool _showToken = false;
  String? _error;

  /// Workspaces to choose from after connecting an account that has several.
  List<ClickUpWorkspace>? _choices;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ClickUpScope.read(context).refreshSyncStatus();
    });
  }

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final clickUp = ClickUpScope.read(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final workspaces = await clickUp.connect(_token.text);
      if (!mounted) return;
      _token.clear();
      setState(() => _choices = workspaces.length > 1 ? workspaces : null);
    } on ClickUpException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeWorkspace() async {
    final clickUp = ClickUpScope.read(context);
    setState(() => _busy = true);
    try {
      final workspaces = await clickUp.workspaces();
      if (mounted) setState(() => _choices = workspaces);
    } on ClickUpException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final clickUp = ClickUpScope.read(context);
    final pending = clickUp.syncStatus.pending;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect ClickUp?'),
        content: Text(
          'Belltide forgets your API token. Timers keep their linked tasks but stop logging time'
          '${pending > 0 ? ', and $pending time ${pending == 1 ? 'entry' : 'entries'} not yet sent will be discarded' : ''}.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Disconnect')),
        ],
      ),
    );
    if (confirmed == true) await clickUp.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final clickUp = ClickUpScope.of(context);
    final Widget body;
    if (_choices != null) {
      body = _workspaceChooser(clickUp, _choices!);
    } else if (clickUp.connected) {
      body = _connectedView(clickUp);
    } else {
      body = _connectView();
    }
    return Scaffold(appBar: AppBar(title: const Text('ClickUp')), body: body);
  }

  Widget _connectView() {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Link timers to ClickUp tasks', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Search your tasks and subtasks, attach a timer to one, and Belltide logs the time it runs '
          'to that task. Several timers can run for different tasks at once.',
          style: muted,
        ),
        const SizedBox(height: 8),
        Text(
          'Belltide talks to ClickUp directly with your personal API token. The token is encrypted on '
          'this phone and not sent anywhere else.',
          style: muted,
        ),
        const SizedBox(height: 24),
        Text('Get your token', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Text(
          '1. In ClickUp, open your account Settings and choose Apps.\n'
          '2. Under API Token, select Generate, then copy the token. It starts with pk_.\n'
          '3. Paste it below.',
          style: muted,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _token,
          obscureText: !_showToken,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'API token',
            hintText: 'pk_…',
            errorText: _error,
            errorMaxLines: 3,
            suffixIcon: IconButton(
              tooltip: _showToken ? 'Hide token' : 'Show token',
              icon: Icon(_showToken ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _showToken = !_showToken),
            ),
          ),
          onSubmitted: (_) => _busy ? null : _connect(),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _busy ? null : _connect,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.link),
            label: const Text('Connect'),
          ),
        ),
      ],
    );
  }

  Widget _workspaceChooser(ClickUpController clickUp, List<ClickUpWorkspace> workspaces) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          child: Text('Choose a workspace', style: theme.textTheme.titleLarge),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            'Task search and time logging use this workspace. You can change it later.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        for (final workspace in workspaces)
          ListTile(
            leading: Icon(
              clickUp.account?.workspaceId == workspace.id ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            ),
            title: Text(workspace.name),
            onTap: () async {
              await clickUp.selectWorkspace(workspace);
              if (mounted) setState(() => _choices = null);
            },
          ),
      ],
    );
  }

  Widget _connectedView(ClickUpController clickUp) {
    final theme = Theme.of(context);
    final account = clickUp.account!;
    final sync = clickUp.syncStatus;
    final String syncText;
    if (sync.pending > 0) {
      syncText = '${sync.pending} time ${sync.pending == 1 ? 'entry' : 'entries'} waiting to be sent.';
    } else if (sync.lastSyncedAt != null) {
      syncText = 'All time logged. Last sent ${_ago(sync.lastSyncedAt!)}.';
    } else {
      syncText = 'Nothing waiting to be sent.';
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ListTile(
          leading: const Icon(Icons.account_circle_outlined),
          title: Text(account.username.isEmpty ? 'Connected' : account.username),
          subtitle: Text('Workspace: ${account.workspaceName}'),
          trailing: TextButton(onPressed: _busy ? null : _changeWorkspace, child: const Text('Change')),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        SwitchListTile(
          secondary: const Icon(Icons.more_time_rounded),
          title: const Text('Log time to linked tasks'),
          subtitle: const Text(
            'When a linked timer pauses, stops or finishes, the time it ran is added to its task.',
          ),
          value: clickUp.logTime,
          onChanged: clickUp.setLogTime,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.person_search_outlined),
          title: const Text('Search only my tasks'),
          subtitle: const Text('Task search starts with tasks assigned to you.'),
          value: clickUp.onlyMine,
          onChanged: clickUp.setOnlyMine,
        ),
        ListTile(
          leading: Icon(sync.lastError == null ? Icons.cloud_done_outlined : Icons.cloud_off_outlined),
          title: const Text('Time entries'),
          subtitle: Text(sync.lastError == null ? syncText : '$syncText\n${sync.lastError}'),
          isThreeLine: sync.lastError != null,
          trailing: sync.pending > 0 ? TextButton(onPressed: clickUp.syncNow, child: const Text('Send now')) : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: OutlinedButton.icon(
            onPressed: _disconnect,
            icon: const Icon(Icons.link_off),
            label: const Text('Disconnect ClickUp'),
          ),
        ),
      ],
    );
  }
}

String _ago(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${time.day}/${time.month}/${time.year}';
}

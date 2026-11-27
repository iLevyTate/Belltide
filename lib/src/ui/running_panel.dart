import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../model/running_timer.dart';
import '../state/belltide_scope.dart';
import '../util/format.dart';
import 'theme.dart';

/// Live status of a running timer: current step, countdown and controls.
class RunningPanel extends StatefulWidget {
  const RunningPanel({super.key, required this.timer});

  final RunningTimer timer;

  @override
  State<RunningPanel> createState() => _RunningPanelState();
}

class _RunningPanelState extends State<RunningPanel> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  Duration _now = Duration.zero;
  String _shownClock = '';
  double _shownProgress = -1;

  @override
  void initState() {
    super.initState();
    _now = BelltideScope.read(context).clock.now();
    _syncTicker();
  }

  @override
  void didUpdateWidget(RunningPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _now = BelltideScope.read(context).clock.now();
    _syncTicker();
  }

  void _syncTicker() {
    if (widget.timer.paused) {
      if (_ticker.isActive) _ticker.stop();
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  void _onTick(Duration _) {
    final now = BelltideScope.read(context).clock.now();
    final clock = formatClock(widget.timer.stepRemainingAt(now));
    final progress = widget.timer.stepProgressAt(now);
    // Rebuild only when something visible changes.
    if (clock != _shownClock || (progress - _shownProgress).abs() > 0.002) {
      setState(() => _now = now);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  String get _phase {
    final t = widget.timer;
    if (t.inLeadIn) return 'Get ready';
    if (t.isInterval) return 'Next chime in';
    return t.stepLabel;
  }

  String? get _roundText {
    final t = widget.timer;
    if (t.isInterval) return t.rounds > 0 ? 'Chime ${t.round} of ${t.rounds}' : null;
    if (t.inLeadIn) return t.rounds > 0 ? '${t.rounds} rounds' : null;
    final step = t.stepCount > 1 ? 'Step ${t.stepIndex + 1} of ${t.stepCount} · ' : '';
    return t.rounds > 0 ? '${step}Round ${t.round} of ${t.rounds}' : '${step}Round ${t.round}';
  }

  @override
  Widget build(BuildContext context) {
    final controller = BelltideScope.read(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final t = widget.timer;
    final remaining = t.stepRemainingAt(_now);
    final total = t.totalRemainingAt(_now);
    _shownClock = formatClock(remaining);
    _shownProgress = t.stepProgressAt(_now);
    final roundText = _roundText;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.paused ? 'Paused · $_phase' : _phase,
                      style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary),
                    ),
                    Semantics(
                      label: '$_phase, ${formatSpan(Duration(seconds: (remaining.inMilliseconds + 999) ~/ 1000))} left',
                      excludeSemantics: true,
                      child: Text(
                        _shownClock,
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontFeatures: tabularFigures,
                          color: t.paused ? scheme.onSurfaceVariant : scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (roundText != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    roundText,
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _shownProgress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
            color: scheme.primary,
            backgroundColor: scheme.onSecondaryContainer.withValues(alpha: 0.12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton.filled(
                tooltip: t.paused ? 'Resume' : 'Pause',
                icon: Icon(t.paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                onPressed: () => t.paused ? controller.resume(t.id) : controller.pause(t.id),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: t.isInterval ? 'Chime now and restart the interval' : 'Skip to the next step',
                icon: const Icon(Icons.skip_next_rounded),
                onPressed: () => controller.skip(t.id),
              ),
              const Spacer(),
              if (total != null)
                Text(
                  '${formatClock(total)} left',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: tabularFigures,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

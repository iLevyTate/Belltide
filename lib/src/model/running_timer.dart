import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'timer_preset.dart';

/// A live view of a timer the Android service is running, as of [receivedAt].
///
/// The service only sends state when something changes (a step starts, a
/// timer is paused). In between, the UI counts down locally from
/// [stepRemaining] using a monotonic clock.
@immutable
class RunningTimer {
  const RunningTimer({
    required this.id,
    required this.name,
    required this.kind,
    required this.paused,
    required this.inLeadIn,
    required this.stepIndex,
    required this.stepCount,
    required this.stepLabel,
    required this.round,
    required this.rounds,
    required this.stepDuration,
    required this.stepRemaining,
    required this.totalRemaining,
    required this.receivedAt,
  });

  final String id;
  final String name;
  final TimerKind kind;
  final bool paused;
  final bool inLeadIn;
  final int stepIndex;
  final int stepCount;
  final String stepLabel;

  /// One-based round number. For an interval timer, the number of the next chime.
  final int round;

  /// 0 when the timer repeats until stopped.
  final int rounds;
  final Duration stepDuration;
  final Duration stepRemaining;

  /// Null when the timer repeats until stopped.
  final Duration? totalRemaining;

  /// Monotonic time when this snapshot arrived.
  final Duration receivedAt;

  bool get isInterval => kind == TimerKind.interval;

  Duration _elapsedSince(Duration now) {
    if (paused) return Duration.zero;
    final elapsed = now - receivedAt;
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  Duration stepRemainingAt(Duration now) {
    final left = stepRemaining - _elapsedSince(now);
    return left.isNegative ? Duration.zero : left;
  }

  Duration? totalRemainingAt(Duration now) {
    final total = totalRemaining;
    if (total == null) return null;
    final left = total - _elapsedSince(now);
    return left.isNegative ? Duration.zero : left;
  }

  /// Progress through the current step, from 0 to 1.
  double stepProgressAt(Duration now) {
    final ms = stepDuration.inMilliseconds;
    if (ms <= 0) return 0;
    return (1 - stepRemainingAt(now).inMilliseconds / ms).clamp(0.0, 1.0);
  }

  factory RunningTimer.fromJson(Map<String, Object?> json, Duration receivedAt) {
    int asInt(String key) => (json[key] as num?)?.toInt() ?? 0;
    final total = asInt('totalRemainingMs');
    return RunningTimer(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      kind: TimerKind.fromName(json['kind']),
      paused: json['status'] == 'paused',
      inLeadIn: json['inLeadIn'] as bool? ?? false,
      stepIndex: asInt('stepIndex'),
      stepCount: asInt('stepCount'),
      stepLabel: json['stepLabel'] as String? ?? '',
      round: asInt('round'),
      rounds: asInt('rounds'),
      stepDuration: Duration(milliseconds: asInt('stepDurationMs')),
      stepRemaining: Duration(milliseconds: asInt('stepRemainingMs')),
      totalRemaining: total < 0 ? null : Duration(milliseconds: total),
      receivedAt: receivedAt,
    );
  }
}

/// Everything the service reported in one update.
@immutable
class EngineState {
  const EngineState({this.timers = const [], this.finished = const []});

  static const EngineState empty = EngineState();

  final List<RunningTimer> timers;

  /// Ids of timers that ran all their rounds since the previous update.
  final List<String> finished;

  factory EngineState.fromJson(String source, Duration receivedAt) {
    final json = jsonDecode(source) as Map<String, Object?>;
    return EngineState(
      timers: (json['timers'] as List<Object?>? ?? const [])
          .whereType<Map<String, Object?>>()
          .map((t) => RunningTimer.fromJson(t, receivedAt))
          .toList(growable: false),
      finished: (json['finished'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
    );
  }
}

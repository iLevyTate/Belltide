import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'chime_sound.dart';

/// How a timer is presented and edited. Both kinds run on the same engine:
/// an interval timer is a sequence with a single step.
enum TimerKind {
  interval,
  sequence;

  static TimerKind fromName(Object? name) =>
      name == 'interval' ? TimerKind.interval : TimerKind.sequence;
}

/// One step of a sequence, such as "Hold" for 10 seconds with a bell.
@immutable
class TimerStep {
  const TimerStep({
    required this.id,
    required this.label,
    required this.duration,
    required this.sound,
  });

  /// Stable id so the editor can keep track of steps while they are reordered.
  final String id;
  final String label;
  final Duration duration;

  /// Plays when this step starts.
  final ChimeSound sound;

  TimerStep copyWith({String? label, Duration? duration, ChimeSound? sound}) {
    return TimerStep(
      id: id,
      label: label ?? this.label,
      duration: duration ?? this.duration,
      sound: sound ?? this.sound,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'durationMs': duration.inMilliseconds,
    'sound': sound.id,
  };

  factory TimerStep.fromJson(Map<String, Object?> json) {
    return TimerStep(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      duration: Duration(milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0),
      sound: ChimeSound.fromId(json['sound']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TimerStep &&
      other.id == id &&
      other.label == label &&
      other.duration == duration &&
      other.sound == sound;

  @override
  int get hashCode => Object.hash(id, label, duration, sound);
}

/// A saved timer: an interval chime or a multi-step sequence.
@immutable
class TimerPreset {
  const TimerPreset({
    required this.id,
    required this.name,
    required this.kind,
    required this.steps,
    this.rounds = 0,
    this.leadIn = Duration.zero,
    this.startChime = false,
    this.finishSound = ChimeSound.none,
  });

  /// An interval chime: [sound] every [every], forever or for [chimes] chimes.
  factory TimerPreset.interval({
    required String id,
    required String name,
    required Duration every,
    required ChimeSound sound,
    int chimes = 0,
    bool startChime = false,
  }) {
    return TimerPreset(
      id: id,
      name: name,
      kind: TimerKind.interval,
      steps: [TimerStep(id: '$id-interval', label: 'Interval', duration: every, sound: sound)],
      rounds: chimes,
      startChime: startChime,
      finishSound: sound,
    );
  }

  static const int maxRounds = 999;
  static const Duration minStep = Duration(seconds: 1);
  static const Duration maxStep = Duration(hours: 24);

  final String id;
  final String name;
  final TimerKind kind;
  final List<TimerStep> steps;

  /// How many times the steps run. 0 repeats until stopped. For an interval
  /// timer this is the number of chimes.
  final int rounds;

  /// A "get ready" countdown before the first step.
  final Duration leadIn;

  /// Whether the first step's sound plays as the first step starts.
  final bool startChime;

  /// Plays when the last round ends. Unused when the timer repeats forever.
  final ChimeSound finishSound;

  bool get isInterval => kind == TimerKind.interval;
  bool get repeatsForever => rounds == 0;

  /// The interval length of an interval timer.
  Duration get every => steps.first.duration;

  /// The sound of an interval timer.
  ChimeSound get intervalSound => steps.first.sound;

  /// Length of one pass through the steps.
  Duration get cycle => steps.fold(Duration.zero, (sum, s) => sum + s.duration);

  /// Total running time, or null when the timer repeats until stopped.
  Duration? get total => repeatsForever ? null : leadIn + cycle * rounds;

  /// A name to show when the user left the name blank.
  String get displayName => name.trim().isEmpty ? 'Untitled timer' : name.trim();

  /// Returns a problem to show the user, or null when the timer can run.
  String? validate() {
    if (steps.isEmpty) return 'Add at least one step.';
    for (final step in steps) {
      if (step.duration < minStep) return 'Each step needs to be at least 1 second long.';
      if (step.duration > maxStep) return 'Steps can be at most 24 hours long.';
    }
    if (rounds < 0 || rounds > maxRounds) return 'Rounds must be between 1 and $maxRounds.';
    return null;
  }

  TimerPreset copyWith({
    String? id,
    String? name,
    TimerKind? kind,
    List<TimerStep>? steps,
    int? rounds,
    Duration? leadIn,
    bool? startChime,
    ChimeSound? finishSound,
  }) {
    return TimerPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      steps: steps ?? this.steps,
      rounds: rounds ?? this.rounds,
      leadIn: leadIn ?? this.leadIn,
      startChime: startChime ?? this.startChime,
      finishSound: finishSound ?? this.finishSound,
    );
  }

  /// The configuration the Android timer service runs (see EngineJson.kt).
  Map<String, Object?> toEngineJson() {
    final interval = isInterval;
    return {
      'id': id,
      'name': displayName,
      'kind': kind.name,
      'steps': [
        for (final step in interval ? steps.take(1) : steps)
          {
            'label': step.label.trim().isEmpty ? 'Step' : step.label.trim(),
            'durationMs': step.duration.inMilliseconds,
            'sound': step.sound.id,
          },
      ],
      'rounds': rounds,
      'leadInMs': interval ? 0 : leadIn.inMilliseconds,
      'startChime': startChime,
      // An interval timer ends on its own chime.
      'finishSound': interval ? intervalSound.id : finishSound.id,
    };
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'steps': [for (final step in steps) step.toJson()],
    'rounds': rounds,
    'leadInMs': leadIn.inMilliseconds,
    'startChime': startChime,
    'finishSound': finishSound.id,
  };

  factory TimerPreset.fromJson(Map<String, Object?> json) {
    final steps = (json['steps'] as List<Object?>? ?? const [])
        .whereType<Map<String, Object?>>()
        .map(TimerStep.fromJson)
        .toList(growable: false);
    return TimerPreset(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      kind: TimerKind.fromName(json['kind']),
      steps: steps,
      rounds: (json['rounds'] as num?)?.toInt() ?? 0,
      leadIn: Duration(milliseconds: (json['leadInMs'] as num?)?.toInt() ?? 0),
      startChime: json['startChime'] as bool? ?? false,
      finishSound: ChimeSound.fromId(json['finishSound'], fallback: ChimeSound.none),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TimerPreset && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

import '../model/timer_preset.dart';

/// A countdown clock: 0:07, 12:00, 1:02:03. Rounds up, so a step shows its
/// full length when it starts and 0:00 only when it ends.
String formatClock(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final totalSeconds = (d.inMilliseconds + 999) ~/ 1000;
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// A length in words: 10 s, 5 min, 1 min 30 s, 1 h 5 min.
String formatSpan(Duration d) {
  final totalSeconds = d.inSeconds;
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  final parts = <String>[
    if (h > 0) '$h h',
    if (m > 0) '$m min',
    if (s > 0 || totalSeconds == 0) '$s s',
  ];
  return parts.join(' ');
}

String _plural(int n, String one, String many) => n == 1 ? '$n $one' : '$n $many';

/// First summary line for a timer card.
String presetSummary(TimerPreset p) {
  if (p.isInterval) {
    return 'Every ${formatSpan(p.every)} · ${p.intervalSound.label}';
  }
  const shown = 3;
  final steps = p.steps
      .take(shown)
      .map((s) => '${s.label.trim().isEmpty ? 'Step' : s.label.trim()} ${formatSpan(s.duration)}');
  final more = p.steps.length > shown ? ' · +${p.steps.length - shown} more' : '';
  return '${steps.join(' · ')}$more';
}

/// Second summary line: how long the timer runs.
String presetDetail(TimerPreset p) {
  final total = p.total;
  if (total == null) return 'Repeats until stopped';
  final count = p.isInterval
      ? _plural(p.rounds, 'chime', 'chimes')
      : _plural(p.rounds, 'round', 'rounds');
  return '$count · ${formatSpan(total)} total';
}

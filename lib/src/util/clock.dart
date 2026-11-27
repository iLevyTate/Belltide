/// A monotonic clock for counting down between engine updates. Unlike
/// DateTime.now, it never jumps when the user changes the system time.
class MonotonicClock {
  MonotonicClock() : _stopwatch = Stopwatch()..start();

  final Stopwatch _stopwatch;

  Duration now() => _stopwatch.elapsed;
}

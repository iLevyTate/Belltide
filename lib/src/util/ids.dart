import 'dart:math';

final Random _random = Random();

/// A short unique id for presets and steps, such as `m2x9k4-a7f3`.
String newId() {
  final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final noise = _random.nextInt(1 << 20).toRadixString(36).padLeft(4, '0');
  return '$time-$noise';
}

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../model/app_settings.dart';
import '../model/timer_preset.dart';
import 'key_value_store.dart';

/// Saved timers, stored on the device as JSON.
class PresetRepository {
  PresetRepository(this._store);

  static const String key = 'presets.v1';

  final KeyValueStore _store;

  /// The saved timers, or null if nothing was ever saved (first launch).
  Future<List<TimerPreset>?> load() async {
    final raw = await _store.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      return (decoded['presets'] as List<Object?>? ?? const [])
          .whereType<Map<String, Object?>>()
          .map(TimerPreset.fromJson)
          .where((p) => p.id.isNotEmpty && p.validate() == null)
          .toList();
    } on FormatException catch (e) {
      debugPrint('Belltide: ignoring unreadable presets: $e');
      return [];
    }
  }

  Future<void> save(List<TimerPreset> presets) => _store.setString(
    key,
    jsonEncode({
      'version': 1,
      'presets': [for (final p in presets) p.toJson()],
    }),
  );
}

class SettingsRepository {
  SettingsRepository(this._store);

  static const String key = 'settings.v1';

  final KeyValueStore _store;

  Future<AppSettings> load() async {
    final raw = await _store.getString(key);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on FormatException {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) =>
      _store.setString(key, jsonEncode(settings.toJson()));
}

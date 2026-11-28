import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../model/app_settings.dart';
import '../model/audio_status.dart';
import '../model/chime_sound.dart';
import '../model/running_timer.dart';
import '../model/timer_preset.dart';
import '../util/clock.dart';
import 'timer_engine.dart';

/// Talks to the Android timer service through MainActivity.kt.
class PlatformTimerEngine implements TimerEngine {
  PlatformTimerEngine({MonotonicClock? clock}) : _clock = clock ?? MonotonicClock() {
    // The only call Android makes to Dart: a volume or the ringer mode changed.
    _methods.setMethodCallHandler((call) async {
      if (call.method == 'audioChanged') _audioChanges.add(null);
    });
  }

  static const MethodChannel _methods = MethodChannel('belltide/engine');
  static const EventChannel _events = EventChannel('belltide/engine/state');

  final MonotonicClock _clock;
  final StreamController<void> _audioChanges = StreamController<void>.broadcast();

  @override
  late final Stream<EngineState> states = _events
      .receiveBroadcastStream()
      .map((event) => EngineState.fromJson(event as String, _clock.now()));

  @override
  Future<void> start(TimerPreset preset) =>
      _methods.invokeMethod('start', {'config': jsonEncode(preset.toEngineJson())});

  @override
  Future<void> pause(String id) => _methods.invokeMethod('pause', {'id': id});

  @override
  Future<void> resume(String id) => _methods.invokeMethod('resume', {'id': id});

  @override
  Future<void> skip(String id) => _methods.invokeMethod('skip', {'id': id});

  @override
  Future<void> stop(String id) => _methods.invokeMethod('stop', {'id': id});

  @override
  Future<void> stopAll() => _methods.invokeMethod('stopAll');

  @override
  Future<void> previewSound(ChimeSound sound) async {
    if (sound.isSilent) return;
    await _methods.invokeMethod('previewSound', {'sound': sound.id});
  }

  @override
  Future<void> applySettings(AppSettings settings) => _methods.invokeMethod('applySettings', {
    'audioStream': settings.volume.name,
    'vibrate': settings.vibrate,
    'level': settings.level,
    'duckOthers': settings.duckOthers,
    'vibrateWhenSilenced': settings.vibrateWhenSilenced,
  });

  @override
  Future<AudioStatus> audioStatus() async => AudioStatus.fromJson(
    await _methods.invokeMapMethod<Object?, Object?>('audioStatus') ?? const {},
  );

  @override
  Stream<void> get audioChanges => _audioChanges.stream;

  @override
  Future<void> openVolumeSettings() => _methods.invokeMethod('openVolumeSettings');

  @override
  Future<bool> notificationsAllowed() async =>
      await _methods.invokeMethod<String>('notificationPermission') == 'granted';

  @override
  Future<bool> requestNotificationPermission() async =>
      await _methods.invokeMethod<bool>('requestNotificationPermission') ?? false;

  @override
  Future<void> openNotificationSettings() => _methods.invokeMethod('openNotificationSettings');

  @override
  Future<bool> isIgnoringBatteryOptimizations() async =>
      await _methods.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;

  @override
  Future<void> openBatterySettings() => _methods.invokeMethod('openBatterySettings');
}

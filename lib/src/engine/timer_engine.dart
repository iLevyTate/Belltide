import '../model/app_settings.dart';
import '../model/chime_sound.dart';
import '../model/running_timer.dart';
import '../model/timer_preset.dart';

/// The timer engine as the UI sees it. On Android it is a foreground service
/// ([PlatformTimerEngine]); tests use a fake.
abstract interface class TimerEngine {
  /// Engine updates. A new listener receives the current state first.
  Stream<EngineState> get states;

  /// Starts [preset], restarting it if it is already running.
  Future<void> start(TimerPreset preset);
  Future<void> pause(String id);
  Future<void> resume(String id);

  /// Jumps to the start of the next step.
  Future<void> skip(String id);
  Future<void> stop(String id);
  Future<void> stopAll();

  Future<void> previewSound(ChimeSound sound);
  Future<void> applySettings(AppSettings settings);

  Future<bool> notificationsAllowed();

  /// Asks for notification permission (Android 13+). Returns whether it is granted.
  Future<bool> requestNotificationPermission();
  Future<void> openNotificationSettings();

  Future<bool> isIgnoringBatteryOptimizations();
  Future<void> openBatterySettings();
}

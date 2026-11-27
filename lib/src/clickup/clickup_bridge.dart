import 'package:flutter/services.dart';

import 'clickup_models.dart';

/// The Android side of the ClickUp integration: encrypted token storage and the
/// time-entry queue the timer service fills (see ClickUpSync.kt).
abstract interface class ClickUpBridge {
  Future<String?> readToken();
  Future<void> saveToken(String? token);
  Future<void> setLogging(bool enabled);
  Future<SyncStatus> syncStatus();

  /// Uploads queued time entries now and returns the new status.
  Future<SyncStatus> syncNow();
  Future<void> clearQueue();
  Future<void> openUrl(String url);
}

class PlatformClickUpBridge implements ClickUpBridge {
  static const MethodChannel _channel = MethodChannel('belltide/engine');

  @override
  Future<String?> readToken() => _channel.invokeMethod<String>('clickupGetToken');

  @override
  Future<void> saveToken(String? token) => _channel.invokeMethod('clickupSetToken', {'token': token});

  @override
  Future<void> setLogging(bool enabled) => _channel.invokeMethod('clickupSetLogging', {'enabled': enabled});

  @override
  Future<SyncStatus> syncStatus() async =>
      SyncStatus.fromMap(await _channel.invokeMethod<Map<Object?, Object?>>('clickupSyncStatus'));

  @override
  Future<SyncStatus> syncNow() async =>
      SyncStatus.fromMap(await _channel.invokeMethod<Map<Object?, Object?>>('clickupSyncNow'));

  @override
  Future<void> clearQueue() => _channel.invokeMethod('clickupClearQueue');

  @override
  Future<void> openUrl(String url) => _channel.invokeMethod('openUrl', {'url': url});
}

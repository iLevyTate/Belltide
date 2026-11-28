import 'package:flutter/foundation.dart';

/// Which volume the chimes follow.
enum ChimeVolume {
  /// The alarm stream on the phone's own speaker. Through headphones or an
  /// external speaker chimes follow the media volume instead, because Android
  /// would play an alarm on both outputs at the speaker's level.
  alarm('alarm volume'),

  /// The media stream, on the speaker and through headphones alike.
  media('media volume');

  const ChimeVolume(this.label);

  /// The name of this volume in running text, like "alarm volume".
  final String label;

  static ChimeVolume fromName(Object? name) =>
      name == 'media' ? ChimeVolume.media : ChimeVolume.alarm;
}

@immutable
class AppSettings {
  const AppSettings({
    this.volume = ChimeVolume.alarm,
    this.vibrate = false,
    this.level = 1.0,
    this.duckOthers = true,
    this.vibrateWhenSilenced = false,
  }) : assert(level >= 0 && level <= 1);

  final ChimeVolume volume;

  /// Buzz along with every chime.
  final bool vibrate;

  /// The chime volume inside the app, from 0 (muted) to 1, on top of the
  /// phone's own [volume].
  final double level;

  /// Briefly lower music, videos and other audio while a chime plays.
  final bool duckOthers;

  /// When the phone is on vibrate or silent, buzz instead of playing the sound.
  final bool vibrateWhenSilenced;

  AppSettings copyWith({
    ChimeVolume? volume,
    bool? vibrate,
    double? level,
    bool? duckOthers,
    bool? vibrateWhenSilenced,
  }) => AppSettings(
    volume: volume ?? this.volume,
    vibrate: vibrate ?? this.vibrate,
    level: level ?? this.level,
    duckOthers: duckOthers ?? this.duckOthers,
    vibrateWhenSilenced: vibrateWhenSilenced ?? this.vibrateWhenSilenced,
  );

  Map<String, Object?> toJson() => {
    'volume': volume.name,
    'vibrate': vibrate,
    'level': level,
    'duckOthers': duckOthers,
    'vibrateWhenSilenced': vibrateWhenSilenced,
  };

  factory AppSettings.fromJson(Map<String, Object?> json) {
    final level = json['level'];
    return AppSettings(
      volume: ChimeVolume.fromName(json['volume']),
      vibrate: json['vibrate'] as bool? ?? false,
      level: level is num && level.isFinite ? level.toDouble().clamp(0.0, 1.0) : 1.0,
      duckOthers: json['duckOthers'] as bool? ?? true,
      vibrateWhenSilenced: json['vibrateWhenSilenced'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.volume == volume &&
      other.vibrate == vibrate &&
      other.level == level &&
      other.duckOthers == duckOthers &&
      other.vibrateWhenSilenced == vibrateWhenSilenced;

  @override
  int get hashCode => Object.hash(volume, vibrate, level, duckOthers, vibrateWhenSilenced);
}

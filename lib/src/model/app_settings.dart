import 'package:flutter/foundation.dart';

/// Which volume the chimes follow.
enum ChimeVolume {
  /// The alarm stream: usually loud, and on most phones also played through
  /// the speaker when headphones are connected.
  alarm,

  /// The media stream: follows the media volume and plays through headphones.
  media;

  static ChimeVolume fromName(Object? name) =>
      name == 'media' ? ChimeVolume.media : ChimeVolume.alarm;
}

@immutable
class AppSettings {
  const AppSettings({this.volume = ChimeVolume.alarm, this.vibrate = false});

  final ChimeVolume volume;
  final bool vibrate;

  AppSettings copyWith({ChimeVolume? volume, bool? vibrate}) =>
      AppSettings(volume: volume ?? this.volume, vibrate: vibrate ?? this.vibrate);

  Map<String, Object?> toJson() => {'volume': volume.name, 'vibrate': vibrate};

  factory AppSettings.fromJson(Map<String, Object?> json) => AppSettings(
    volume: ChimeVolume.fromName(json['volume']),
    vibrate: json['vibrate'] as bool? ?? false,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings && other.volume == volume && other.vibrate == vibrate;

  @override
  int get hashCode => Object.hash(volume, vibrate);
}

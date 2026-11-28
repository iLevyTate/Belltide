import 'package:flutter/foundation.dart';

import 'app_settings.dart';

/// The phone's ringer switch.
enum RingerMode {
  normal,
  vibrate,
  silent;

  static RingerMode fromName(Object? name) => switch (name) {
    'vibrate' => RingerMode.vibrate,
    'silent' => RingerMode.silent,
    _ => RingerMode.normal,
  };
}

/// What the phone will do with a chime right now: the level of the volume
/// chimes follow, and whether the ringer is silenced.
@immutable
class AudioStatus {
  const AudioStatus({
    required this.volume,
    required this.maxVolume,
    required this.ringer,
    this.headphones = false,
  });

  /// The phone volume chimes follow, in the phone's own steps.
  final int volume;
  final int maxVolume;
  final RingerMode ringer;

  /// True while headphones or an external speaker carry the phone's audio.
  /// Chimes then play through them at the media volume, whatever was chosen.
  final bool headphones;

  /// The volume chimes follow right now, given the one the user [chosen].
  ChimeVolume volumeFor(ChimeVolume chosen) => headphones ? ChimeVolume.media : chosen;

  /// True when the phone volume is all the way down, so chimes can't be heard.
  bool get muted => volume <= 0;

  /// True when the phone is on vibrate or silent.
  bool get silenced => ringer != RingerMode.normal;

  factory AudioStatus.fromJson(Map<Object?, Object?> json) => AudioStatus(
    volume: (json['volume'] as num?)?.toInt() ?? 0,
    maxVolume: (json['maxVolume'] as num?)?.toInt() ?? 0,
    ringer: RingerMode.fromName(json['ringer']),
    headphones: json['headphones'] == true,
  );

  @override
  bool operator ==(Object other) =>
      other is AudioStatus &&
      other.volume == volume &&
      other.maxVolume == maxVolume &&
      other.ringer == ringer &&
      other.headphones == headphones;

  @override
  int get hashCode => Object.hash(volume, maxVolume, ringer, headphones);
}

/// How the sound picker groups the chimes.
enum ChimeGroup {
  bells('Bells'),
  bowls('Bowls & gongs'),
  chimes('Chimes'),
  mallets('Wood & mallets'),
  tones('Tones');

  const ChimeGroup(this.label);

  final String label;
}

/// The chimes Belltide can play. Ids match the files written by
/// tool/generate_chimes.py (`android/app/src/main/res/raw/chime_<id>.ogg`) and
/// are saved in presets, so an id never changes once it has shipped.
enum ChimeSound {
  bell('bell', 'Bell', 'A clear, bright strike', ChimeGroup.bells),
  doubleBell('double', 'Double bell', 'Two quick strikes', ChimeGroup.bells),
  rise('rise', 'Rising bells', 'Three notes going up', ChimeGroup.bells),
  fall('fall', 'Falling bells', 'Three notes coming down', ChimeGroup.bells),
  temple('temple', 'Temple bell', 'Deep, with a long ring', ChimeGroup.bells),
  bowl('bowl', 'Singing bowl', 'Warm and slowly pulsing', ChimeGroup.bowls),
  crystal('crystal', 'Crystal bowl', 'A pure tone that swells in', ChimeGroup.bowls),
  gong('gong', 'Gong', 'Low, with a wash of shimmer', ChimeGroup.bowls),
  tingsha('tingsha', 'Tingsha', 'Two small cymbals, high and long', ChimeGroup.bowls),
  chime('chime', 'High chime', 'A single bright tube', ChimeGroup.chimes),
  wind('wind', 'Wind chimes', 'A scatter of soft notes', ChimeGroup.chimes),
  glass('glass', 'Glass', 'A short, delicate ping', ChimeGroup.chimes),
  wood('wood', 'Wood block', 'A dry, short knock', ChimeGroup.mallets),
  marimba('marimba', 'Marimba', 'Two mellow wooden notes', ChimeGroup.mallets),
  kalimba('kalimba', 'Kalimba', 'Two plucked notes', ChimeGroup.mallets),
  beep('beep', 'Beep', 'Two plain beeps', ChimeGroup.tones),
  soft('soft', 'Soft tone', 'A gentle, rounded note', ChimeGroup.tones),
  chord('chord', 'Warm chord', 'An electric piano chord', ChimeGroup.tones),
  none('none', 'Silent', 'No sound', null);

  const ChimeSound(this.id, this.label, this.description, this.group);

  final String id;
  final String label;

  /// A few words on what the sound is like, for the picker.
  final String description;

  /// Null only for [none].
  final ChimeGroup? group;

  bool get isSilent => this == ChimeSound.none;

  /// Every sound that actually makes a noise.
  static List<ChimeSound> get audible =>
      values.where((s) => !s.isSilent).toList(growable: false);

  /// The audible sounds in [group], in picker order.
  static List<ChimeSound> inGroup(ChimeGroup group) =>
      values.where((s) => s.group == group).toList(growable: false);

  static ChimeSound fromId(Object? id, {ChimeSound fallback = ChimeSound.bell}) {
    for (final sound in values) {
      if (sound.id == id) return sound;
    }
    return fallback;
  }
}

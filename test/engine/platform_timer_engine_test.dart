import 'package:belltide/src/engine/platform_timer_engine.dart';
import 'package:belltide/src/model/app_settings.dart';
import 'package:belltide/src/model/audio_status.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('belltide/engine');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'audioStatus' => {'volume': 3, 'maxVolume': 7, 'ringer': 'vibrate', 'headphones': true},
        _ => null,
      };
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('settings reach Android with the level, ducking and vibrate choices', () async {
    await PlatformTimerEngine().applySettings(
      const AppSettings(
        volume: ChimeVolume.media,
        vibrate: true,
        level: 0.4,
        duckOthers: false,
        vibrateWhenSilenced: true,
      ),
    );
    expect(calls.single.method, 'applySettings');
    expect(calls.single.arguments, {
      'audioStream': 'media',
      'vibrate': true,
      'level': 0.4,
      'duckOthers': false,
      'vibrateWhenSilenced': true,
    });
  });

  test('reads the phone volume and ringer mode', () async {
    final status = await PlatformTimerEngine().audioStatus();
    expect(
      status,
      const AudioStatus(volume: 3, maxVolume: 7, ringer: RingerMode.vibrate, headphones: true),
    );
    expect(status.silenced, isTrue);
    expect(status.muted, isFalse);
  });

  test('opens the phone volume sliders', () async {
    await PlatformTimerEngine().openVolumeSettings();
    expect(calls.single.method, 'openVolumeSettings');
  });

  test('a volume or ringer change on the phone reaches listeners', () async {
    final engine = PlatformTimerEngine();
    var changes = 0;
    final sub = engine.audioChanges.listen((_) => changes++);
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('audioChanged')),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
    expect(changes, 1);
    await sub.cancel();
  });
}

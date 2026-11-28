# Belltide

Interval chimes and custom timing patterns for Android, built to keep ringing when the screen is off.

Belltide is a native Flutter app for anything that runs on a rhythm: recurring chimes every few minutes, hold and release sets for stretching or physical therapy, and work and rest cycles that don't fit a standard Pomodoro. Timers run in a foreground service, so chimes stay on time with the screen locked or the app in the background.

## Status

Early development. Android first.

The v1 feature set and the optional ClickUp integration are implemented and covered by unit and widget tests, and the app builds as a debug and release APK. Screen-off timing has only had a short check: one phone, plugged in, a three-minute timer. The longer runs on battery and in Doze have not been done. The way chimes mix with other apps' audio has been measured on that phone (a Pixel 9 Pro XL on Android 17 with Bluetooth earbuds) for sound previews and for timer chimes with the screen on and off, but not on the phone speaker. The ClickUp integration has only been tested against a simulated API; that is roadmap step 3, and [docs/reliability-testing.md](docs/reliability-testing.md) describes how to run it.

## Features

### v1

- **Interval chimes:** a chime at a set interval, toggled on or off per timer. Runs until stopped or for a set number of chimes.
- **Custom sequences:** chain steps of any length, for example a 10 second hold followed by 30 seconds off, repeated for a set number of rounds. Optional "get ready" countdown and finish sound.
- **Background reliability:** an Android foreground service with a persistent notification keeps chimes going while the screen is off. The notification shows a live countdown with pause, skip and stop controls.
- **Presets:** save a sequence once and start it with one tap. Several timers can run at the same time.
- **Per-step sounds:** a different chime for each step, so you know which phase starts without looking. Eighteen built-in sounds in five groups (bells, bowls and gongs, chimes, wood and mallets, tones), plus silent steps. The picker plays each sound as you tap it, so you can compare before choosing.
- **Plays alongside other audio:** a chime mixes with music, a video or a podcast instead of stopping it, and can lower the other audio for a moment so it stays easy to hear.
- **Volume you control:** a chime volume slider in Settings, on top of the phone's alarm or media volume. While Belltide is open, the phone's volume buttons adjust the volume chimes use. Through headphones or a Bluetooth speaker, chimes use the media volume so they mix with what you are listening to.
- **Works on vibrate and silent:** chimes keep playing when the ringer is on vibrate or silent, or can buzz instead if you prefer.

The app opens with three sample timers (a five-minute mindfulness bell, stretch holds, and a 50/10 work and rest cycle). Edit or delete them freely.

### ClickUp integration (optional)

Search tasks and subtasks, attach a timer to one, and run several timers for different tasks at once while each stays in sync with its task.

- **Connect** in Settings › ClickUp with a personal API token (ClickUp › Settings › Apps › API Token). Pick a workspace if you have more than one.
- **Search** from the task icon on the home screen, or from "Link a task" in the timer editor. Results cover tasks and subtasks, most recently updated first, filtered to tasks assigned to you unless you turn that off. Every word you type must appear in the task name, custom id, list, folder, status, or the parent task's name, so typing a parent finds its subtasks. Pasting a task link or id (including custom ids like `DEV-42`) opens that exact task even if it isn't in the loaded results.
- **Attach a timer** by linking it in the editor, or by choosing a task in search and starting one of your timers for it. That saves a copy of the timer linked to the task, so each task can have its own timer running at the same time.
- **Time logging.** Each stretch of running time (start or resume until pause, stop or finish) becomes a ClickUp time entry on the linked task, described as "*timer name* (Belltide)". ClickUp allows only one running timer per user, so Belltide creates finished entries instead of using ClickUp's live timer; that is what lets several tasks be timed at once. Entries are queued on the phone and retried when the connection returns.
- **Staying in sync.** Linked task names and statuses refresh when the app opens. A task deleted in ClickUp is marked "not found" on its timer.

#### What the ClickUp API allows

Belltide uses ClickUp's public REST API (v2) with your own token. That API has no text search and no access to ClickUp Brain or other AI features, so search runs on the phone over the tasks Belltide loads: 300 at first (in pages of 100), with "Load more" for older ones, plus direct lookup by link or id. ClickUp's own keyword and AI search is only available inside ClickUp and its assistant integrations, not to third-party apps using a personal token.

The requests Belltide makes are:

| Purpose | Request |
| --- | --- |
| Check the token, get your user id | `GET /api/v2/user` |
| List workspaces | `GET /api/v2/team` |
| Load tasks and subtasks for search | `GET /api/v2/team/{team_id}/task?subtasks=true&order_by=updated&assignees[]=…` |
| Look up a task, refresh a linked task | `GET /api/v2/task/{task_id}` |
| Log time | `POST /api/v2/team/{team_id}/time_entries` with `start`, `duration` and `tid` |

The token is encrypted with a key in the Android Keystore and excluded from cloud backups, along with the time-entry queue. Disconnecting deletes the token and any entries not yet sent.

## How it runs

- Flutter (Dart) app, Android target
- Timer engine runs in an Android foreground service; the Flutter UI reads its state
- Sequences and presets are stored on the device
- No account and no server; the app works offline
- ClickUp integration is opt-in and talks directly to the ClickUp API with the user's own token

### Timing

The engine is written in Kotlin and lives in the foreground service, not in Dart. Three things keep it on time with the screen off:

1. **Foreground service.** Android keeps the process alive and, because it runs at foreground-service priority, honours its wake lock even in Doze.
2. **Partial wake lock while a timer runs.** The CPU stays awake for the next chime. When every timer is paused, the lock is released.
3. **Schedule computed from `SystemClock.elapsedRealtime`.** Each chime's time comes from the timer's start time and its steps, never from "now plus the step length". A late wake-up plays the chime late but does not shift any later chime. If a wake-up is more than five seconds late, that chime is skipped rather than played out of place, and if several boundaries were missed only the most recent one sounds.

For timers linked to a ClickUp task, the service records each stretch of running time when the timer pauses, stops or finishes, converts it to wall-clock time, and queues it for upload on a background thread. Uploads that fail for a network, rate-limit or token problem stay in the queue and are retried when the service starts, when another entry is added, or when the app opens. An entry ClickUp refuses outright (for example because the task was deleted) is dropped and the reason is shown in Settings › ClickUp.

Running timers are saved on every change. If Android kills the service, it restarts it, or the app restores it the next time it opens, and the timers continue on their original schedule. Timers do not survive a reboot.

### Sound

Chimes play through a `SoundPool` on either the alarm volume (the default, usually loud and not tied to media volume) or the media volume, chosen in Settings.

- **Headphones and Bluetooth.** While headphones or an external speaker carry the phone's audio, chimes always play as media, whichever volume is chosen. Android routes alarm audio to the phone speaker as well as the headphones and takes the level of both from the speaker's volume. Measured on a Pixel 9 Pro XL with Bluetooth earbuds, that played the chime at -61 dB and muted the video under it; as media, the chime played at the media volume and the video dipped by 14 dB. Settings shows which phone volume is in use, and the volume buttons follow it.

- **Other audio keeps playing.** `SoundPool` never takes audio focus, so a chime mixes with whatever else is playing. With "Lower other audio during chimes" on (the default), Belltide asks for transient "may duck" audio focus for about the first 70% of the chime (at most three seconds) and then gives it back. Most players dip their volume; some, such as podcast apps, pause and resume instead. If Android refuses the request (during a phone call, for example) the chime plays over the other audio at full level.
- **Two volume controls.** The chime volume slider in Settings scales chimes relative to everything else on the phone (the gain is the slider position squared, which sounds even to the ear). The phone's own alarm or media volume still applies on top. Settings shows that phone volume, opens the system volume panel, and the hardware volume buttons adjust it while the app is on screen.
- **Vibrate and silent.** Alarm and media audio are not muted by the ringer switch, so chimes play in vibrate and silent mode. "Vibrate instead when silenced" turns that around: while the ringer is on vibrate or silent, chimes buzz and make no sound. Vibration always uses the alarm vibration usage, which Android delivers with the screen off and the ringer silenced.
- **Do Not Disturb.** Alarms and media are allowed through Do Not Disturb by default, but a schedule or mode that blocks them (or "total silence") will mute chimes too.

Sounds are loaded when a timer starts, so its chimes are already decoded when they are due.

### Android details

| Item | Choice |
| --- | --- |
| Minimum Android version | 8.0 (API 26) |
| Foreground service type | `specialUse`, with a subtype explaining the interval-timer use |
| Permissions | `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SPECIAL_USE`, `WAKE_LOCK`, `POST_NOTIFICATIONS`, `VIBRATE`, `INTERNET` (ClickUp only) |
| Notification permission | Requested the first time a timer starts (Android 13+). Timers still ring without it; only the notification controls are hidden. |
| Battery optimization | Not requested. Settings links to the system page for phones that stop foreground services anyway. |

Publishing to Google Play will need a foreground service declaration for `specialUse` in the Play Console.

## Getting started

```bash
git clone https://github.com/iLevyTate/belltide.git
cd belltide
flutter pub get
flutter run
```

Requires Flutter 3.50 or later (Dart 3.14) and an Android device or emulator (Android 8.0 or later). The project uses the `material_ui` package that replaced `package:flutter/material.dart` in recent Flutter releases.

## Development

```bash
flutter analyze
flutter test
```

The Kotlin engine has its own JVM unit tests. Gradle's wrapper script is generated by the Flutter tool, so build once before running them:

```bash
flutter build apk --debug
cd android && ./gradlew :app:testDebugUnitTest :app:lintDebug
```

The JSON exchanged between Dart and Kotlin is pinned by fixtures in `test/fixtures/`, which both test suites read. Change them together.

### Releasing

Release builds are signed with the debug key until you add your own. Create a keystore once and keep it safe; Google Play needs the same key for every update:

```bash
keytool -genkeypair -v -keystore android/belltide-release.jks -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000 -alias belltide
```

Copy `android/key.properties.example` to `android/key.properties` and fill in the passwords. Both files are ignored by git. Then build:

```bash
flutter build appbundle
```

Use `flutter build apk --release` for a file you can install directly. Bump `version` in `pubspec.yaml` and `appVersion` in `lib/src/app_info.dart` together.

### Chime sounds

The sounds are synthesized by `tool/generate_chimes.py` (modal synthesis with a synthetic room reverb, no third-party audio) and committed as stereo 32 kHz Ogg files in `android/app/src/main/res/raw/`. Every sound is matched to the same loudness, so switching sounds doesn't change how loud a chime is. To change one, edit the script and regenerate from the repository root:

```bash
python3 tool/generate_chimes.py
```

It needs `numpy`, and `ffmpeg` for Ogg output. The script also writes `service/ChimeCatalog.kt` (resource ids and lengths), so the Kotlin side can't drift from the files. The Dart list in `lib/src/model/chime_sound.dart` is kept by hand; `test/model_test.dart` fails if its ids and the files differ. Ids are saved in presets, so don't rename one that has shipped.

`SoundPool` decodes each sound into a buffer of about 1 MB, which is why the files are 32 kHz and at most 7.5 seconds long; the script refuses to write anything bigger.

### Project layout

```
lib/
  main.dart                     App entry point
  src/model/                    Presets, steps, sounds, task links, running-timer snapshots, settings
  src/engine/                   Dart interface to the timer service (method and event channels)
  src/clickup/                  ClickUp API client, on-device task search, connection state
  src/data/                     On-device storage (shared_preferences) and sample timers
  src/state/                    BelltideController: presets, running state, settings
  src/ui/                       Home, editor, settings, pickers
android/app/src/main/kotlin/io/github/ilevytate/belltide/
  MainActivity.kt               Platform channels, permission requests
  engine/                       Pure timing logic (Timeline, TimerEngine) and JSON
  service/                      TimerService, notification, SoundPool player and mix rules, persistence
  clickup/                      Encrypted token, time-entry queue and uploader
android/app/src/test/           JVM unit tests for the engine
test/                           Dart unit and widget tests, shared fixtures
tool/generate_chimes.py         Chime synthesis
docs/reliability-testing.md     Screen-off test plan for real devices
```

## Roadmap

1. ~~Single interval chime with on/off control~~
2. ~~Multi-step sequences with rounds~~
3. Foreground service and lock-screen reliability testing (service built; device testing to do)
4. ~~Saved presets and per-step sounds~~
5. ~~ClickUp task search and timer linking~~ (built and tested against a simulated API; needs a check with a real account)

## License

MIT

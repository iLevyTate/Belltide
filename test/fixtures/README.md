# Wire-format fixtures

These files pin the JSON exchanged between the Flutter UI and the Android
timer service. Both test suites read them:

- `engine_config.json`: what `TimerPreset.toEngineJson()` produces for the
  "Stretch holds" sample, and what `EngineJson.parseConfig` reads.
- `engine_state.json`: what `EngineJson.snapshotsToJson` produces 17 seconds
  into that timer, and what `EngineState.fromJson` reads.
- `engine_config_task.json`: the same timer linked to a ClickUp task, which is
  how the service learns where to log time.

If you change the format, update the fixture and both sides together.

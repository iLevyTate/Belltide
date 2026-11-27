# Screen-off reliability testing

Roadmap step 3. The timing logic is covered by JVM unit tests, but whether chimes stay on time with the screen off depends on the device, its Android version and its manufacturer's battery management. This plan checks that on real hardware.

## Setup

Install a release build, since debug builds run slower and behave differently under power management:

```bash
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Keep a log running for the whole session. The service logs how late each wake-up was:

```bash
adb logcat -s BelltideTimerService
```

Each tick prints a line like `tick 3 ms after due`. Values under about 50 ms are normal. Anything over a second points to the CPU sleeping through the wake lock.

## Test timers

Create these in the app:

| Name | Pattern | What it exercises |
| --- | --- | --- |
| Fast | Sequence: Hold 10 s (Bell), Rest 5 s (Wood), repeat until stopped | Short steps, frequent wake-ups |
| Slow | Interval: every 5 min, repeat until stopped | Long idle gaps, where Doze is most likely to kick in |
| Finite | Sequence: Hold 10 s, Rest 30 s, 3 rounds, 5 s get ready, finish sound | Lead-in, finish chime, service shutdown |

## Checks

Run each check with the screen off unless noted. For each, note the device, Android version, result, and the largest "ms after due" value in the log.

1. **Screen off, plugged in.** Start Fast and Slow, lock the phone, wait 30 minutes. Every chime should sound and the log should show no large delays.
2. **Screen off, on battery.** Unplug and repeat check 1 for 60 minutes. This is the real-world case.
3. **Forced Doze.** Start Fast and Slow, lock the phone, then force deep idle:

   ```bash
   adb shell dumpsys battery unplug
   adb shell dumpsys deviceidle force-idle
   ```

   Wait 15 minutes, then restore normal behavior:

   ```bash
   adb shell dumpsys deviceidle unforce
   adb shell dumpsys battery reset
   ```

4. **App standby.** With timers running, mark the app inactive and confirm chimes continue:

   ```bash
   adb shell am set-inactive io.github.ilevytate.belltide true
   ```

5. **Swiped from recents.** Start Fast, swipe Belltide away from the recent apps screen, lock the phone. Chimes should continue and the notification should stay.
6. **Process killed.** Start Slow, note the time of the next chime, then stop the app and reopen it:

   ```bash
   adb shell am force-stop io.github.ilevytate.belltide
   ```

   Reopen Belltide. Slow should be running again with the same next-chime time as before, not restarted from zero.
7. **Notification controls.** From the lock screen, use Pause, Resume, Skip and Stop on the notification. With two timers running, use Pause all and Stop all.
8. **Finish.** Run Finite to the end with the screen off. The finish sound plays, the notification disappears, and the switch in the app is off.
9. **Notification permission denied** (Android 13+). Deny the permission on first start. The timer should still chime; only the notification is missing.
10. **Audio routing.** With headphones connected, check the alarm and media volume settings: alarm should usually also play on the speaker, media only in the headphones. Check that both play with the ringer on silent.

## Inspecting state

```bash
# Is the foreground service running, and with which type?
adb shell dumpsys activity services io.github.ilevytate.belltide

# Is the wake lock held? (Only while a timer is running and not paused.)
adb shell dumpsys power | grep -i belltide
```

## Devices to cover

At minimum: one Pixel or other near-stock device on the latest Android, one Android 13 device (notification permission), one Android 14 or later device (foreground service types), and at least one Samsung or Xiaomi phone, since those manufacturers are the most aggressive about stopping background work. If chimes stop on those, the Battery optimization link in Settings is the first thing to try; record whether it fixes the problem.

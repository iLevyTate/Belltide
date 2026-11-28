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
10. **Audio routing.** On the phone speaker, check the alarm and media volume settings: each follows its own phone volume. Connect headphones or a Bluetooth speaker: chimes play only through them, at the media volume, with either setting, and Settings shows "Phone media volume". Check that chimes play with the ringer on silent.

## Sound checks

Run these with the screen on first, then repeat 11 and 13 with the screen off. Keep a second log open for the player:

```bash
adb logcat -s BelltideChimePlayer
```

11. **Over other audio.** Play a video or music, then start Fast. The other audio keeps playing, dips for each chime and comes back. If the log says `Other audio was not lowered`, Android refused the request; note the focus result. Repeat with "Lower other audio during chimes" off: nothing dips and the chime is still audible. While a chime plays, this shows who holds audio focus:

    ```bash
    adb shell dumpsys audio | grep -A8 "Audio Focus stack"
    ```

    Belltide should appear with `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK` during a chime and be gone a few seconds later.

    Do this once on the phone speaker and once over Bluetooth. To see the levels Android applies, run this while a chime plays and find the two tracks (Belltide's uid and the player's):

    ```bash
    adb shell dumpsys media.audio_flinger | grep -B3 -A12 "Active tracks"
    ```

    The player's track should keep a finite `PortVol dB` and show a negative `VS dB` (the dip). `-inf` means the other audio was muted, not lowered. Belltide's track should be on the same output as the player's.
12. **Volume controls.** In Settings, drag the chime volume slider: a bell plays at the new level when you let go, and at 0% ("Muted") nothing plays. Press the phone's volume buttons while Belltide is open: the alarm (or media) volume changes, not the ring volume, and the number in Settings follows. With headphones connected and "Alarm volume" chosen, the tile reads "Phone media volume" and the buttons change the media volume; unplug them and it goes back to the alarm volume. "Adjust" opens the phone's volume panel. With the phone volume at zero, Settings says chimes can't be heard.
13. **Vibrate and silent.** Switch the ringer to vibrate, then to silent. Settings shows the mode, and chimes still play at the alarm or media volume. Turn on "Vibrate instead when silenced": chimes buzz and make no sound, and sound returns when the ringer is back on. With "Vibrate with each chime" on, the buzz arrives with the screen off. `adb shell dumpsys vibrator_manager` lists recent vibrations and why any were ignored.
14. **Do Not Disturb.** With the default Do Not Disturb settings, alarms and media are allowed and chimes play. Note what happens in any mode that blocks alarms.
15. **Sound picker.** Open a timer and tap its sound. Each of the 18 sounds plays when tapped, a new tap cuts off the one before, and nothing is saved until "Use …" is pressed. Listen for clicks, distortion at full volume, and sounds that seem much louder or quieter than the rest.
16. **Calls.** During a phone call, a chime must not interrupt or lower the call audio.

## ClickUp checks

Use a test workspace or a task you don't mind adding time entries to.

17. **Connect.** Settings › ClickUp, paste a personal token. A wrong token shows an error and isn't saved. With several workspaces, you're asked to choose one.
18. **Search.** Open the task icon on the home screen. Check that subtasks appear with "Subtask of …", that typing a parent's name finds its subtasks, that "Assigned to me" and "Include closed" change the results, and that pasting a task link (and a custom id, if your workspace uses them) finds a task that isn't in the list.
19. **Log time.** Start a timer for a task, let it run about a minute, pause it, resume, then stop it. The task in ClickUp should show two time entries named "*timer* (Belltide)" whose lengths match the running time.
20. **Several tasks at once.** Start timers for two different tasks at the same time, stop both, and check each task got its own entry.
21. **Offline.** Turn on airplane mode, run and stop a linked timer, then turn the network back on and open the app. Settings › ClickUp should show the entry waiting, then sent.
22. **Screen off.** Run a finite linked sequence to the end with the screen off. Its time entry should appear in ClickUp without opening the app.
23. **Renamed or deleted task.** Rename a linked task in ClickUp and reopen Belltide: the card shows the new name. Delete it: the card says "not found", and a time entry for it is dropped with an explanation in Settings › ClickUp.

Upload attempts log to `adb logcat -s BelltideClickUp` when they fail.

## Inspecting state

```bash
# Is the foreground service running, and with which type?
adb shell dumpsys activity services io.github.ilevytate.belltide

# Is the wake lock held? (Only while a timer is running and not paused.)
adb shell dumpsys power | grep -i belltide
```

## Devices to cover

At minimum: one Pixel or other near-stock device on the latest Android, one Android 13 device (notification permission), one Android 14 or later device (foreground service types), and at least one Samsung or Xiaomi phone, since those manufacturers are the most aggressive about stopping background work. If chimes stop on those, the Battery optimization link in Settings is the first thing to try; record whether it fixes the problem.

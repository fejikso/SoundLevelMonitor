# Sound Level Monitor (MVP)

A minimal Flutter app that measures ambient noise through the device microphone, color-codes custom thresholds, aggregates min/mean/max levels per interval, and exports a CSV summary. Supports Android and iOS (building for iOS still requires macOS/Xcode).

## Features
- Live decibel reading with color feedback (Calm/Busy/Loud/Hazard)
- Configurable recording interval (15 seconds to 5 minutes)
- In-memory history of min/mean/max values per interval
- Record, Pause, Export (CSV share sheet), and About flows

## Prerequisites
1. Install Flutter 3.38+ and add it to your `PATH` or run it explicitly (e.g. `/mnt/vol1/var/flutter/bin/flutter`).
2. Android: enable Developer Options → USB debugging on your phone (Settings → About phone → tap Build number 7× → System → Developer options).
3. iOS: use Xcode on macOS, add a signing team, and trust the developer profile on-device.

## Run on Android (step-by-step)
1. Connect the phone via USB and accept the fingerprint prompt.
2. From the project root run:
   ```bash
   /mnt/vol1/var/flutter/bin/flutter devices
   /mnt/vol1/var/flutter/bin/flutter run
   ```
3. The build can take a few minutes the first time. Keep the terminal open—press `q` to stop the app.

## Run on iOS (summary)
1. Open `ios/Runner.xcworkspace` in Xcode on macOS.
2. Set your Development Team under Runner → Signing & Capabilities.
3. Plug in the iPhone, select it from the Run target picker, then press ▶️.

## Manual Test Checklist (beginner friendly)
Follow these steps after the app installs:

1. **Launch & permissions**
   - Tap `Record`.
   - Accept the microphone permission prompt. If denied, go to device Settings → App → Permissions → enable Microphone, then retry `Record`.

2. **Live reading**
   - Speak or play music; confirm the large decibel number changes.
   - Watch the color band: green (calm) should change to orange/red as levels rise.

3. **Interval storage**
   - Leave the app recording for at least one full interval (default 1 minute; adjust via the slider if you want a quicker test).
   - After the interval completes, ensure a new entry appears under “Recorded intervals” showing min/mean/max.

4. **Pause & resume**
   - Tap `Pause`; the live number should freeze and the Record button becomes active again.
   - Tap `Record` to resume and verify readings continue.

5. **Export CSV**
   - Once you have at least one interval, tap `Export`.
   - Choose a target (e.g., Gmail, Drive). The attachment named `sound_history.csv` should include timestamp, min, mean, and max columns.

6. **About dialog**
   - Tap `About` and confirm the informational dialog appears; dismiss it to return.

## Tips
- Use shorter intervals (slider) while testing so entries appear faster.
- If audio capture stops unexpectedly, the banner at the top will guide you to restart.
- Clearing the app’s data (Settings → Apps) resets stored intervals.

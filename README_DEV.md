# Sound Level Monitor – Developer Notes

This document summarizes the key implementation details and tunable parameters for the Sound Level Monitor app. It supplements `README.md`, which focuses on end-user setup.

## Architecture Overview

- **State management:** The app uses `MonitorController` (`lib/monitor_controller.dart`) as a `ChangeNotifier` that wraps all business logic: microphone ingestion, smoothing, interval aggregation, color-band selection, persistence, and keep-awake control. The UI (`lib/main.dart`) subscribes via `ChangeNotifierProvider`.
- **Audio ingestion:** `noise_meter` streams `NoiseReading` objects with `meanDecibel`/`maxDecibel`. We only read the `meanDecibel` channel; the controller optionally smooths it and stores each sample into a fixed-length buffer (`_sampleBuffer`) aligned to the current recording interval.
- **UI layers:** `_MonitorContent` renders the live panel, controls, chart/stats panel, and interval history. `_ControlsWrap` ensures buttons adapt to the available width. `_LevelChart` consumes the sample buffer and draws the “panning” min/mean/max data with FL Chart.
- **Persistence:** `shared_preferences` stores keep-awake state, palette mode, and recording interval. The controller loads these values in `_restorePreferences()` and writes updates from the relevant setters.

## Key Tunables

### 1. Exponential Smoothing (`smoothingAlpha`)
Defined in `MonitorController`:
```dart
static const double smoothingAlpha = 0.1; // tweak to alter responsiveness
```
Used in `_handleReading()`:
```dart
_currentDb = _currentDb == null
    ? value
    : value * smoothingAlpha + _currentDb! * (1 - smoothingAlpha);
```
Increase `smoothingAlpha` for snappier responses (less smoothing); decrease it for more inertia. This value also affects threshold-crossing detection, since `_currentDb` drives `_updateActiveBand()` and the chart’s live line.

### 2. Threshold Hold Duration
```dart
static const Duration thresholdHoldDuration = Duration(seconds: 5);
```
When a reading crosses into a higher noise band, the background/indicator color locks for this duration before returning to the smoothed real-time value. Adjust as needed for faster/slower fall-back.

### 3. Recording Interval
The default interval is 30 seconds (`_interval = const Duration(milliseconds: 30000);`). Users can change it via Settings (Options screen), and the controller also persists it across launches. Internally:
- `_trimSamples()` keeps only samples within the last `_interval`.
- `_finalizeWindow()` aggregates min/mean/max for history entries on every interval boundary.

### 4. Color Palettes
`_paletteForMode()` defines two palettes (normal vs. high-contrast). Add additional modes or modify colors by extending `_PaletteColors`. The chart’s band shading pulls from these colors with slight transparency via `.withValues(alpha: …)`.

### 5. Chart Ranges and Guides
`_LevelChart` uses fixed vertical bounds (30–90 dB) and draws two dashed lines:
- Red horizontal line at the current max reading in the window (`maxLineValue`).
- Black horizontal line at the window mean.
Threshold bands correspond to the current caution/danger levels; change the shading colors or axis limits in `_buildChartData`.

### 6. Sample Buffer
`_sampleBuffer` holds `SamplePoint` objects for every incoming reading. If you need more/less temporal resolution, adjust the capture strategy inside `_addSamplePoint()` (e.g., sub-sample, decimate, or store extra fields such as raw max).

### 7. Threshold Crossing Delay
The app filters “threshold crossings” so that brief spikes don’t thrash the color bands:
```dart
static const double defaultCrossingSeconds = 0.2;
double _thresholdCrossingSeconds;

Future<void> setThresholdCrossingSeconds(double seconds) { ... }
```
The Options screen exposes a 0.1–1.0 s slider, and the value is persisted. Lower values make the UI flip bands immediately; higher values require sustained loudness before the color changes.

### 8. Keep-Screen-Awake Default
`_keepScreenAwake` starts `true` and is persisted. To change the default, edit the initialization in `_restorePreferences()` and/or the constructors.

## Implementation Notes

- **Smoothing vs. raw chart:** The chart displays the smoothed `_currentDb` value to match the live panel. If you want to plot raw samples, store both raw and smoothed values in `SamplePoint`.
- **Threshold logic:** `_updateActiveBand()` compares the smoothed reading (`meanValue`) against the ordered threshold list. It increments `_flashCounter` to trigger the overlay animation and resets `_bandHoldUntil` after `thresholdHoldDuration`.
- **Responsiveness:** `_ControlsWrap` uses a `Wrap` with width constraints and smaller button padding to keep controls within two rows on narrow devices. Adjust `columns` logic or `itemWidth` clamp if you need a different layout.
- **Persistence keys:** See `_keepAwakeKey`, `_paletteKey`, and `_intervalKey` for storage naming. Add new keys alongside `_restorePreferences()` to keep the logic centralized.



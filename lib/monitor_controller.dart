import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:noise_meter/noise_meter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

enum PaletteMode { normal, highContrast }

class ThresholdBand {
  const ThresholdBand({
    required this.limitDb,
    required this.label,
    required this.color,
    required this.foreground,
  });

  final double limitDb;
  final String label;
  final Color color;
  final Color foreground;
}

class IntervalSnapshot {
  IntervalSnapshot({
    required this.timestamp,
    required this.minDb,
    required this.meanDb,
    required this.maxDb,
  });

  final DateTime timestamp;
  final double minDb;
  final double meanDb;
  final double maxDb;
}

class IntervalStats {
  const IntervalStats({
    required this.minDb,
    required this.meanDb,
    required this.maxDb,
  });

  final double minDb;
  final double meanDb;
  final double maxDb;
}

class HistogramBucket {
  const HistogramBucket({
    required this.lowerBound,
    required this.upperBound,
    required this.seconds,
  });

  final double lowerBound;
  final double upperBound;
  final double seconds;
}

class SamplePoint {
  SamplePoint({
    required this.timestamp,
    required this.minDb,
    required this.meanDb,
    required this.maxDb,
    required this.positionSeconds,
  });

  final DateTime timestamp;
  final double minDb;
  final double meanDb;
  final double maxDb;
  final double positionSeconds;
}

class MonitorController extends ChangeNotifier {
  static const double smoothingAlpha = 0.1;
  static const double defaultCrossingSeconds = 0.2;
  static const double histogramMinDb = 40;
  static const double histogramMaxDb = 100;
  static const double histogramStepDb = 5;
  static final int _histogramBinCount =
      ((histogramMaxDb - histogramMinDb) / histogramStepDb).round();

  MonitorController() {
    _refreshThresholds();
    _activeBandIndex = _thresholdIndexFor(0);
    _restorePreferences();
  }

  static const Duration thresholdHoldDuration = Duration(seconds: 5);
  final NoiseMeter _noiseMeter = NoiseMeter();
  StreamSubscription<NoiseReading>? _noiseSubscription;
  Timer? _intervalTimer;

  bool _isRecording = false;
  double? _currentDb;
  Duration _interval = const Duration(milliseconds: 30000);
  late final List<ThresholdBand> _thresholds;
  String? _errorMessage;
  int _activeBandIndex = 0;
  DateTime? _bandHoldUntil;
  double _cautionThreshold = 70;
  double _dangerThreshold = 80;
  int _flashCounter = 0;
  bool _keepScreenAwake = false;
  PaletteMode _paletteMode = PaletteMode.normal;
  DateTime? _windowStart;
  int? _pendingBandIndex;
  DateTime? _pendingBandStart;

  int _windowCount = 0;
  double _windowSum = 0;
  double? _windowMin;
  double? _windowMax;
  final List<IntervalSnapshot> _history = [];
  final List<SamplePoint> _sampleBuffer = [];
  double _thresholdCrossingSeconds = defaultCrossingSeconds;
  final List<double> _histogramSeconds =
      List<double>.filled(_histogramBinCount, 0);
  DateTime? _lastSampleTimestamp;
  double? _lastSampleDb;
  double _chartElapsedSeconds = 0;
  final Set<int> _hiddenHistogramBins = <int>{};

  bool get isRecording => _isRecording;
  double? get currentDb => _currentDb;
  Duration get interval => _interval;
  double get intervalMinutes => _interval.inSeconds / 60;
  List<ThresholdBand> get thresholds => List.unmodifiable(_thresholds);
  List<IntervalSnapshot> get history => List.unmodifiable(_history);
  List<IntervalSnapshot> get sessionSeries =>
      List.unmodifiable(_history.reversed.toList());
  List<SamplePoint> get intervalSamples => List.unmodifiable(_sampleBuffer);
  Set<int> get hiddenHistogramBins => Set.unmodifiable(_hiddenHistogramBins);
  String? get errorMessage => _errorMessage;
  double get cautionThreshold => _cautionThreshold;
  double get dangerThreshold => _dangerThreshold;
  int get flashCounter => _flashCounter;
  bool get keepScreenAwake => _keepScreenAwake;
  PaletteMode get paletteMode => _paletteMode;
  double get thresholdCrossingSeconds => _thresholdCrossingSeconds;
  double get intervalProgress {
    if (!_isRecording || _windowStart == null || _interval.inMilliseconds == 0) {
      return 0;
    }
    final elapsed =
        DateTime.now().difference(_windowStart!).inMilliseconds.toDouble();
    final total = _interval.inMilliseconds.toDouble();
    return (elapsed / total).clamp(0, 1);
  }
  List<HistogramBucket> get histogramBuckets => List.generate(
        _histogramSeconds.length,
        (index) {
          final lower = histogramMinDb + histogramStepDb * index;
          final upper = lower + histogramStepDb;
          return HistogramBucket(
            lowerBound: lower,
            upperBound: upper,
            seconds: _histogramSeconds[index],
          );
        },
      );
  IntervalStats? get currentIntervalStats => _windowCount == 0
      ? null
      : IntervalStats(
          minDb: _windowMin!,
          meanDb: _windowSum / _windowCount,
          maxDb: _windowMax!,
        );

  ThresholdBand get activeBand {
    return _thresholds[_activeBandIndex];
  }

  Future<void> startMonitoring() async {
    if (_isRecording) return;

    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      _errorMessage = micStatus.isPermanentlyDenied
          ? 'Microphone permission denied. Enable it in system settings.'
          : 'Microphone permission is required to capture sound levels.';
      notifyListeners();
      return;
    }

    _errorMessage = null;

    try {
      _noiseSubscription = _noiseMeter.noise.listen(
        _handleReading,
        onError: _handleError,
        cancelOnError: true,
      );
      _resetHistogram(silent: true);
      _isRecording = true;
      _windowStart = DateTime.now();
      _startIntervalTimer();
      notifyListeners();
    } on Exception catch (error) {
      _isRecording = false;
      await _noiseSubscription?.cancel();
      _noiseSubscription = null;
      _errorMessage = 'Failed to start monitoring: $error';
      notifyListeners();
    }
  }

  Future<void> pauseMonitoring() async {
    if (!_isRecording) return;
    _isRecording = false;
    _intervalTimer?.cancel();
    _intervalTimer = null;
    await _noiseSubscription?.cancel();
    _noiseSubscription = null;
    _finalizeWindow(includePartial: true);
    _windowStart = null;
    _lastSampleTimestamp = null;
    _lastSampleDb = null;
    notifyListeners();
  }

  void setIntervalMinutes(double minutes) {
    final clamped = minutes.clamp(0.25, 10.0);
    _interval = Duration(
      milliseconds: (clamped * Duration.millisecondsPerMinute).round(),
    );
    if (_isRecording) {
      _restartIntervalTimer();
    } else {
      notifyListeners();
    }
    _trimSamples();
    _persistInterval();
  }

  void clearHistory() {
    _history.clear();
    _resetHistogram(silent: true);
    notifyListeners();
  }

  bool isHistogramBinVisible(int index) {
    if (index < 0 || index >= _histogramSeconds.length) return true;
    return !_hiddenHistogramBins.contains(index);
  }

  void setHistogramBinVisibility(int index, bool isVisible) {
    if (index < 0 || index >= _histogramSeconds.length) return;
    final changed = isVisible
        ? _hiddenHistogramBins.remove(index)
        : _hiddenHistogramBins.add(index);
    if (!changed) return;
    notifyListeners();
    _persistHistogramVisibility();
  }

  void showAllHistogramBins() {
    if (_hiddenHistogramBins.isEmpty) return;
    _hiddenHistogramBins.clear();
    notifyListeners();
    _persistHistogramVisibility();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> setKeepScreenAwake(bool value) async {
    if (_keepScreenAwake == value) return;
    _keepScreenAwake = value;
    if (value) {
      await WakelockPlus.enable();
    } else {
      await WakelockPlus.disable();
    }
    notifyListeners();
  }

  void updateThresholds({double? caution, double? danger}) {
    final newCaution = (caution ?? _cautionThreshold).clamp(40, 90);
    final minDanger = (newCaution + 1).clamp(45, 110);
    final newDanger =
        (danger ?? _dangerThreshold).clamp(minDanger, 110);
    _cautionThreshold = newCaution.toDouble();
    _dangerThreshold = newDanger.toDouble();
    _refreshThresholds();
    _activeBandIndex = _thresholdIndexFor(_currentDb ?? 0);
    notifyListeners();
  }

  void setPaletteMode(PaletteMode mode) {
    if (_paletteMode == mode) return;
    _paletteMode = mode;
    _refreshThresholds();
    notifyListeners();
    _persistPalette();
  }

  Future<void> setThresholdCrossingSeconds(double seconds) async {
    final clamped = seconds.clamp(0.1, 1.0);
    if ((clamped - _thresholdCrossingSeconds).abs() < 0.0001) return;
    _thresholdCrossingSeconds = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_thresholdCrossingKey, clamped);
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  void _handleReading(NoiseReading reading) {
    var value = reading.meanDecibel;
    if (!value.isFinite) {
      value = 0;
    }
    final now = DateTime.now();
    double deltaSeconds = 0;
    if (_lastSampleTimestamp != null && _lastSampleDb != null) {
      deltaSeconds =
          now.difference(_lastSampleTimestamp!).inMilliseconds / 1000.0;
      if (deltaSeconds > 0) {
        _accumulateHistogram(_lastSampleDb!, deltaSeconds);
      } else {
        deltaSeconds = 0;
      }
    }
    _currentDb =
        _currentDb == null ? value : value * smoothingAlpha + _currentDb! * (1 - smoothingAlpha);
    _windowSum += value;
    _windowCount++;
    _windowMin = _windowMin == null ? value : min(_windowMin!, value);
    _windowMax = _windowMax == null ? value : max(_windowMax!, value);
    _addSamplePoint(value, now, deltaSeconds);
    _lastSampleTimestamp = now;
    _lastSampleDb = value;
    _updateActiveBand(value);
    notifyListeners();
  }

  void _handleError(Object error) {
    _isRecording = false;
    _intervalTimer?.cancel();
    _noiseSubscription?.cancel();
    _intervalTimer = null;
    _noiseSubscription = null;
    _errorMessage = 'Sound capture stopped unexpectedly. Tap Record to retry.';
    notifyListeners();
  }

  void _startIntervalTimer() {
    _intervalTimer?.cancel();
    _intervalTimer = Timer.periodic(_interval, (_) => _finalizeWindow());
  }

  void _restartIntervalTimer() {
    _intervalTimer?.cancel();
    if (_isRecording) {
      _intervalTimer = Timer.periodic(_interval, (_) => _finalizeWindow());
    }
  }

  void _finalizeWindow({bool includePartial = false}) {
    if (_windowCount == 0) {
      if (includePartial) {
        notifyListeners();
      }
      return;
    }

    final minDb = _windowMin!;
    final maxDb = _windowMax!;
    final meanDb = _windowSum / _windowCount;

    _history.insert(
      0,
      IntervalSnapshot(
        timestamp: DateTime.now(),
        minDb: minDb,
        meanDb: meanDb,
        maxDb: maxDb,
      ),
    );

    _windowSum = 0;
    _windowCount = 0;
    _windowMin = null;
    _windowMax = null;
    _windowStart = DateTime.now();
    _trimSamples();
    notifyListeners();
  }

  void _refreshThresholds() {
    final palette = _paletteForMode(_paletteMode);
    _thresholds = [
      ThresholdBand(
        limitDb: 55,
        label: 'Calm',
        color: palette.calmColor,
        foreground: palette.calmForeground,
      ),
      ThresholdBand(
        limitDb: _cautionThreshold,
        label: 'Caution',
        color: palette.cautionColor,
        foreground: palette.cautionForeground,
      ),
      ThresholdBand(
        limitDb: _dangerThreshold,
        label: 'Danger',
        color: palette.dangerColor,
        foreground: palette.dangerForeground,
      ),
      ThresholdBand(
        limitDb: double.infinity,
        label: 'Hazard',
        color: palette.hazardColor,
        foreground: palette.hazardForeground,
      ),
    ];
  }

  int _thresholdIndexFor(double value) {
    for (var i = 0; i < _thresholds.length; i++) {
      if (value <= _thresholds[i].limitDb) {
        return i;
      }
    }
    return _thresholds.length - 1;
  }

  void _updateActiveBand(double value) {
    final now = DateTime.now();
    final newIndex = _thresholdIndexFor(value);
    final requiredHold = Duration(
      milliseconds: (_thresholdCrossingSeconds * 1000).round(),
    );

    if (newIndex > _activeBandIndex) {
      if (_pendingBandIndex != newIndex) {
        _pendingBandIndex = newIndex;
        _pendingBandStart = now;
      }
      if (now.difference(_pendingBandStart ?? now) >= requiredHold) {
        _activeBandIndex = newIndex;
        _bandHoldUntil = now.add(thresholdHoldDuration);
        _flashCounter++;
        _pendingBandIndex = null;
        _pendingBandStart = null;
      }
      return;
    }
    if (newIndex < _activeBandIndex) {
      if (_bandHoldUntil != null && now.isBefore(_bandHoldUntil!)) {
        return;
      }
      _activeBandIndex = newIndex;
      _bandHoldUntil = null;
      _pendingBandIndex = null;
      _pendingBandStart = null;
      return;
    }
    if (_bandHoldUntil != null && now.isAfter(_bandHoldUntil!)) {
      _bandHoldUntil = null;
    }
    if (newIndex <= _activeBandIndex) {
      _pendingBandIndex = null;
      _pendingBandStart = null;
    }
  }

  void _addSamplePoint(double reading, DateTime now, double deltaSeconds) {
    _windowStart ??= now;
    if (!deltaSeconds.isFinite || deltaSeconds < 0) {
      deltaSeconds = 0;
    }
    _chartElapsedSeconds += deltaSeconds;
    final sample = SamplePoint(
      timestamp: now,
      minDb: _windowMin ?? reading,
      meanDb: reading,
      maxDb: _windowMax ?? reading,
      positionSeconds: _chartElapsedSeconds,
    );
    _sampleBuffer.add(sample);
    _trimSamples();
  }

  void _trimSamples() {
    final cutoff = DateTime.now().subtract(_interval);
    while (_sampleBuffer.isNotEmpty &&
        _sampleBuffer.first.timestamp.isBefore(cutoff)) {
      _sampleBuffer.removeAt(0);
    }
  }

  void _accumulateHistogram(double reading, double seconds) {
    final clamped = reading.clamp(histogramMinDb, histogramMaxDb);
    final index = ((clamped - histogramMinDb) / histogramStepDb)
        .floor()
        .clamp(0, _histogramSeconds.length - 1);
    _histogramSeconds[index] += seconds;
  }

  void _resetHistogram({bool silent = false}) {
    for (var i = 0; i < _histogramSeconds.length; i++) {
      _histogramSeconds[i] = 0;
    }
    _lastSampleTimestamp = null;
    _lastSampleDb = null;
    _sampleBuffer.clear();
    _chartElapsedSeconds = 0;
    if (!silent) {
      notifyListeners();
    }
  }

  Future<void> _restorePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final keepAwake = prefs.getBool(_keepAwakeKey);
    final paletteName = prefs.getString(_paletteKey);
    final minutes = prefs.getDouble(_intervalKey);

    if (keepAwake != null) {
      _keepScreenAwake = keepAwake;
      if (keepAwake) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } else {
      _keepScreenAwake = true;
      await WakelockPlus.enable();
    }

    if (paletteName != null) {
      final restored = PaletteMode.values.firstWhere(
        (mode) => mode.name == paletteName,
        orElse: () => _paletteMode,
      );
      _paletteMode = restored;
      _refreshThresholds();
    }

    if (minutes != null) {
      _interval = Duration(
        milliseconds:
            (minutes.clamp(0.25, 10.0) * Duration.millisecondsPerMinute).round(),
      );
    }

    final crossingSeconds =
        prefs.getDouble(_thresholdCrossingKey) ?? defaultCrossingSeconds;
    _thresholdCrossingSeconds = crossingSeconds.clamp(0.1, 1.0);

    final hiddenBins = prefs.getStringList(_histogramHiddenKey);
    if (hiddenBins != null) {
      _hiddenHistogramBins
        ..clear()
        ..addAll(hiddenBins
            .map(int.tryParse)
            .whereType<int>()
            .where((index) => index >= 0 && index < _histogramSeconds.length));
    }

    notifyListeners();
  }

  Future<void> _persistInterval() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_intervalKey, _interval.inSeconds / 60);
  }

  Future<void> _persistPalette() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_paletteKey, _paletteMode.name);
  }

  Future<void> _persistHistogramVisibility() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _histogramHiddenKey,
      _hiddenHistogramBins.map((index) => index.toString()).toList(),
    );
  }

  _PaletteColors _paletteForMode(PaletteMode mode) {
    switch (mode) {
      case PaletteMode.highContrast:
        return const _PaletteColors(
          calmColor: Color(0xFF00E676),
          calmForeground: Colors.black,
          cautionColor: Color(0xFFFFFF00),
          cautionForeground: Colors.black,
          dangerColor: Color(0xFFFF1744),
          dangerForeground: Colors.white,
          hazardColor: Color(0xFFFF6D00),
          hazardForeground: Colors.black,
        );
      case PaletteMode.normal:
        return const _PaletteColors(
          calmColor: Color(0xFF1B5E20),
          calmForeground: Colors.white,
          cautionColor: Color(0xFFFFC107),
          cautionForeground: Colors.black,
          dangerColor: Color(0xFFFF3D00),
          dangerForeground: Colors.white,
          hazardColor: Color(0xFFB71C1C),
          hazardForeground: Colors.white,
        );
    }
  }

  static const _keepAwakeKey = 'keep_screen_awake';
  static const _paletteKey = 'palette_mode';
  static const _intervalKey = 'recording_interval_minutes';
  static const _thresholdCrossingKey = 'threshold_crossing_seconds';
  static const _histogramHiddenKey = 'histogram_hidden_bins';
}

class _PaletteColors {
  const _PaletteColors({
    required this.calmColor,
    required this.calmForeground,
    required this.cautionColor,
    required this.cautionForeground,
    required this.dangerColor,
    required this.dangerForeground,
    required this.hazardColor,
    required this.hazardForeground,
  });

  final Color calmColor;
  final Color calmForeground;
  final Color cautionColor;
  final Color cautionForeground;
  final Color dangerColor;
  final Color dangerForeground;
  final Color hazardColor;
  final Color hazardForeground;
}


import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:noise_meter/noise_meter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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

class MonitorController extends ChangeNotifier {
  MonitorController() {
    _refreshThresholds();
    _activeBandIndex = _thresholdIndexFor(0);
  }

  static const Duration _holdDuration = Duration(seconds: 10);
  final NoiseMeter _noiseMeter = NoiseMeter();
  StreamSubscription<NoiseReading>? _noiseSubscription;
  Timer? _intervalTimer;

  bool _isRecording = false;
  double? _currentDb;
  Duration _interval = const Duration(minutes: 1);
  late final List<ThresholdBand> _thresholds;
  String? _errorMessage;
  int _activeBandIndex = 0;
  DateTime? _bandHoldUntil;
  double _cautionThreshold = 65;
  double _dangerThreshold = 75;
  int _flashCounter = 0;
  bool _keepScreenAwake = false;

  int _windowCount = 0;
  double _windowSum = 0;
  double? _windowMin;
  double? _windowMax;
  final List<IntervalSnapshot> _history = [];

  bool get isRecording => _isRecording;
  double? get currentDb => _currentDb;
  Duration get interval => _interval;
  double get intervalMinutes => _interval.inSeconds / 60;
  List<ThresholdBand> get thresholds => List.unmodifiable(_thresholds);
  List<IntervalSnapshot> get history => List.unmodifiable(_history);
  String? get errorMessage => _errorMessage;
  double get cautionThreshold => _cautionThreshold;
  double get dangerThreshold => _dangerThreshold;
  int get flashCounter => _flashCounter;
  bool get keepScreenAwake => _keepScreenAwake;
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
      _isRecording = true;
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
  }

  void clearHistory() {
    _history.clear();
    notifyListeners();
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
    _currentDb = value;
    _windowSum += value;
    _windowCount++;
    _windowMin = _windowMin == null ? value : min(_windowMin!, value);
    _windowMax = _windowMax == null ? value : max(_windowMax!, value);
    final meanValue = _windowSum / _windowCount;
    _updateActiveBand(meanValue);
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
    notifyListeners();
  }

  void _refreshThresholds() {
    _thresholds = [
      const ThresholdBand(
        limitDb: 55,
        label: 'Calm',
        color: Color(0xFF1B5E20),
        foreground: Colors.white,
      ),
      ThresholdBand(
        limitDb: _cautionThreshold,
        label: 'Caution',
        color: const Color(0xFFFFC107),
        foreground: Colors.black,
      ),
      ThresholdBand(
        limitDb: _dangerThreshold,
        label: 'Danger',
        color: const Color(0xFFFF3D00),
        foreground: Colors.white,
      ),
      const ThresholdBand(
        limitDb: double.infinity,
        label: 'Hazard',
        color: Color(0xFFB71C1C),
        foreground: Colors.white,
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
    if (newIndex > _activeBandIndex) {
      _activeBandIndex = newIndex;
      _bandHoldUntil = now.add(_holdDuration);
      _flashCounter++;
      return;
    }
    if (newIndex < _activeBandIndex) {
      if (_bandHoldUntil != null && now.isBefore(_bandHoldUntil!)) {
        return;
      }
      _activeBandIndex = newIndex;
      _bandHoldUntil = null;
      return;
    }
    if (_bandHoldUntil != null && now.isAfter(_bandHoldUntil!)) {
      _bandHoldUntil = null;
    }
  }
}


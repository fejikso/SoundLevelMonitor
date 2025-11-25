import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:noise_meter/noise_meter.dart';
import 'package:permission_handler/permission_handler.dart';

class ThresholdBand {
  const ThresholdBand({
    required this.limitDb,
    required this.label,
    required this.color,
  });

  final double limitDb;
  final String label;
  final Color color;
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

class MonitorController extends ChangeNotifier {
  MonitorController() {
    _thresholds = const [
      ThresholdBand(limitDb: 55, label: 'Calm', color: Colors.green),
      ThresholdBand(limitDb: 75, label: 'Busy', color: Colors.orange),
      ThresholdBand(limitDb: 85, label: 'Loud', color: Colors.deepOrange),
      ThresholdBand(limitDb: double.infinity, label: 'Hazard', color: Colors.red),
    ];
  }

  final NoiseMeter _noiseMeter = NoiseMeter();
  StreamSubscription<NoiseReading>? _noiseSubscription;
  Timer? _intervalTimer;

  bool _isRecording = false;
  double? _currentDb;
  Duration _interval = const Duration(minutes: 1);
  late final List<ThresholdBand> _thresholds;
  String? _errorMessage;

  final List<double> _windowSamples = [];
  double _windowSum = 0;
  final List<IntervalSnapshot> _history = [];

  bool get isRecording => _isRecording;
  double? get currentDb => _currentDb;
  Duration get interval => _interval;
  double get intervalMinutes => _interval.inSeconds / 60;
  List<ThresholdBand> get thresholds => List.unmodifiable(_thresholds);
  List<IntervalSnapshot> get history => List.unmodifiable(_history);
  String? get errorMessage => _errorMessage;

  ThresholdBand get activeBand {
    final value = _currentDb ?? 0;
    for (final band in _thresholds) {
      if (value <= band.limitDb) {
        return band;
      }
    }
    return _thresholds.last;
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

  void _handleReading(NoiseReading reading) {
    final value = reading.meanDecibel;
    _currentDb = value;
    _windowSamples.add(value);
    _windowSum += value;
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
    if (_windowSamples.isEmpty) {
      if (includePartial) {
        notifyListeners();
      }
      return;
    }

    final minDb = _windowSamples.reduce(min);
    final maxDb = _windowSamples.reduce(max);
    final meanDb = _windowSum / _windowSamples.length;

    _history.insert(
      0,
      IntervalSnapshot(
        timestamp: DateTime.now(),
        minDb: minDb,
        meanDb: meanDb,
        maxDb: maxDb,
      ),
    );

    _windowSamples.clear();
    _windowSum = 0;
    notifyListeners();
  }
}


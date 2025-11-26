import 'dart:io';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'monitor_controller.dart';

void main() {
  runApp(const SoundMonitorApp());
}

class SoundMonitorApp extends StatelessWidget {
  const SoundMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MonitorController(),
      child: MaterialApp(
        title: 'Decibel Monitor',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const MonitorHomeScreen(),
      ),
    );
  }
}

class MonitorHomeScreen extends StatelessWidget {
  const MonitorHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sound Level Monitor'),
      ),
      body: const SafeArea(
        child: _MonitorContent(),
      ),
    );
  }
}

class _MonitorContent extends StatelessWidget {
  const _MonitorContent();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MonitorController>();
    final threshold = controller.activeBand;
    final stats = controller.currentIntervalStats;
    final flashKey = controller.flashCounter;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (controller.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: MaterialBanner(
                      content: Text(controller.errorMessage!),
                      leading: const Icon(Icons.warning_rounded),
                      actions: [
                        TextButton(
                          onPressed: controller.clearError,
                          child: const Text('Dismiss'),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Stack(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: threshold.color.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: threshold.color, width: 1.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          controller.currentDb != null
                              ? controller.currentDb!.toStringAsFixed(1)
                              : '--',
                          style: Theme.of(context)
                              .textTheme
                              .displayLarge
                              ?.copyWith(
                                color: threshold.foreground,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'dB',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: threshold.foreground,
                              ),
                        ),
                      ],
                    ),
                            const SizedBox(height: 8),
                            Text(
                              _panelMessage(threshold),
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: threshold.foreground,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      if (flashKey > 0)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: TweenAnimationBuilder<double>(
                              key: ValueKey(flashKey),
                              tween: Tween(begin: 1, end: 0),
                              duration: const Duration(milliseconds: 650),
                              builder: (context, value, child) => Container(
                                decoration: BoxDecoration(
                                  color: threshold.color.withValues(alpha: 0.6 * value),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _ControlsGrid(stats: stats),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    height: 320,
                    child: _IntervalsCard(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum InsightMode { chart, hist, stats }

class _ControlsGrid extends StatefulWidget {
  const _ControlsGrid({required this.stats});

  final IntervalStats? stats;

  @override
  State<_ControlsGrid> createState() => _ControlsGridState();
}

class _ControlsGridState extends State<_ControlsGrid> {
  InsightMode _mode = InsightMode.chart;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MonitorController>();
    return Column(
      children: [
        _ControlsWrap(
          isRecording: controller.isRecording,
          onStart: controller.startMonitoring,
          onPause: controller.pauseMonitoring,
          onOptions: () => _openOptions(context),
          onAbout: () => _showAboutDialog(context),
          mode: _mode,
          onModeChanged: (value) => setState(() => _mode = value),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: () {
            switch (_mode) {
              case InsightMode.chart:
                return const _LevelChart(key: ValueKey('chart'));
              case InsightMode.hist:
                return const _HistogramCard(key: ValueKey('hist'));
              case InsightMode.stats:
                if (widget.stats == null) {
                  return const Card(
                      key: ValueKey('stats-empty'),
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No interval stats yet. Start recording to see values.',
                        ),
                      ),
                  );
                }
                return _StatsCard(
                      key: const ValueKey('stats'),
                      title: 'Current interval so far',
                      stats: widget.stats!,
                  progress: controller.intervalProgress,
                  isRecording: controller.isRecording,
                );
            }
          }(),
        ),
      ],
    );
  }
}

class _LevelChart extends StatelessWidget {
  const _LevelChart({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MonitorController>();
    final buckets = controller.secondBuckets;
    const minY = 30.0;
    const maxY = 90.0;
    final intervalSeconds =
        controller.interval.inMilliseconds / Duration.millisecondsPerSecond;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Interval trends',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 16),
            if (buckets.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text('No data yet. Start a recording to populate the chart.'),
                ),
              )
            else
              SizedBox(
                height: 220,
                child: _BoxPlotChart(
                  buckets: buckets,
                  minDb: minY,
                  maxDb: maxY,
                  intervalSeconds: intervalSeconds <= 0 ? 1 : intervalSeconds,
                  caution: controller.cautionThreshold,
                  danger: controller.dangerThreshold,
                ),
              ),
            if (buckets.isNotEmpty) ...[
              const SizedBox(height: 12),
            const SizedBox(height: 4),
            ],
          ],
        ),
      ),
    );
  }

}

class _HistogramCard extends StatelessWidget {
  const _HistogramCard({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MonitorController>();
    final buckets = controller.histogramBuckets;
    final visibleEntries = <MapEntry<int, HistogramBucket>>[];
    for (var i = 0; i < buckets.length; i++) {
      if (!controller.isHistogramBinVisible(i)) continue;
      visibleEntries.add(MapEntry(i, buckets[i]));
    }
    final hasHidden = controller.hiddenHistogramBins.isNotEmpty;
    final totalSeconds = buckets.fold<double>(
      0,
      (sum, bucket) => sum + bucket.seconds,
    );
    final maxSeconds = visibleEntries.isEmpty
        ? 0.0
        : visibleEntries
            .map((entry) => entry.value.seconds)
            .reduce(math.max)
            .toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Exposure histogram',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (hasHidden)
                  TextButton(
                    onPressed: () => controller.showAllHistogramBins(),
                    child: const Text('Reset bins'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (totalSeconds == 0)
              SizedBox(
                height: 180,
                child: Center(
                  child: Text(
                    'No histogram data yet. Start recording to see exposure time.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else if (visibleEntries.isEmpty)
              SizedBox(
                height: 180,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('All bins hidden.'),
                      TextButton(
                        onPressed: () => controller.showAllHistogramBins(),
                        child: const Text('Show all bins'),
                      ),
                    ],
                  ),
                ),
              )
            else
              SizedBox(
                height: 220,
                child: BarChart(
                  _buildChartData(
                    context,
                    visibleEntries,
                    maxSeconds == 0 ? 1 : maxSeconds,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => _exportHistogram(context),
                icon: const Icon(Icons.ios_share),
                label: const Text('Export histogram'),
              ),
            ),
            const SizedBox(height: 8),
            if (totalSeconds > 0)
              LayoutBuilder(
                builder: (context, constraints) {
                  final maxWidth = constraints.maxWidth;
                  final tileWidth =
                      maxWidth >= 520 ? (maxWidth - 12) / 2 : maxWidth;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < buckets.length; i++)
                        SizedBox(
                          width: tileWidth,
                          child: _HistogramToggle(
                            bucket: buckets[i],
                            isVisible: controller.isHistogramBinVisible(i),
                            onChanged: (value) => controller
                                .setHistogramBinVisibility(i, value),
                          ),
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  BarChartData _buildChartData(
    BuildContext context,
    List<MapEntry<int, HistogramBucket>> entries,
    double maxValue,
  ) {
    final theme = Theme.of(context);
    final groups = <BarChartGroupData>[];
    for (var i = 0; i < entries.length; i++) {
      final bucket = entries[i].value;
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: bucket.seconds,
              width: 14,
              borderRadius: BorderRadius.circular(6),
              color: theme.colorScheme.primary,
              rodStackItems: [],
            ),
          ],
        ),
      );
    }
    return BarChartData(
      minY: 0,
      maxY: maxValue * 1.1,
      gridData: FlGridData(show: true, horizontalInterval: maxValue / 4),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: theme.dividerColor),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 36,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index < 0 || index >= entries.length) {
                return const SizedBox.shrink();
              }
              final bucket = entries[index].value;
              return Transform.rotate(
                angle: -math.pi / 4,
                child: Text(
                  '${bucket.lowerBound.toInt()}-${bucket.upperBound.toInt()}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 48,
            getTitlesWidget: (value, meta) =>
                Text(_formatExposure(value.toDouble())),
          ),
        ),
      ),
      barGroups: groups,
    );
  }
}

class _BoxPlotChart extends StatelessWidget {
  const _BoxPlotChart({
    required this.buckets,
    required this.minDb,
    required this.maxDb,
    required this.intervalSeconds,
    required this.caution,
    required this.danger,
  });

  final List<SecondBoxStats> buckets;
  final double minDb;
  final double maxDb;
  final double intervalSeconds;
  final double caution;
  final double danger;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BoxPlotPainter(
        buckets: buckets,
        minDb: minDb,
        maxDb: maxDb,
        intervalSeconds: intervalSeconds,
        caution: caution,
        danger: danger,
        colorScheme: Theme.of(context).colorScheme,
        textStyle: Theme.of(context).textTheme.bodySmall ??
            const TextStyle(fontSize: 12),
      ),
      willChange: true,
    );
  }
}

class _BoxPlotPainter extends CustomPainter {
  _BoxPlotPainter({
    required this.buckets,
    required this.minDb,
    required this.maxDb,
    required this.intervalSeconds,
    required this.caution,
    required this.danger,
    required this.colorScheme,
    required this.textStyle,
  });

  final List<SecondBoxStats> buckets;
  final double minDb;
  final double maxDb;
  final double intervalSeconds;
  final double caution;
  final double danger;
  final ColorScheme colorScheme;
  final TextStyle textStyle;

  static const double _leftPadding = 40;
  static const double _rightPadding = 12;
  static const double _topPadding = 12;
  static const double _bottomPadding = 28;

  @override
  void paint(Canvas canvas, Size size) {
    final chartWidth = size.width - _leftPadding - _rightPadding;
    final chartHeight = size.height - _topPadding - _bottomPadding;
    if (chartWidth <= 0 || chartHeight <= 0 || buckets.isEmpty) {
      return;
    }

    final axisPaint = Paint()
      ..color = colorScheme.outline
      ..strokeWidth = 1;

    final verticalAxisStart = Offset(_leftPadding, _topPadding);
    final verticalAxisEnd =
        Offset(_leftPadding, size.height - _bottomPadding);
    canvas.drawLine(verticalAxisStart, verticalAxisEnd, axisPaint);

    final horizontalAxisStart =
        Offset(_leftPadding, size.height - _bottomPadding);
    final horizontalAxisEnd =
        Offset(size.width - _rightPadding, size.height - _bottomPadding);
    canvas.drawLine(horizontalAxisStart, horizontalAxisEnd, axisPaint);

    final xTicks = _buildXTicks(chartWidth);
    _drawGrid(canvas, chartWidth, chartHeight, xTicks);
    _drawThresholdBands(canvas, chartWidth, chartHeight);
    _drawYTicks(canvas, chartHeight);
    _drawBoxPlots(canvas, chartWidth, chartHeight);
    _drawXAxisLabels(canvas, chartHeight, xTicks);
    _drawYAxisLabel(canvas, chartHeight);
  }

  void _drawYTicks(Canvas canvas, double chartHeight) {
    const tickStep = 10;
    for (var value = minDb; value <= maxDb; value += tickStep) {
      final y = _mapValue(value, chartHeight);
      canvas.drawLine(
        Offset(_leftPadding - 4, y),
        Offset(_leftPadding, y),
        Paint()
          ..color = colorScheme.outline
          ..strokeWidth = 1,
      );
      _drawText(
        canvas,
        '${value.round()}',
        Offset(4, y - 7),
        textStyle.copyWith(color: colorScheme.onSurfaceVariant, fontSize: 11),
      );
    }
  }

  void _drawBoxPlots(Canvas canvas, double chartWidth, double chartHeight) {
    final whiskerPaint = Paint()..strokeWidth = 1.2;
    final medianPaint = Paint()..strokeWidth = 2;
    final boxFill = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF90CAF9);
    final boxBorder = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFF0D47A1);

    final latestStart = buckets.last.start;
    final coverageSeconds = intervalSeconds <= 0 ? 1 : intervalSeconds;
    final rangeStart =
        latestStart.subtract(Duration(seconds: coverageSeconds.round()));
    final boxWidth =
        math.min(18.0, (chartWidth / coverageSeconds).clamp(2, 30));

    for (var i = 0; i < buckets.length; i++) {
      final bucket = buckets[i];
      final relSeconds =
          bucket.start.difference(rangeStart).inMilliseconds / 1000.0;
      final ratio =
          relSeconds.clamp(0, coverageSeconds).toDouble() / coverageSeconds;
      final centerX = _leftPadding + ratio * chartWidth;
      final boxColor = bucket.maxDb >= danger
          ? Colors.red
          : bucket.maxDb >= caution
              ? Colors.amber
              : const Color(0xFF0D47A1);

      whiskerPaint.color = boxColor.withValues(alpha: 0.9);
      medianPaint.color = boxColor;
      boxBorder.color = boxColor;
      boxFill.color = boxColor == const Color(0xFF0D47A1)
          ? const Color(0xFF90CAF9)
          : boxColor.withValues(alpha: 0.22);

      final yMin = _mapValue(bucket.minDb, chartHeight);
      final yMax = _mapValue(bucket.maxDb, chartHeight);
      final yQ1 = _mapValue(bucket.q1, chartHeight);
      final yQ3 = _mapValue(bucket.q3, chartHeight);
      final yMedian = _mapValue(bucket.median, chartHeight);

      canvas.drawLine(Offset(centerX, yMax), Offset(centerX, yMin), whiskerPaint);
      canvas.drawLine(
        Offset(centerX - boxWidth * 0.3, yMax),
        Offset(centerX + boxWidth * 0.3, yMax),
        whiskerPaint,
      );
      canvas.drawLine(
        Offset(centerX - boxWidth * 0.3, yMin),
        Offset(centerX + boxWidth * 0.3, yMin),
        whiskerPaint,
      );

      final rect = Rect.fromLTRB(
        centerX - boxWidth / 2,
        yQ3,
        centerX + boxWidth / 2,
        yQ1,
      );
      canvas.drawRect(rect, boxFill);
      canvas.drawRect(rect, boxBorder);

      canvas.drawLine(
        Offset(centerX - boxWidth / 2, yMedian),
        Offset(centerX + boxWidth / 2, yMedian),
        medianPaint,
      );
    }
  }

  double _mapValue(double value, double chartHeight) {
    final clamped = value.clamp(minDb, maxDb);
    final ratio = (clamped - minDb) / (maxDb - minDb);
    return _topPadding + chartHeight * (1 - ratio);
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(minWidth: 0, maxWidth: 40);
    painter.paint(canvas, offset);
  }

  void _drawGrid(
    Canvas canvas,
    double chartWidth,
    double chartHeight,
    List<_AxisTick> xTicks,
  ) {
    final horizontalPaint = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.5)
      ..strokeWidth = 0.8;
    final verticalPaint = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.5)
      ..strokeWidth = 0.8;

    const divisions = 5;
    for (var i = 1; i < divisions; i++) {
      final y = _topPadding + chartHeight * (i / divisions);
      canvas.drawLine(
        Offset(_leftPadding, y),
        Offset(_leftPadding + chartWidth, y),
        horizontalPaint,
      );
    }

    for (final tick in xTicks) {
      canvas.drawLine(
        Offset(tick.position, _topPadding),
        Offset(tick.position, _topPadding + chartHeight),
        verticalPaint,
      );
    }
  }

  void _drawThresholdBands(
    Canvas canvas,
    double chartWidth,
    double chartHeight,
  ) {
    final safeCaution = caution.clamp(minDb, maxDb);
    final safeDanger = danger.clamp(minDb, maxDb);
    final cautionY = _mapValue(safeCaution, chartHeight);
    final dangerY = _mapValue(safeDanger, chartHeight);
    final cautionPaint = Paint()
      ..color = Colors.yellow.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    final dangerPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromLTRB(
        _leftPadding,
        _topPadding,
        _leftPadding + chartWidth,
        dangerY,
      ),
      dangerPaint,
    );
    canvas.drawRect(
      Rect.fromLTRB(
        _leftPadding,
        dangerY,
        _leftPadding + chartWidth,
        cautionY,
      ),
      cautionPaint,
    );
  }

  void _drawXAxisLabels(
    Canvas canvas,
    double chartHeight,
    List<_AxisTick> ticks,
  ) {
    final style = textStyle.copyWith(
      color: colorScheme.onSurfaceVariant,
      fontSize: 11,
    );
    for (final tick in ticks) {
      _drawText(
        canvas,
        tick.label,
        Offset(tick.position - 20, _topPadding + chartHeight + 6),
        style,
      );
    }
  }

  void _drawYAxisLabel(Canvas canvas, double chartHeight) {
    final painter = TextPainter(
      text: TextSpan(
        text: 'dB',
        style: textStyle.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.save();
    canvas.translate(6, _topPadding + chartHeight / 2);
    canvas.rotate(-math.pi / 2);
    painter.paint(
      canvas,
      Offset(-painter.width / 2, -painter.height / 2),
    );
    canvas.restore();
  }

  List<_AxisTick> _buildXTicks(double chartWidth) {
    if (buckets.isEmpty) return const [];
    const tickCount = 6;
    final totalSeconds = intervalSeconds <= 0 ? 1.0 : intervalSeconds;
    final ticks = <_AxisTick>[];
    for (var i = 0; i < tickCount; i++) {
      final ratio = tickCount == 1 ? 0.0 : i / (tickCount - 1);
      final secondsFromStart = ratio * totalSeconds;
      final secondsToNow = (totalSeconds - secondsFromStart).round();
      final label =
          secondsToNow <= 0 ? '0s' : '-${_formatSeconds(secondsToNow)}';
      final position = _leftPadding + ratio * chartWidth;
      ticks.add(_AxisTick(position: position, label: label));
    }
    return ticks;
  }

  String _formatSeconds(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final remSeconds = seconds % 60;
    if (minutes < 60) {
      return '${minutes}m ${remSeconds.toString().padLeft(2, '0')}s';
    }
    final hours = minutes ~/ 60;
    final remMinutes = minutes % 60;
    return '${hours}h ${remMinutes.toString().padLeft(2, '0')}m';
  }

  @override
  bool shouldRepaint(covariant _BoxPlotPainter oldDelegate) {
    return oldDelegate.buckets != buckets ||
        oldDelegate.minDb != minDb ||
        oldDelegate.maxDb != maxDb ||
        oldDelegate.colorScheme != colorScheme;
  }
}

class _AxisTick {
  const _AxisTick({required this.position, required this.label});

  final double position;
  final String label;
}


Future<void> _exportHistogram(BuildContext context) async {
  final controller = context.read<MonitorController>();
  final buckets = controller.histogramBuckets;
  if (buckets.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No histogram data to export yet.')),
    );
    return;
  }

  final buffer = StringBuffer('bin_lower_db,bin_upper_db,seconds\n');
  for (final bucket in buckets) {
    buffer.writeln(
      '${bucket.lowerBound.toStringAsFixed(0)},'
      '${bucket.upperBound.toStringAsFixed(0)},'
      '${bucket.seconds.toStringAsFixed(2)}',
    );
  }

  try {
    final dir = await getTemporaryDirectory();
    final filename =
        'histogram_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File('${dir.path}/$filename');
    await file.writeAsString(buffer.toString());
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(
            file.path,
            mimeType: 'text/csv',
            name: 'histogram.csv',
          ),
        ],
        text: 'Sound level histogram export',
      ),
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $error')),
      );
    }
  }
}

class _HistogramToggle extends StatelessWidget {
  const _HistogramToggle({
    required this.bucket,
    required this.isVisible,
    required this.onChanged,
  });

  final HistogramBucket bucket;
  final bool isVisible;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondaryColor =
        theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        color: theme.colorScheme.surfaceContainerLowest,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${bucket.lowerBound.toInt()}-${bucket.upperBound.toInt()} dB',
                  style: theme.textTheme.labelLarge,
                ),
                Text(
                  _formatExposure(bucket.seconds),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondaryColor,
                  ),
            ),
        ],
      ),
          ),
          Switch.adaptive(
            value: isVisible,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

String _formatExposure(double seconds) {
  final doubleSeconds = seconds;
  if (doubleSeconds < 60) {
    final value = doubleSeconds < 10 ? doubleSeconds.toStringAsFixed(1) : doubleSeconds.toStringAsFixed(0);
    return '$value s';
  }
  final minutes = doubleSeconds / 60;
  if (minutes < 60) {
    final value = minutes < 10 ? minutes.toStringAsFixed(1) : minutes.toStringAsFixed(0);
    return '$value min';
  }
  final hours = minutes / 60;
  if (hours < 24) {
    final value = hours < 10 ? hours.toStringAsFixed(1) : hours.toStringAsFixed(0);
    return '$value h';
  }
  final days = hours / 24;
  final value = days < 10 ? days.toStringAsFixed(1) : days.toStringAsFixed(0);
  return '$value d';
}
class _ControlsWrap extends StatelessWidget {
  const _ControlsWrap({
    required this.isRecording,
    required this.onStart,
    required this.onPause,
    required this.onOptions,
    required this.onAbout,
    required this.mode,
    required this.onModeChanged,
  });

  final bool isRecording;
  final Future<void> Function()? onStart;
  final Future<void> Function()? onPause;
  final VoidCallback onOptions;
  final VoidCallback onAbout;
  final InsightMode mode;
  final ValueChanged<InsightMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final standardStyle = ButtonStyle(
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          ),
          minimumSize: WidgetStateProperty.all(const Size(110, 40)),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );

        Widget compactOutlined(
          String label,
          IconData icon,
          VoidCallback onPressed,
        ) {
          return SizedBox(
            width: 130,
            child: OutlinedButton.icon(
              style: standardStyle,
              onPressed: onPressed,
              icon: Icon(icon, size: 18),
              label: Text(label),
            ),
          );
        }

        final buttonsRow = Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            _RecordPauseButtons(
              isRecording: isRecording,
              onStart: onStart,
              onPause: onPause,
            ),
            const SizedBox(width: 12),
            compactOutlined('Options', Icons.settings_suggest, onOptions),
            const SizedBox(width: 12),
            compactOutlined('About', Icons.info_outline, onAbout),
          ],
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: constraints.maxWidth,
                ),
                child: buttonsRow,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<InsightMode>(
            segments: const [
              ButtonSegment(value: InsightMode.chart, label: Text('Chart')),
                  ButtonSegment(
                    value: InsightMode.hist,
                    label: Text('Histogram'),
                  ),
              ButtonSegment(value: InsightMode.stats, label: Text('Stats')),
            ],
            showSelectedIcon: false,
            selected: {mode},
            onSelectionChanged: (value) => onModeChanged(value.first),
          ),
            ),
          ],
        );
      },
    );
  }
}

class _RecordPauseButtons extends StatelessWidget {
  const _RecordPauseButtons({
    required this.isRecording,
    required this.onStart,
    required this.onPause,
  });

  final bool isRecording;
  final Future<void> Function()? onStart;
  final Future<void> Function()? onPause;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = colorScheme.outline;
    final recordColor =
        isRecording ? Colors.redAccent : colorScheme.outlineVariant;
    final pauseColor =
        isRecording ? colorScheme.outlineVariant : const Color(0xFF0D47A1);
    final iconStyle = IconButton.styleFrom(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: const Size(40, 40),
    );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Record',
            style: iconStyle,
            onPressed: () {
              if (isRecording) return;
              onStart?.call();
            },
            icon: Icon(
              Icons.fiber_manual_record,
              color: recordColor,
            ),
          ),
          SizedBox(
            height: 28,
            child: VerticalDivider(
              color: borderColor,
              thickness: 1,
              width: 1,
            ),
          ),
          IconButton(
            tooltip: 'Pause',
            style: iconStyle,
            onPressed: () {
              if (!isRecording) return;
              onPause?.call();
            },
            icon: Icon(
              Icons.pause,
              color: pauseColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _IntervalsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MonitorController>();
    final entries = controller.history;
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Recorded intervals',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: entries.isEmpty
                  ? const Center(
                      child: Text('No samples yet. Tap Record to begin tracking.'),
                    )
                  : Scrollbar(
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowColor: WidgetStatePropertyAll(
                              theme.colorScheme.surfaceContainerHighest,
                            ),
                            columns: const [
                              DataColumn(label: Text('Time')),
                              DataColumn(label: Text('Min dB')),
                              DataColumn(label: Text('Mean dB')),
                              DataColumn(label: Text('Max dB')),
                            ],
                            rows: entries
                                .map(
                                  (snapshot) => DataRow(
                                    cells: [
                                      DataCell(Text(
                                        _formatTime(snapshot.timestamp),
                                      )),
                                      DataCell(
                                        Text(snapshot.minDb.toStringAsFixed(1)),
                                      ),
                                      DataCell(
                                        Text(snapshot.meanDb.toStringAsFixed(1)),
                                      ),
                                      DataCell(
                                        Text(snapshot.maxDb.toStringAsFixed(1)),
                                      ),
                                    ],
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
              onPressed: () => _exportHistory(context),
              icon: const Icon(Icons.ios_share),
              label: const Text('Export history'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        entries.isEmpty ? null : () => controller.clearHistory(),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Clear'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IntervalSlider extends StatelessWidget {
  const _IntervalSlider({
    required this.minutes,
    required this.onChanged,
  });

  final double minutes;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Recording interval: ${minutes.toStringAsFixed(2)} min',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            Slider(
              value: minutes.clamp(0.25, 5).toDouble(),
              min: 0.25,
              max: 5,
              divisions: 19,
              label: '${minutes.toStringAsFixed(2)} min',
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertLevelsCard extends StatelessWidget {
  const _AlertLevelsCard({required this.controller});

  final MonitorController controller;

  @override
  Widget build(BuildContext context) {
    final caution = controller.cautionThreshold;
    final danger = controller.dangerThreshold;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Alert levels',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Reference table',
                  onPressed: () => _showLevelsInfo(context),
                  icon: const Icon(Icons.info_outline),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ThresholdSlider(
              label: 'Yellow warning',
              value: caution,
              min: 40,
              max: 90,
              onChanged: (value) => controller.updateThresholds(caution: value),
            ),
            const SizedBox(height: 12),
            _ThresholdSlider(
              label: 'Red danger',
              value: danger,
              min: (caution + 1).clamp(45, 110),
              max: 110,
              onChanged: (value) => controller.updateThresholds(danger: value),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatTime(DateTime time) {
  return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

Future<void> _exportHistory(BuildContext context) async {
  final controller = context.read<MonitorController>();
  final entries = controller.history;
  final messenger = ScaffoldMessenger.of(context);

  if (entries.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Record some intervals before exporting.')),
    );
    return;
  }

  final buffer = StringBuffer('timestamp,min_db,mean_db,max_db\n');
  for (final snapshot in entries.reversed) {
    buffer.writeln(
      '${snapshot.timestamp.toIso8601String()},'
      '${snapshot.minDb.toStringAsFixed(1)},'
      '${snapshot.meanDb.toStringAsFixed(1)},'
      '${snapshot.maxDb.toStringAsFixed(1)}',
    );
  }

  try {
    final dir = await getTemporaryDirectory();
    final filename =
        'sound_history_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File('${dir.path}/$filename');
    await file.writeAsString(buffer.toString());

    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(file.path, mimeType: 'text/csv', name: 'sound_history.csv'),
        ],
        text: 'Sound level history export',
      ),
    );
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text('Export failed: $error')),
    );
  }
}

Future<void> _showAboutDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('About'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sound Level Monitor estimates ambient noise using your device microphone.',
            ),
            const SizedBox(height: 12),
            _LinkText(
              label:
                  'This app was crafted in the author\'s free time. If you find it useful, please consider tipping to support further development.',
              url: 'https://buymeacoffee.com/fejikso',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

Future<void> _showLevelsInfo(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Exposure guidance'),
        content: SingleChildScrollView(
          child: _GuidanceTable(),
        ),
        actions: [
          TextButton(
                        onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

class _ThresholdSlider extends StatelessWidget {
  const _ThresholdSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label: ${value.toStringAsFixed(0)} dB'),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: (max - min).round(),
              label: '${value.toStringAsFixed(0)} dB',
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _GuidanceTable extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const rows = [
      [
        'Whisper (20–30 dB)',
        'Faint / quiet',
      ],
      [
        'Quiet library (≈40 dB)',
        'Soft • Comfortable background level.',
      ],
      [
        'Conversation (55–65 dB)',
        'Moderate • Safe for unlimited exposure.',
      ],
      [
        'Noisy office (65–75 dB)',
        'Loud • Limit long-term exposure beyond ~70 dB.',
      ],
      [
        'Busy street (70–85 dB)',
        'Very loud • 85 dB is potential long-term damage threshold.',
      ],
      [
        'Shouting (85–95 dB)',
        'Dangerous with sustained exposure; voice must be raised to be heard.',
      ],
      [
        'Shouting in ear (~110 dB)',
        'Extremely dangerous • Damage possible within minutes.',
      ],
      [
        'Human scream (80–125 dB)',
        'Painful and dangerous • Highest levels cause immediate harm.',
      ],
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reference levels',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(1.2),
                1: FlexColumnWidth(1.8),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.top,
              children: rows
                  .map(
                    (row) => TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            row[0],
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(row[1]),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    super.key,
    required this.title,
    required this.stats,
    required this.progress,
    required this.isRecording,
  });

  final String title;
  final IntervalStats stats;
  final double progress;
  final bool isRecording;

  @override
  Widget build(BuildContext context) {
    final effectiveProgress =
        isRecording ? progress.clamp(0, 1).toDouble() : 0.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: effectiveProgress,
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 12),
            _StatRow(stats: stats),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.stats});

  final IntervalStats stats;

  @override
  Widget build(BuildContext context) {
    final labels = ['Min', 'Mean', 'Max'];
    final values = [
      stats.minDb.toStringAsFixed(1),
      stats.meanDb.toStringAsFixed(1),
      stats.maxDb.toStringAsFixed(1),
    ];
    return Row(
      children: List.generate(labels.length, (index) {
        return Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                labels[index],
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text('${values[index]} dB'),
            ],
          ),
        );
      }),
    );
  }
}

class _LinkText extends StatelessWidget {
  const _LinkText({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SelectableText.rich(
        TextSpan(
          text: label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => _launchLink(url, context),
        ),
      ),
    );
  }
}

Future<void> _launchLink(String url, BuildContext context) async {
  final launched = await launchUrlString(url);
  if (!launched && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Unable to open $url')),
    );
  }
}

String _panelMessage(ThresholdBand band) {
  const descriptions = {
    'Calm': 'Comfortable background level.',
    'Caution': 'Elevated noise. Limit how long it stays this loud.',
    'Danger': 'Very loud. Hearing protection recommended.',
    'Hazard': 'Extremely loud. Risk of immediate hearing damage.',
  };
  final description = descriptions[band.label] ?? band.label;
  if (band.label == 'Calm') {
    return description;
  }
  return 'Caution: $description';
}

void _openOptions(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const OptionsScreen(),
    ),
  );
}

class OptionsScreen extends StatelessWidget {
  const OptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Options'),
      ),
      body: Consumer<MonitorController>(
        builder: (context, controller, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _IntervalSlider(
                minutes: controller.intervalMinutes,
                onChanged: controller.setIntervalMinutes,
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              Text(
                'Alert hysteresis: ${controller.thresholdCrossingSeconds.toStringAsFixed(2)} s',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Slider(
                value: controller.thresholdCrossingSeconds,
                min: 0.1,
                max: 1.0,
                divisions: 9,
                label: '${controller.thresholdCrossingSeconds.toStringAsFixed(2)} s',
                onChanged: (value) =>
                    controller.setThresholdCrossingSeconds(value),
              ),
              const SizedBox(height: 16),
                      Text(
                        'Color palette',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<PaletteMode>(
                        segments: const [
                          ButtonSegment(
                            value: PaletteMode.normal,
                            label: Text('Normal'),
                          ),
                          ButtonSegment(
                            value: PaletteMode.highContrast,
                            label: Text('High contrast'),
                          ),
                        ],
                        showSelectedIcon: false,
                        selected: {controller.paletteMode},
                        onSelectionChanged: (value) =>
                            controller.setPaletteMode(value.first),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _AlertLevelsCard(controller: controller),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Keep screen awake'),
                subtitle: const Text(
                  'Prevent the display from sleeping while monitoring.',
                ),
                value: controller.keepScreenAwake,
                onChanged: controller.setKeepScreenAwake,
              ),
            ],
          );
        },
      ),
    );
  }
}

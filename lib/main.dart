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

enum InsightMode { chart, stats }

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
          onLevels: () => _showLevelsSheet(context),
          onOptions: () => _openOptions(context),
          onAbout: () => _showAboutDialog(context),
          mode: _mode,
          onModeChanged: (value) => setState(() => _mode = value),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _mode == InsightMode.chart
              ? const _LevelChart(key: ValueKey('chart'))
              : widget.stats == null
                  ? const Card(
                      key: ValueKey('stats-empty'),
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No interval stats yet. Start recording to see values.',
                        ),
                      ),
                    )
                  : _StatsCard(
                      key: const ValueKey('stats'),
                      title: 'Current interval so far',
                      stats: widget.stats!,
                    ),
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
    final samples = controller.intervalSamples;
    final windowSeconds =
        controller.interval.inMilliseconds / Duration.millisecondsPerSecond;
    final now = DateTime.now();

    final minY = 30.0;
    final maxY = 90.0;
    final xInterval = windowSeconds <= 0 ? 1.0 : windowSeconds / 4;
    final maxLineValue =
        samples.isEmpty ? null : samples.map((s) => s.maxDb).reduce(math.max);
    final meanLineValue = samples.isEmpty
        ? null
        : samples.map((s) => s.meanDb).reduce((a, b) => a + b) / samples.length;

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
            if (samples.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text('No data yet. Start a recording to populate the chart.'),
                ),
              )
            else
              SizedBox(
                height: 220,
                child: LineChart(
                  _buildChartData(
                    context,
                    controller,
                    _buildSpots(samples, (p) => p.meanDb, now, windowSeconds),
                    minY,
                    maxY,
                    windowSeconds,
                    xInterval,
                    maxLineValue,
                    meanLineValue,
                  ),
                ),
              ),
            if (samples.isNotEmpty) ...[
              const SizedBox(height: 12),
            const SizedBox(height: 4),
            ],
          ],
        ),
      ),
    );
  }

  LineChartData _buildChartData(
    BuildContext context,
    MonitorController controller,
    List<FlSpot> meanSpots,
    double minY,
    double maxY,
    double windowSeconds,
    double xInterval,
    double? maxLineValue,
    double? meanLineValue,
  ) {
    Color colorFor(String label) =>
        controller.thresholds.firstWhere((band) => band.label == label).color;
    final calmColor = colorFor('Calm').withValues(alpha: 0.06);
    final cautionColor = colorFor('Caution').withValues(alpha: 0.12);
    final dangerColor = colorFor('Danger').withValues(alpha: 0.12);
    final caution = controller.cautionThreshold.toDouble();
    final danger = controller.dangerThreshold.toDouble();

    return LineChartData(
      minX: 0,
      maxX: windowSeconds,
      minY: minY,
      maxY: maxY,
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) =>
              Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: 5,
        verticalInterval: xInterval,
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: xInterval,
            getTitlesWidget: (value, meta) => Text('${value.round()}s'),
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (value, meta) => Text('${value.round()}'),
          ),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      rangeAnnotations: RangeAnnotations(
        horizontalRangeAnnotations: [
          HorizontalRangeAnnotation(
            y1: minY,
            y2: caution,
            color: calmColor,
          ),
          HorizontalRangeAnnotation(
            y1: caution,
            y2: danger,
            color: cautionColor,
          ),
          HorizontalRangeAnnotation(
            y1: danger,
            y2: maxY,
            color: dangerColor,
          ),
        ],
      ),
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          if (maxLineValue != null)
            HorizontalLine(
              y: maxLineValue,
              color: Colors.red,
              strokeWidth: 1,
              dashArray: const [6, 3],
            ),
          if (meanLineValue != null)
            HorizontalLine(
              y: meanLineValue,
              color: Colors.black,
              strokeWidth: 1,
              dashArray: const [4, 4],
            ),
        ],
      ),
      lineBarsData: [
        _buildLine(meanSpots, Colors.blueAccent),
      ],
    );
  }

  List<FlSpot> _buildSpots(
    List<SamplePoint> samples,
    double Function(SamplePoint) selector,
    DateTime now,
    double windowSeconds,
  ) {
    return samples.map((sample) {
      final ageSeconds =
          now.difference(sample.timestamp).inMilliseconds / 1000.0;
      final x = (windowSeconds - ageSeconds).clamp(0, windowSeconds).toDouble();
      return FlSpot(x, selector(sample));
    }).toList();
  }

  LineChartBarData _buildLine(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: false,
      color: color,
      barWidth: 2,
      dotData: const FlDotData(show: false),
    );
  }
}

class _ControlsWrap extends StatelessWidget {
  const _ControlsWrap({
    required this.isRecording,
    required this.onStart,
    required this.onPause,
    required this.onLevels,
    required this.onOptions,
    required this.onAbout,
    required this.mode,
    required this.onModeChanged,
  });

  final bool isRecording;
  final Future<void> Function()? onStart;
  final Future<void> Function()? onPause;
  final VoidCallback onLevels;
  final VoidCallback onOptions;
  final VoidCallback onAbout;
  final InsightMode mode;
  final ValueChanged<InsightMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = (constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width) -
            4; // account for padding jitter
        const spacing = 12.0;
        final columns = availableWidth > 640 ? 3 : 2;
        final rawWidth =
            (availableWidth - spacing * (columns - 1)) / columns;
        final itemWidth = rawWidth.clamp(150.0, 220.0);

        final buttonStyle = ButtonStyle(
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          ),
          minimumSize: WidgetStateProperty.all(Size(itemWidth, 40)),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );

        final buttons = [
          ElevatedButton.icon(
            style: buttonStyle,
            onPressed: isRecording ? null : onStart,
            icon: const Icon(Icons.fiber_manual_record),
            label: const Text('Record'),
          ),
          FilledButton.icon(
            style: buttonStyle,
            onPressed: isRecording ? onPause : null,
            icon: const Icon(Icons.pause_circle),
            label: const Text('Pause'),
          ),
          OutlinedButton.icon(
            style: buttonStyle,
            onPressed: onLevels,
            icon: const Icon(Icons.tune),
            label: const Text('Levels'),
          ),
          OutlinedButton.icon(
            style: buttonStyle,
            onPressed: onOptions,
            icon: const Icon(Icons.settings_suggest),
            label: const Text('Options'),
          ),
          OutlinedButton.icon(
            style: buttonStyle,
            onPressed: onAbout,
            icon: const Icon(Icons.info_outline),
            label: const Text('About'),
          ),
          SegmentedButton<InsightMode>(
            segments: const [
              ButtonSegment(value: InsightMode.chart, label: Text('Chart')),
              ButtonSegment(value: InsightMode.stats, label: Text('Stats')),
            ],
            showSelectedIcon: false,
            selected: {mode},
            onSelectionChanged: (value) => onModeChanged(value.first),
          ),
        ];

        return Wrap(
          spacing: spacing,
          runSpacing: 8,
          children: buttons
              .map(
                (button) => SizedBox(
                  width: itemWidth,
                  child: button,
                ),
              )
              .toList(),
        );
      },
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
            FilledButton.icon(
              onPressed: () => _exportHistory(context),
              icon: const Icon(Icons.ios_share),
              label: const Text('Export history'),
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

void _showLevelsSheet(BuildContext context) {
  final controller = context.read<MonitorController>();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      double caution = controller.cautionThreshold;
      double danger = controller.dangerThreshold;
      return StatefulBuilder(
        builder: (context, setState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 24,
              bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Configure alert levels',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ThresholdSlider(
                    label: 'Yellow warning',
                    value: caution,
                    min: 40,
                    max: 90,
                    onChanged: (value) {
                      setState(() {
                        caution = value;
                        if (danger <= caution) {
                          danger = (caution + 1).clamp(45, 110);
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  _ThresholdSlider(
                    label: 'Red danger',
                    value: danger,
                    min: caution + 1,
                    max: 110,
                    onChanged: (value) {
                      setState(() {
                        danger = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  _GuidanceTable(),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      controller.updateThresholds(
                        caution: caution,
                        danger: danger,
                      );
                      Navigator.of(context).pop();
                    },
                    child: const Text('Save levels'),
                  ),
                ],
              ),
            ),
          );
        },
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
        'Faint / quiet • Comfortable for long exposure.',
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
  const _StatsCard({super.key, required this.title, required this.stats});

  final String title;
  final IntervalStats stats;

  @override
  Widget build(BuildContext context) {
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

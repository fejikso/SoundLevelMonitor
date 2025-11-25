import 'dart:io';

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
    final meanValue = stats?.meanDb ?? controller.currentDb;
    final flashKey = controller.flashCounter;

    return Column(
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
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          meanValue != null ? meanValue.toStringAsFixed(1) : '--',
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
          child: _IntervalSlider(
            minutes: controller.intervalMinutes,
            onChanged: controller.setIntervalMinutes,
          ),
        ),
        const SizedBox(height: 8),
        if (stats != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _StatsCard(
              title: 'Current interval so far',
              stats: stats,
            ),
          ),
        if (stats != null) const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ElevatedButton.icon(
                onPressed: controller.isRecording ? null : controller.startMonitoring,
                icon: const Icon(Icons.fiber_manual_record),
                label: const Text('Record'),
              ),
              FilledButton.icon(
                onPressed: controller.isRecording ? controller.pauseMonitoring : null,
                icon: const Icon(Icons.pause_circle),
                label: const Text('Pause'),
              ),
              OutlinedButton.icon(
                onPressed: () => _exportHistory(context),
                icon: const Icon(Icons.ios_share),
                label: const Text('Export'),
              ),
              OutlinedButton.icon(
                onPressed: () => _showLevelsSheet(context),
                icon: const Icon(Icons.tune),
                label: const Text('Levels'),
              ),
              OutlinedButton.icon(
                onPressed: () => _openOptions(context),
                icon: const Icon(Icons.settings_suggest),
                label: const Text('Options'),
              ),
              OutlinedButton.icon(
                onPressed: () => _showAboutDialog(context),
                icon: const Icon(Icons.info_outline),
                label: const Text('About'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Recorded intervals',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: controller.history.isEmpty
              ? const _EmptyHistory()
              : ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemBuilder: (context, index) {
                    final sample = controller.history[index];
                    return _SnapshotTile(snapshot: sample);
                  },
                  separatorBuilder: (context, _) => const SizedBox(height: 8),
                  itemCount: controller.history.length,
                ),
        ),
      ],
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

class _SnapshotTile extends StatelessWidget {
  const _SnapshotTile({required this.snapshot});

  final IntervalSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        title: Text(
          _formatTime(snapshot.timestamp),
          style: theme.textTheme.titleSmall,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _StatRow(
            stats: IntervalStats(
              minDb: snapshot.minDb,
              meanDb: snapshot.meanDb,
              maxDb: snapshot.maxDb,
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('No samples yet. Tap Record to begin tracking.'),
    );
  }
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
              label: 'GitHub repository',
              url: 'https://github.com/fejikso/SoundLevelMonitor',
            ),
            _LinkText(
              label: 'Support the author',
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
  const _StatsCard({required this.title, required this.stats});

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
            children: [
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

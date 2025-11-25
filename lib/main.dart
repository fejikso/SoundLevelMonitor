import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

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
    final dbValue = controller.currentDb;
    final threshold = controller.activeBand;

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
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: threshold.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: threshold.color, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.isRecording ? 'Live level' : 'Waiting for recording',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      dbValue != null ? dbValue.toStringAsFixed(1) : '--',
                      style: Theme.of(context)
                          .textTheme
                          .displayMedium
                          ?.copyWith(color: threshold.color, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'dB',
                      style: TextStyle(fontSize: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${threshold.label} • Sound level reached ${threshold.limitDb.isFinite ? threshold.limitDb.toStringAsFixed(0) : (dbValue?.toStringAsFixed(0) ?? '--')} dB',
                  style: TextStyle(color: threshold.color.darken()),
                ),
              ],
            ),
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
        subtitle: Text(
          'Min ${snapshot.minDb.toStringAsFixed(1)} dB • Mean ${snapshot.meanDb.toStringAsFixed(1)} dB • Max ${snapshot.maxDb.toStringAsFixed(1)} dB',
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

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv', name: 'sound_history.csv')],
      text: 'Sound level history export',
    );
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text('Export failed: $error')),
    );
  }
}

void _showAboutDialog(BuildContext context) {
  showAboutDialog(
    context: context,
    applicationIcon: const Icon(Icons.graphic_eq),
    applicationName: 'Sound Level Monitor',
    applicationVersion: '1.0.0',
    children: const [
      Text('This MVP uses your device microphone to estimate noise levels.'),
      SizedBox(height: 8),
      Text('Tap Record to begin measuring, Pause to stop, and Export to share results.'),
    ],
  );
}

extension ColorShade on Color {
  Color darken([double amount = .2]) {
    final hsl = HSLColor.fromColor(this);
    final lightness = (hsl.lightness - amount).clamp(0.0, 1.0);
    return hsl.withLightness(lightness).toColor();
  }
}

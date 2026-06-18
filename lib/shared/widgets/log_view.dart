import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/logging/logging_providers.dart';

/// A scrollable, auto-updating view of recent [AppLogger] entries (newest at
/// the bottom). Used on the dashboard and diagnostic screens.
class LogView extends ConsumerStatefulWidget {
  const LogView({super.key, this.maxEntries = 200, this.height});

  final int maxEntries;
  final double? height;

  @override
  ConsumerState<LogView> createState() => _LogViewState();
}

class _LogViewState extends ConsumerState<LogView> {
  StreamSubscription<LogEntry>? _sub;

  @override
  void initState() {
    super.initState();
    // Rebuild whenever a new log entry arrives.
    final logger = ref.read(appLoggerProvider);
    _sub = logger.stream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Color _color(BuildContext context, LogLevel level) {
    final scheme = Theme.of(context).colorScheme;
    switch (level) {
      case LogLevel.debug:
        return scheme.onSurfaceVariant;
      case LogLevel.info:
        return scheme.onSurface;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return scheme.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final logger = ref.read(appLoggerProvider);
    final entries = logger.entries;
    final shown = entries.length > widget.maxEntries
        ? entries.sublist(entries.length - widget.maxEntries)
        : entries;

    final list = shown.isEmpty
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No log entries yet.'),
            ),
          )
        : ListView.builder(
            reverse: true,
            padding: const EdgeInsets.all(8),
            itemCount: shown.length,
            itemBuilder: (context, index) {
              final entry = shown[shown.length - 1 - index];
              return Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${entry.timeLabel} ',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    TextSpan(
                      text: '[${entry.tag}] ',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: entry.message),
                  ],
                ),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: _color(context, entry.level),
                ),
              );
            },
          );

    final bordered = DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: list,
    );

    return widget.height != null
        ? SizedBox(height: widget.height, child: bordered)
        : bordered;
  }
}

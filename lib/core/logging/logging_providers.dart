import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/settings_providers.dart';
import 'app_logger.dart';

/// App-wide logger. Its debug flag follows the Settings "Debug logging" toggle.
final appLoggerProvider = Provider<AppLogger>((ref) {
  final logger = AppLogger();
  logger.debugEnabled = ref.read(settingsProvider).debugLogging;
  ref.listen<dynamic>(settingsProvider, (previous, next) {
    logger.debugEnabled = next.debugLogging;
  });
  ref.onDispose(logger.dispose);
  return logger;
});

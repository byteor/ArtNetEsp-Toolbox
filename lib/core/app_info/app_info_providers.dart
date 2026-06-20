import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The running app's version as `<version>+<build>` (e.g. `1.0.1+2`), mirroring
/// pubspec's `version:`. Sourced from the platform package metadata (Android
/// versionName/versionCode, iOS CFBundleShortVersionString/CFBundleVersion), so
/// it reflects the actually-installed build rather than a hard-coded constant.
///
/// Override in tests/widget tests to avoid the platform channel.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version}+${info.buildNumber}';
});

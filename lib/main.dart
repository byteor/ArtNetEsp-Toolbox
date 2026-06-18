import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/settings/app_settings.dart';
import 'core/settings/settings_providers.dart';
import 'core/settings/shared_prefs_settings_repository.dart';
import 'features/device_config/data/device_credentials_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load persisted settings before the app starts so the rest of the tree can
  // read them synchronously (see settings_providers.dart).
  final prefs = await SharedPreferences.getInstance();
  final repository = SharedPrefsSettingsRepository(prefs);
  final AppSettings settings = await repository.load();

  // Decode the encrypted device credentials once, for synchronous reads.
  final secureStorage = buildSecureStorage();
  final credentials = await loadCredentialSnapshot(secureStorage);

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialSettingsProvider.overrideWithValue(settings),
        secureStorageProvider.overrideWithValue(secureStorage),
        initialCredentialSnapshotProvider.overrideWithValue(credentials),
      ],
      child: const ArtNetApp(),
    ),
  );
}

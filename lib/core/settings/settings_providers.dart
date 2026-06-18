import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';
import 'settings_repository.dart';
import 'shared_prefs_settings_repository.dart';

/// Provides the SharedPreferences instance. Overridden in `main()` after it has
/// been initialised, so the rest of the app can read settings synchronously.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main()',
  ),
);

/// The settings loaded once at startup. Overridden in `main()`.
final initialSettingsProvider = Provider<AppSettings>(
  (ref) => throw UnimplementedError(
    'initialSettingsProvider must be overridden in main()',
  ),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SharedPrefsSettingsRepository(ref.watch(sharedPreferencesProvider)),
);

/// Holds the current [AppSettings] and persists changes.
class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(initialSettingsProvider);

  Future<void> update(AppSettings settings) async {
    state = settings;
    await ref.read(settingsRepositoryProvider).save(settings);
  }

  Future<void> setArtNetPort(int port) =>
      update(state.copyWith(artNetPort: port));

  Future<void> setBroadcastAddress(String address) =>
      update(state.copyWith(broadcastAddress: address));

  Future<void> setPreferComputedBroadcast(bool value) =>
      update(state.copyWith(preferComputedBroadcast: value));

  Future<void> setMdnsServiceTypes(List<String> types) =>
      update(state.copyWith(mdnsServiceTypes: types));

  Future<void> setDebugLogging(bool value) =>
      update(state.copyWith(debugLogging: value));

  Future<void> setListenTimeoutMs(int ms) =>
      update(state.copyWith(listenTimeoutMs: ms));

  Future<void> setPacketDisplayLimit(int limit) =>
      update(state.copyWith(packetDisplayLimit: limit));
}

final settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

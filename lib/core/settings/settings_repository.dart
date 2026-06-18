import 'app_settings.dart';

/// Persistence boundary for [AppSettings]. Implemented by
/// [SharedPrefsSettingsRepository]; swap in another impl (file, secure storage)
/// without touching the rest of the app.
abstract interface class SettingsRepository {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

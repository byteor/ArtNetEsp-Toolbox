import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';
import 'settings_repository.dart';

/// [SettingsRepository] backed by `shared_preferences`.
class SharedPrefsSettingsRepository implements SettingsRepository {
  SharedPrefsSettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const String _kPort = 'artnet_port';
  static const String _kBroadcast = 'broadcast_address';
  static const String _kPreferComputed = 'prefer_computed_broadcast';
  static const String _kMdns = 'mdns_service_types';
  static const String _kDebug = 'debug_logging';
  static const String _kTimeout = 'listen_timeout_ms';
  static const String _kPacketLimit = 'packet_display_limit';

  @override
  Future<AppSettings> load() async {
    const d = AppSettings.defaults;
    final mdns = _prefs.getStringList(_kMdns);
    return AppSettings(
      artNetPort: _prefs.getInt(_kPort) ?? d.artNetPort,
      broadcastAddress: _prefs.getString(_kBroadcast) ?? d.broadcastAddress,
      preferComputedBroadcast:
          _prefs.getBool(_kPreferComputed) ?? d.preferComputedBroadcast,
      mdnsServiceTypes:
          (mdns == null || mdns.isEmpty) ? d.mdnsServiceTypes : mdns,
      debugLogging: _prefs.getBool(_kDebug) ?? d.debugLogging,
      listenTimeoutMs: _prefs.getInt(_kTimeout) ?? d.listenTimeoutMs,
      packetDisplayLimit: _prefs.getInt(_kPacketLimit) ?? d.packetDisplayLimit,
    );
  }

  @override
  Future<void> save(AppSettings settings) async {
    await _prefs.setInt(_kPort, settings.artNetPort);
    await _prefs.setString(_kBroadcast, settings.broadcastAddress);
    await _prefs.setBool(_kPreferComputed, settings.preferComputedBroadcast);
    await _prefs.setStringList(_kMdns, settings.mdnsServiceTypes);
    await _prefs.setBool(_kDebug, settings.debugLogging);
    await _prefs.setInt(_kTimeout, settings.listenTimeoutMs);
    await _prefs.setInt(_kPacketLimit, settings.packetDisplayLimit);
  }
}

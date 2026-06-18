import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'device_config_client.dart';

/// Supplies device HTTP-Basic credentials to the config controller and
/// remembers the ones that work, keyed by device host.
///
/// Two sources feed an attempt: the app-wide [defaultCredentials] (set in
/// Settings) and a per-host entry remembered after a successful authenticated
/// call. Overridable in tests via [deviceCredentialStoreProvider].
abstract class DeviceCredentialStore {
  /// Credentials previously confirmed to work for [host], if any.
  DeviceCredentials? rememberedFor(String host);

  /// The app-wide default credentials, or null when none are configured.
  DeviceCredentials? get defaultCredentials;

  /// Set (or clear, when null/empty) the app-wide default credentials.
  void setDefault(DeviceCredentials? creds);

  /// Persist [creds] as the working credentials for [host].
  void remember(String host, DeviceCredentials creds);
}

/// Plain snapshot of the stored credentials, decoded once at startup so the
/// store can serve synchronous reads. The on-disk form is a single JSON value
/// encrypted at rest by [FlutterSecureStorage].
class CredentialSnapshot {
  const CredentialSnapshot({this.defaultCredentials, this.hosts = const {}});

  final DeviceCredentials? defaultCredentials;
  final Map<String, DeviceCredentials> hosts;

  static DeviceCredentials? _decodeCreds(Object? v) {
    if (v is! Map) return null;
    return DeviceCredentials(v['u'] as String? ?? '', v['p'] as String? ?? '');
  }

  /// Parse the stored JSON blob; any corruption decodes to an empty snapshot.
  static CredentialSnapshot decode(String? raw) {
    if (raw == null || raw.isEmpty) return const CredentialSnapshot();
    try {
      final m = jsonDecode(raw);
      if (m is! Map<String, dynamic>) return const CredentialSnapshot();
      final hosts = <String, DeviceCredentials>{};
      final h = m['hosts'];
      if (h is Map) {
        h.forEach((k, v) {
          final c = _decodeCreds(v);
          if (c != null) hosts['$k'] = c;
        });
      }
      return CredentialSnapshot(
        defaultCredentials: _decodeCreds(m['default']),
        hosts: hosts,
      );
    } catch (_) {
      return const CredentialSnapshot();
    }
  }
}

/// Function that persists the encoded credential blob (encrypted on write).
typedef CredentialWriter = Future<void> Function(String json);

/// [DeviceCredentialStore] kept in memory for synchronous reads and written
/// through to encrypted secure storage on every change. Constructed from a
/// [CredentialSnapshot] loaded at startup.
class SecureDeviceCredentialStore implements DeviceCredentialStore {
  SecureDeviceCredentialStore(CredentialSnapshot snapshot, this._write)
      : _default = snapshot.defaultCredentials,
        _hosts = {...snapshot.hosts};

  final CredentialWriter _write;
  DeviceCredentials? _default;
  final Map<String, DeviceCredentials> _hosts;

  @override
  DeviceCredentials? get defaultCredentials => _default;

  @override
  DeviceCredentials? rememberedFor(String host) => _hosts[host];

  @override
  void setDefault(DeviceCredentials? creds) {
    _default = (creds != null && (creds.user.isNotEmpty || creds.pass.isNotEmpty))
        ? creds
        : null;
    _persist();
  }

  @override
  void remember(String host, DeviceCredentials creds) {
    _hosts[host] = creds;
    _persist();
  }

  void _persist() {
    final map = <String, dynamic>{
      if (_default != null)
        'default': {'u': _default!.user, 'p': _default!.pass},
      'hosts': _hosts.map((h, c) => MapEntry(h, {'u': c.user, 'p': c.pass})),
    };
    unawaited(_write(jsonEncode(map)));
  }
}

/// The secure-storage key holding the credential blob.
const String kCredentialStorageKey = 'device_credentials_v1';

/// Strong defaults (AES-GCM + RSA-OAEP key wrapping on Android, Keychain on
/// Apple). The same instance config is used at startup and for write-through.
FlutterSecureStorage buildSecureStorage() => const FlutterSecureStorage();

/// Load and decode the stored credentials. Call once at startup; a read error
/// (e.g. missing keychain entitlement) degrades to an empty snapshot.
Future<CredentialSnapshot> loadCredentialSnapshot(
    FlutterSecureStorage storage) async {
  try {
    return CredentialSnapshot.decode(
        await storage.read(key: kCredentialStorageKey));
  } catch (_) {
    return const CredentialSnapshot();
  }
}

/// The secure storage handle (write-through target). Overridable in tests.
final secureStorageProvider =
    Provider<FlutterSecureStorage>((_) => buildSecureStorage());

/// The credentials decoded at startup. Defaults to empty; `main()` overrides it
/// with the value read from secure storage.
final initialCredentialSnapshotProvider =
    Provider<CredentialSnapshot>((_) => const CredentialSnapshot());

/// The credential store. Production reads the startup snapshot and writes
/// through to encrypted storage; tests override this with an in-memory fake.
final deviceCredentialStoreProvider = Provider<DeviceCredentialStore>((ref) {
  final storage = ref.read(secureStorageProvider);
  final snapshot = ref.read(initialCredentialSnapshotProvider);
  return SecureDeviceCredentialStore(
    snapshot,
    (json) => storage.write(key: kCredentialStorageKey, value: json),
  );
});

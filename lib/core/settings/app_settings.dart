/// Default mDNS service types browsed by the app.
///
/// `_http._tcp` and `_ws._tcp` match the user's ESP firmware (web config UI /
/// websocket); `_workstation._tcp` is a generic sanity check. NOTE: on iOS,
/// every type browsed at runtime must also be declared in Info.plist
/// `NSBonjourServices` — see docs/IOS_LOCAL_NETWORK.md.
const List<String> kDefaultMdnsServiceTypes = <String>[
  '_http._tcp',
  '_ws._tcp',
  '_workstation._tcp',
];

/// Immutable application settings. Persisted via [SettingsRepository].
class AppSettings {
  const AppSettings({
    this.artNetPort = 6454,
    this.broadcastAddress = '255.255.255.255',
    this.preferComputedBroadcast = true,
    this.mdnsServiceTypes = kDefaultMdnsServiceTypes,
    this.debugLogging = false,
    this.listenTimeoutMs = 3000,
    this.packetDisplayLimit = 500,
  });

  /// UDP port for Art-Net (spec default 6454).
  final int artNetPort;

  /// Broadcast address used when no manual unicast target is given.
  /// Defaults to limited broadcast; the dashboard/settings can swap in the
  /// computed subnet-directed broadcast (more reliable, esp. on iOS).
  final String broadcastAddress;

  /// When true, prefer the auto-computed subnet broadcast (from the device IP +
  /// mask) over [broadcastAddress] when one is available.
  final bool preferComputedBroadcast;

  /// mDNS/Bonjour service types to browse.
  final List<String> mdnsServiceTypes;

  /// Whether debug-level logging is recorded.
  final bool debugLogging;

  /// How long discovery/monitor listens before stopping (milliseconds).
  final int listenTimeoutMs;

  /// Max packets retained/shown in the Art-Net monitor's recent-packets log.
  final int packetDisplayLimit;

  Duration get listenTimeout => Duration(milliseconds: listenTimeoutMs);

  static const AppSettings defaults = AppSettings();

  AppSettings copyWith({
    int? artNetPort,
    String? broadcastAddress,
    bool? preferComputedBroadcast,
    List<String>? mdnsServiceTypes,
    bool? debugLogging,
    int? listenTimeoutMs,
    int? packetDisplayLimit,
  }) {
    return AppSettings(
      artNetPort: artNetPort ?? this.artNetPort,
      broadcastAddress: broadcastAddress ?? this.broadcastAddress,
      preferComputedBroadcast:
          preferComputedBroadcast ?? this.preferComputedBroadcast,
      mdnsServiceTypes: mdnsServiceTypes ?? this.mdnsServiceTypes,
      debugLogging: debugLogging ?? this.debugLogging,
      listenTimeoutMs: listenTimeoutMs ?? this.listenTimeoutMs,
      packetDisplayLimit: packetDisplayLimit ?? this.packetDisplayLimit,
    );
  }
}

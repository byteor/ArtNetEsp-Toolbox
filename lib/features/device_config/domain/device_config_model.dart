/// Dart mirror of the ArtNetEsp device config schema.
///
/// Source of truth: the firmware's `docs/API_UX_DESIGN.md` (contract v1.0.0,
/// firmware 2026.2.x) §6. Top-level read/write keys are `host`, `universe`,
/// `hw`, `dmx`; `info`, `_needReboot` and (effectively) `configVersion` are
/// output-only. WiFi is intentionally absent from the contract envelope.
///
/// See docs/DEVICE_CONFIG_PARITY.md for the UI/field mapping kept in sync with
/// the firmware contract.
library;

int _asInt(Object? v, int fallback) =>
    v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? fallback : fallback);

bool _asBool(Object? v, bool fallback) => v is bool ? v : fallback;

String _asString(Object? v, String fallback) => v is String ? v : fallback;

/// DMX device type (§6.4). Wire string is canonical; `RELAY` is a legacy alias
/// for [binary] and any unknown value maps to [disabled].
enum DmxType {
  binary('BINARY'),
  dimmer('DIMMER'),
  servo('SERVO'),
  repeater('REPEATER'),
  disabled('DISABLED');

  const DmxType(this.wire);

  /// The canonical wire string sent to / read from the device.
  final String wire;

  static DmxType fromWire(Object? value) {
    final u = (value is String ? value : '').toUpperCase();
    if (u == 'RELAY') return DmxType.binary; // legacy alias
    for (final t in DmxType.values) {
      if (t.wire == u) return t;
    }
    return DmxType.disabled; // unrecognized → disabled
  }

  /// Field visibility per type (§6.3 / §7.3 visibility table).
  bool get showsPin =>
      this == DmxType.binary || this == DmxType.dimmer || this == DmxType.servo;
  bool get showsLevel => this == DmxType.binary || this == DmxType.dimmer;
  bool get showsThreshold => this == DmxType.binary;
  bool get showsPulse => this == DmxType.dimmer;
  bool get showsMultiplier => this == DmxType.dimmer;
  bool get showsBlackout => this != DmxType.disabled;
}

/// One `dmx[]` entry (§6.3).
class DmxDevice {
  const DmxDevice({
    this.channel = 0,
    this.type = DmxType.disabled,
    this.pin = 2,
    this.level = 'LOW',
    this.threshold = 127,
    this.pulse = 10,
    this.multiplier = 1,
    this.blackout = true,
  });

  final int channel; // start DMX channel; UI range 1..512
  final DmxType type;
  final int pin;
  final String level; // 'HIGH' or 'LOW'
  final int threshold; // 0..255
  final int pulse;
  final int multiplier;
  final bool blackout;

  /// Defaults for a freshly added device (§7.3).
  static const DmxDevice freshDefault = DmxDevice(
    channel: 1,
    type: DmxType.binary,
    pin: 2,
    level: 'HIGH',
    threshold: 127,
    pulse: 10,
    multiplier: 1,
    blackout: true,
  );

  factory DmxDevice.fromJson(Map<String, dynamic> json) => DmxDevice(
        channel: _asInt(json['channel'], 0),
        type: DmxType.fromWire(json['type']),
        pin: _asInt(json['pin'], 2),
        level: _normLevel(json['level']),
        threshold: _asInt(json['threshold'], 127),
        pulse: _asInt(json['pulse'], 10),
        multiplier: _asInt(json['multiplier'], 1),
        blackout: _asBool(json['blackout'], true),
      );

  /// Serializes every field; the device stores/round-trips unused ones (§6.3).
  Map<String, dynamic> toJson() => {
        'channel': channel,
        'type': type.wire,
        'pin': pin,
        'level': level,
        'threshold': threshold,
        'pulse': pulse,
        'multiplier': multiplier,
        'blackout': blackout,
      };

  DmxDevice copyWith({
    int? channel,
    DmxType? type,
    int? pin,
    String? level,
    int? threshold,
    int? pulse,
    int? multiplier,
    bool? blackout,
  }) =>
      DmxDevice(
        channel: channel ?? this.channel,
        type: type ?? this.type,
        pin: pin ?? this.pin,
        level: level ?? this.level,
        threshold: threshold ?? this.threshold,
        pulse: pulse ?? this.pulse,
        multiplier: multiplier ?? this.multiplier,
        blackout: blackout ?? this.blackout,
      );

  // Any value other than (case-insensitive) "high" reads as LOW (§6.3).
  static String _normLevel(Object? v) =>
      (v is String && v.toLowerCase() == 'high') ? 'HIGH' : 'LOW';
}

/// The `hw` object (§6.2). Pin/freq board defaults only matter when a key is
/// missing; in practice these are always read from the device first.
class HardwareConfig {
  const HardwareConfig({
    this.freq = 600,
    this.ledPin = 2,
    this.buttonPin = 0,
    this.longPressDelay = 5000,
    this.wifiPowerSave = false,
    this.authEnabled = false,
    this.authUser = '',
    this.authPass = '',
  });

  final int freq;
  final int ledPin;
  final int buttonPin;
  final int longPressDelay;
  final bool wifiPowerSave;
  final bool authEnabled;
  final String authUser;
  final String authPass;

  factory HardwareConfig.fromJson(Map<String, dynamic> json) => HardwareConfig(
        freq: _asInt(json['freq'], 600),
        ledPin: _asInt(json['ledPin'], 2),
        buttonPin: _asInt(json['buttonPin'], 0),
        longPressDelay: _asInt(json['longPressDelay'], 5000),
        wifiPowerSave: _asBool(json['wifiPowerSave'], false),
        authEnabled: _asBool(json['authEnabled'], false),
        authUser: _asString(json['authUser'], ''),
        authPass: _asString(json['authPass'], ''),
      );

  Map<String, dynamic> toJson() => {
        'freq': freq,
        'ledPin': ledPin,
        'buttonPin': buttonPin,
        'longPressDelay': longPressDelay,
        'wifiPowerSave': wifiPowerSave,
        'authEnabled': authEnabled,
        'authUser': authUser,
        'authPass': authPass,
      };

  HardwareConfig copyWith({
    int? freq,
    int? ledPin,
    int? buttonPin,
    int? longPressDelay,
    bool? wifiPowerSave,
    bool? authEnabled,
    String? authUser,
    String? authPass,
  }) =>
      HardwareConfig(
        freq: freq ?? this.freq,
        ledPin: ledPin ?? this.ledPin,
        buttonPin: buttonPin ?? this.buttonPin,
        longPressDelay: longPressDelay ?? this.longPressDelay,
        wifiPowerSave: wifiPowerSave ?? this.wifiPowerSave,
        authEnabled: authEnabled ?? this.authEnabled,
        authUser: authUser ?? this.authUser,
        authPass: authPass ?? this.authPass,
      );
}

/// The output-only `info` object (§6.5).
class DeviceRuntimeInfo {
  const DeviceRuntimeInfo({
    this.id = '',
    this.chip = '',
    this.version = '',
    this.built = '',
    this.maxDmxDevices = 8,
    this.ssid = '',
    this.rssi = 0,
    this.uptime = 0,
    this.freeHeap = 0,
    this.ota = false,
  });

  final String id;
  final String chip;
  final String version;
  final String built;
  final int maxDmxDevices;
  final String ssid;
  final int rssi;
  final int uptime; // ms since boot
  final int freeHeap; // bytes
  final bool ota;

  factory DeviceRuntimeInfo.fromJson(Map<String, dynamic> json) =>
      DeviceRuntimeInfo(
        id: _asString(json['id'], ''),
        chip: _asString(json['chip'], ''),
        version: _asString(json['version'], ''),
        built: _asString(json['built'], ''),
        maxDmxDevices: _asInt(json['max_dmx_devices'], 8),
        ssid: _asString(json['ssid'], ''),
        rssi: _asInt(json['rssi'], 0),
        uptime: _asInt(json['uptime'], 0),
        freeHeap: _asInt(json['free_heap'], 0),
        ota: _asBool(json['ota'], false),
      );
}

/// The full `GET /config` envelope (§6.1). `info`, `needReboot` and
/// `configVersion` are output-only; only [generalPayload]/[devicesPayload]/
/// [hwPayload] are ever sent back (partial, section-scoped — §5.4).
class DeviceFullConfig {
  const DeviceFullConfig({
    this.configVersion = 1,
    this.needReboot = false,
    this.host = '',
    this.universe = 0,
    this.hw = const HardwareConfig(),
    this.dmx = const [],
    this.info = const DeviceRuntimeInfo(),
  });

  final int configVersion;
  final bool needReboot;
  final String host;
  final int universe;
  final HardwareConfig hw;
  final List<DmxDevice> dmx;
  final DeviceRuntimeInfo info;

  factory DeviceFullConfig.fromJson(Map<String, dynamic> json) {
    final rawDmx = json['dmx'];
    return DeviceFullConfig(
      configVersion: _asInt(json['configVersion'], 1),
      needReboot: _asBool(json['_needReboot'], false),
      host: _asString(json['host'], ''),
      universe: _asInt(json['universe'], 0),
      hw: HardwareConfig.fromJson(
          (json['hw'] as Map?)?.cast<String, dynamic>() ?? const {}),
      dmx: rawDmx is List
          ? rawDmx
              .whereType<Map>()
              .map((e) => DmxDevice.fromJson(e.cast<String, dynamic>()))
              .toList()
          : const [],
      info: DeviceRuntimeInfo.fromJson(
          (json['info'] as Map?)?.cast<String, dynamic>() ?? const {}),
    );
  }

  /// `{host, universe}` — the General section save payload (§7.3).
  Map<String, dynamic> generalPayload() => {'host': host, 'universe': universe};

  /// `{dmx: [...]}` — the Devices section save payload; whole array (§5.4).
  Map<String, dynamic> devicesPayload() =>
      {'dmx': dmx.map((d) => d.toJson()).toList()};

  /// `{hw: {...}}` — the System/Advanced section save payload (§7.3).
  Map<String, dynamic> hwPayload() => {'hw': hw.toJson()};

  DeviceFullConfig copyWith({
    int? configVersion,
    bool? needReboot,
    String? host,
    int? universe,
    HardwareConfig? hw,
    List<DmxDevice>? dmx,
    DeviceRuntimeInfo? info,
  }) =>
      DeviceFullConfig(
        configVersion: configVersion ?? this.configVersion,
        needReboot: needReboot ?? this.needReboot,
        host: host ?? this.host,
        universe: universe ?? this.universe,
        hw: hw ?? this.hw,
        dmx: dmx ?? this.dmx,
        info: info ?? this.info,
      );
}

/// Identifies an editable config section (drives per-section dirty + save).
enum ConfigSection { general, devices, system }

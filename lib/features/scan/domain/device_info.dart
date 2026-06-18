/// Device identity returned by an ESP node's HTTP API.
///
/// Parsed from either `GET /status` or `GET /config`. As with the Art-Net
/// parsers, network input is not trusted: parsing returns null unless the
/// expected string fields are present and of the right type.
class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.chip,
    required this.version,
    this.built,
    this.host,
  });

  final String id;
  final String chip;
  final String version;
  final DateTime? built;
  final String? host;

  /// Parses the `/status` shape: `{ id, chip, version, built }`.
  static DeviceInfo? fromStatusJson(Map<String, dynamic> json) {
    final id = json['id'];
    final chip = json['chip'];
    final version = json['version'];
    if (id is! String || chip is! String || version is! String) return null;
    return DeviceInfo(
      id: id,
      chip: chip,
      version: version,
      built: _parseBuilt(json['built']),
    );
  }

  /// Parses the `/config` shape: `{ info: { id, chip, version, built }, host }`.
  static DeviceInfo? fromConfigJson(Map<String, dynamic> json) {
    final info = json['info'];
    if (info is! Map) return null;
    final id = info['id'];
    final chip = info['chip'];
    final version = info['version'];
    if (id is! String || chip is! String || version is! String) return null;
    return DeviceInfo(
      id: id,
      chip: chip,
      version: version,
      built: _parseBuilt(info['built']),
      host: json['host'] is String ? json['host'] as String : null,
    );
  }

  static DateTime? _parseBuilt(dynamic value) =>
      value is String ? DateTime.tryParse(value) : null;

  /// Human-readable build timestamp, e.g. `2026-06-13 14:05:21`.
  String get builtLabel {
    final b = built;
    if (b == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${b.year}-${two(b.month)}-${two(b.day)} '
        '${two(b.hour)}:${two(b.minute)}:${two(b.second)}';
  }
}

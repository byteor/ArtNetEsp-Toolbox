/// An Art-Net node discovered via ArtPollReply.
///
/// This is an immutable value object. The pure parser
/// (`parseArtPollReply`) fills the protocol fields; the service layer adds
/// transport-derived data such as [sourceIp] and [lastSeen].
class ArtNetNode {
  const ArtNetNode({
    required this.ip,
    this.sourceIp,
    this.port,
    this.shortName = '',
    this.longName = '',
    this.oem,
    this.esta,
    this.firmwareVersion,
    this.numPorts,
    this.rawSummary = '',
    this.lastSeen,
  });

  /// Best-known IPv4 address to reach this node (packet IP field, falling back
  /// to the UDP datagram source address).
  final String ip;

  /// The UDP source address the reply actually arrived from (may differ from
  /// [ip] on multi-homed nodes). Useful for diagnostics.
  final String? sourceIp;

  /// UDP port reported in the reply (normally 6454).
  final int? port;

  /// Node short name (max 18 chars on the wire).
  final String shortName;

  /// Node long name (max 64 chars on the wire).
  final String longName;

  /// OEM code (manufacturer/product identifier), if parsed.
  final int? oem;

  /// ESTA manufacturer code, if parsed.
  final int? esta;

  /// Firmware version (VersInfo), if parsed.
  final int? firmwareVersion;

  /// Number of DMX ports the node exposes (0..4), if parsed.
  final int? numPorts;

  /// Short hex/diagnostic summary of the raw packet.
  final String rawSummary;

  /// When this node was last heard from (set by the service layer).
  final DateTime? lastSeen;

  /// A friendly label for lists: long name, else short name, else IP.
  String get displayName {
    if (longName.isNotEmpty) return longName;
    if (shortName.isNotEmpty) return shortName;
    return ip;
  }

  ArtNetNode copyWith({
    String? ip,
    String? sourceIp,
    int? port,
    String? shortName,
    String? longName,
    int? oem,
    int? esta,
    int? firmwareVersion,
    int? numPorts,
    String? rawSummary,
    DateTime? lastSeen,
  }) {
    return ArtNetNode(
      ip: ip ?? this.ip,
      sourceIp: sourceIp ?? this.sourceIp,
      port: port ?? this.port,
      shortName: shortName ?? this.shortName,
      longName: longName ?? this.longName,
      oem: oem ?? this.oem,
      esta: esta ?? this.esta,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      numPorts: numPorts ?? this.numPorts,
      rawSummary: rawSummary ?? this.rawSummary,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  /// Nodes are considered the same device if they share an IP address.
  @override
  bool operator ==(Object other) =>
      other is ArtNetNode && other.ip == ip;

  @override
  int get hashCode => ip.hashCode;
}

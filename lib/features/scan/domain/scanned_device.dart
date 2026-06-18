import '../../artnet/domain/artnet_node.dart';
import '../../mdns/domain/mdns_service_record.dart';
import 'device_info.dart';

/// A device found by the combined scan, merging Art-Net + mDNS sources and the
/// HTTP probe result.
///
/// Per the scan rules:
///  - [info] non-null  => the device answered `/status` or `/config` ("good",
///    [enabled] true).
///  - probe failed but Art-Net saw it => kept with [info] null and [enabled]
///    false (inactive); its mDNS record is dropped.
///  - probe failed and only mDNS saw it => not represented (dropped by the
///    controller).
class ScannedDevice {
  const ScannedDevice({
    required this.ip,
    required this.info,
    required this.artnet,
    required this.mdns,
  });

  final String ip;
  final DeviceInfo? info;
  final ArtNetNode? artnet;
  final MdnsServiceRecord? mdns;

  bool get good => info != null;
  bool get enabled => good;
  bool get fromArtnet => artnet != null;
  bool get fromMdns => mdns != null;

  /// Preferred label: Art-Net short name, else the mDNS host (without `.local`),
  /// else the probed host/id, else IP.
  String get title {
    final a = artnet;
    if (a != null && a.shortName.isNotEmpty) return a.shortName;
    final m = mdns;
    if (m != null && m.host.isNotEmpty) return _stripLocal(m.host);
    final i = info;
    if (i != null) {
      if (i.host != null && i.host!.isNotEmpty) return _stripLocal(i.host!);
      if (i.id.isNotEmpty) return i.id;
    }
    return ip;
  }

  /// Strips a trailing dot and a `.local` suffix from an mDNS hostname.
  static String _stripLocal(String host) {
    var h = host;
    if (h.endsWith('.')) h = h.substring(0, h.length - 1);
    if (h.toLowerCase().endsWith('.local')) {
      h = h.substring(0, h.length - '.local'.length);
    }
    return h;
  }

  List<String> get sources => [
        if (fromArtnet) 'Art-Net',
        if (fromMdns) 'mDNS',
      ];
}

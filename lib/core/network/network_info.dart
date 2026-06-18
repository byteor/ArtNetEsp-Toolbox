import 'package:network_info_plus/network_info_plus.dart';

/// Snapshot of the device's local Wi-Fi network parameters.
class LocalNetworkStatus {
  const LocalNetworkStatus({
    this.ipAddress,
    this.gateway,
    this.broadcast,
    this.subnetMask,
  });

  final String? ipAddress;
  final String? gateway;
  final String? broadcast;
  final String? subnetMask;

  bool get hasWifi =>
      ipAddress != null && ipAddress!.isNotEmpty && ipAddress != '0.0.0.0';

  static const LocalNetworkStatus unknown = LocalNetworkStatus();
}

/// Reads local network info via `network_info_plus`.
///
/// We deliberately DO NOT call `getWifiName`/`getWifiBSSID` — those require
/// location permission on Android and a special entitlement on iOS. IP, gateway,
/// submask and broadcast need no extra permission and are enough to drive
/// Art-Net broadcast addressing and the dashboard.
class NetworkInfoService {
  NetworkInfoService([NetworkInfo? info]) : _info = info ?? NetworkInfo();

  final NetworkInfo _info;

  Future<LocalNetworkStatus> read() async {
    String? ip;
    String? gateway;
    String? broadcast;
    String? mask;

    try {
      ip = await _info.getWifiIP();
    } catch (_) {/* not on Wi-Fi or unsupported */}
    try {
      gateway = await _info.getWifiGatewayIP();
    } catch (_) {}
    try {
      broadcast = await _info.getWifiBroadcast();
    } catch (_) {}
    try {
      mask = await _info.getWifiSubmask();
    } catch (_) {}

    // iOS often returns no broadcast address; compute it from IP + mask.
    broadcast ??= computeBroadcast(ip, mask);

    return LocalNetworkStatus(
      ipAddress: _clean(ip),
      gateway: _clean(gateway),
      broadcast: _clean(broadcast),
      subnetMask: _clean(mask),
    );
  }

  static String? _clean(String? v) {
    if (v == null) return null;
    final t = v.replaceFirst('/', '').trim();
    return t.isEmpty ? null : t;
  }

  /// Computes the subnet-directed broadcast address from an IPv4 [ip] and
  /// [mask] (e.g. 192.168.1.50 + 255.255.255.0 -> 192.168.1.255). Returns null
  /// if either is missing/invalid.
  static String? computeBroadcast(String? ip, String? mask) {
    if (ip == null || mask == null) return null;
    final ipParts = ip.split('.');
    final maskParts = mask.split('.');
    if (ipParts.length != 4 || maskParts.length != 4) return null;
    final out = <int>[];
    for (var i = 0; i < 4; i++) {
      final ipByte = int.tryParse(ipParts[i]);
      final maskByte = int.tryParse(maskParts[i]);
      if (ipByte == null || maskByte == null) return null;
      out.add((ipByte & maskByte) | (~maskByte & 0xFF));
    }
    return out.join('.');
  }
}

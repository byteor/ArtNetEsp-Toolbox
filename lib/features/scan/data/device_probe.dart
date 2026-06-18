import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/logging/app_logger.dart';
import '../domain/device_info.dart';

const String _kTag = 'probe';

/// Probes a device's HTTP API to obtain its [DeviceInfo].
///
/// Tries `GET /status` first; if that fails or doesn't match the expected
/// shape, falls back to `GET /config`. Uses `dart:io` directly (no extra
/// dependency). All failures are swallowed and returned as null — probing must
/// never throw for an unreachable or chatty device.
///
/// NOTE: this is plain HTTP to a local IP, which requires platform allowances
/// (iOS/macOS ATS local-networking, Android cleartext). See the manifests.
class DeviceProbe {
  DeviceProbe({
    required AppLogger logger,
    this.timeout = const Duration(seconds: 2),
  }) : _logger = logger;

  final AppLogger _logger;
  final Duration timeout;

  Future<DeviceInfo?> probe(String ip, {int port = 80}) async {
    final status = await _getJson(ip, port, '/status');
    if (status != null) {
      final info = DeviceInfo.fromStatusJson(status);
      if (info != null) {
        _logger.info(_kTag, '$ip:$port /status → ${info.id} (${info.chip})');
        return info;
      }
    }
    final config = await _getJson(ip, port, '/config');
    if (config != null) {
      final info = DeviceInfo.fromConfigJson(config);
      if (info != null) {
        _logger.info(_kTag, '$ip:$port /config → ${info.id} (${info.chip})');
        return info;
      }
    }
    _logger.debug(_kTag, '$ip:$port no valid /status or /config');
    return null;
  }

  Future<Map<String, dynamic>?> _getJson(String ip, int port, String path) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .getUrl(Uri.parse('http://$ip:$port$path'))
          .timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) {
        await response.drain<void>();
        return null;
      }
      final body =
          await response.transform(utf8.decoder).join().timeout(timeout);
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      _logger.debug(_kTag, 'GET http://$ip:$port$path failed: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/device_config_model.dart';

/// Firmware API contract version this client targets. When the firmware bumps
/// its contract, follow the sync procedure in docs/DEVICE_CONFIG_PARITY.md.
const String kSupportedContractVersion = '1.0.0';

/// HTTP Basic credentials for devices with `hw.authEnabled` (§5.2).
class DeviceCredentials {
  const DeviceCredentials(this.user, this.pass);

  final String user;
  final String pass;

  String get headerValue => 'Basic ${base64Encode(utf8.encode('$user:$pass'))}';
}

/// The device requires HTTP Basic auth (HTTP 401) on a mutating call (§5.2).
class DeviceAuthException implements Exception {
  const DeviceAuthException();
  @override
  String toString() => 'Unauthorized — the device has HTTP auth enabled.';
}

/// Any other failure talking to the device (network, bad status, too-large).
class DeviceConfigException implements Exception {
  const DeviceConfigException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Lightweight `GET /status` snapshot (§6.5 fields + `_needReboot`).
class DeviceStatus {
  const DeviceStatus({required this.info, required this.needReboot});
  final DeviceRuntimeInfo info;
  final bool needReboot;
}

/// REST client for the ArtNetEsp config API (§5). Plain HTTP to a LAN device via
/// `dart:io` (no extra deps), mirroring [DeviceProbe]'s request/timeout pattern.
class DeviceConfigClient {
  DeviceConfigClient({this.timeout = const Duration(seconds: 4)});

  final Duration timeout;

  /// `GET /config` → the full envelope (§5.3).
  Future<DeviceFullConfig> getConfig(String host, int port,
      {DeviceCredentials? creds}) async {
    return DeviceFullConfig.fromJson(
        await _getJson(host, port, '/config', creds: creds));
  }

  /// `GET /status` → runtime info + `_needReboot` (§5.3). Body fields are the
  /// `info` object at the top level (not nested).
  Future<DeviceStatus> getStatus(String host, int port,
      {DeviceCredentials? creds}) async {
    final json = await _getJson(host, port, '/status', creds: creds);
    return DeviceStatus(
      info: DeviceRuntimeInfo.fromJson(json),
      needReboot: json['_needReboot'] as bool? ?? false,
    );
  }

  /// POST a partial section (§5.4): expect `202`, wait ~500 ms for the device to
  /// apply on its loop, then re-`GET /config` (small retry/backoff) and return
  /// the confirmed config.
  Future<DeviceFullConfig> postConfigSection(
    String host,
    int port,
    Map<String, dynamic> payload, {
    DeviceCredentials? creds,
  }) async {
    await _post(host, port, '/config', jsonEncode(payload),
        creds: creds, expect: 202);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    Object? lastErr;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await getConfig(host, port, creds: creds);
      } catch (e) {
        lastErr = e;
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
    throw DeviceConfigException('Saved, but could not re-read config: $lastErr');
  }

  /// `POST /reboot` (§5.3).
  Future<void> reboot(String host, int port, {DeviceCredentials? creds}) =>
      _post(host, port, '/reboot', '', creds: creds, expect: 200);

  /// `POST /reset-wifi` (§5.3) — clears WiFi and reboots into the captive portal.
  Future<void> resetWifi(String host, int port, {DeviceCredentials? creds}) =>
      _post(host, port, '/reset-wifi', '', creds: creds, expect: 200);

  // --------------------------------------------------------------------------

  Future<Map<String, dynamic>> _getJson(String host, int port, String path,
      {DeviceCredentials? creds}) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client
          .getUrl(Uri.parse('http://$host:$port$path'))
          .timeout(timeout);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (creds != null) {
        req.headers.set(HttpHeaders.authorizationHeader, creds.headerValue);
      }
      final resp = await req.close().timeout(timeout);
      if (resp.statusCode == 401) {
        await resp.drain<void>();
        throw const DeviceAuthException();
      }
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        throw DeviceConfigException('HTTP ${resp.statusCode} from $path');
      }
      final body =
          await resp.transform(utf8.decoder).join().timeout(timeout);
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw DeviceConfigException('Unexpected response from $path');
      }
      return decoded;
    } on SocketException catch (e) {
      throw DeviceConfigException('Cannot reach device: ${e.message}');
    } on TimeoutException {
      throw const DeviceConfigException('Device did not respond in time.');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _post(
    String host,
    int port,
    String path,
    String body, {
    DeviceCredentials? creds,
    required int expect,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client
          .postUrl(Uri.parse('http://$host:$port$path'))
          .timeout(timeout);
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      if (creds != null) {
        req.headers.set(HttpHeaders.authorizationHeader, creds.headerValue);
      }
      if (body.isNotEmpty) req.write(body);
      final resp = await req.close().timeout(timeout);
      final code = resp.statusCode;
      final respBody =
          await resp.transform(utf8.decoder).join().timeout(timeout);
      if (code == 401) throw const DeviceAuthException();
      if (code == 500 && respBody.contains('too large')) {
        throw const DeviceConfigException('Config update too large to save.');
      }
      if (code != expect) {
        throw DeviceConfigException('HTTP $code from $path');
      }
    } on SocketException catch (e) {
      throw DeviceConfigException('Cannot reach device: ${e.message}');
    } on TimeoutException {
      throw const DeviceConfigException('Device did not respond in time.');
    } finally {
      client.close(force: true);
    }
  }
}

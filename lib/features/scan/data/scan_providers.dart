import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/logging_providers.dart';
import '../../../core/settings/settings_providers.dart';
import '../../artnet/data/artnet_providers.dart';
import '../../artnet/domain/artnet_node.dart';
import '../../mdns/data/mdns_providers.dart';
import '../../mdns/domain/mdns_service_record.dart';
import '../domain/scanned_device.dart';
import 'device_probe.dart';

final deviceProbeProvider = Provider<DeviceProbe>(
  (ref) => DeviceProbe(logger: ref.watch(appLoggerProvider)),
);

class ScanState {
  const ScanState({
    this.scanning = false,
    this.phase = '',
    this.devices = const [],
    this.error = '',
    this.lastScan,
  });

  final bool scanning;
  final String phase;
  final List<ScannedDevice> devices;
  final String error;
  final DateTime? lastScan;

  int get goodCount => devices.where((d) => d.good).length;

  ScanState copyWith({
    bool? scanning,
    String? phase,
    List<ScannedDevice>? devices,
    String? error,
    DateTime? lastScan,
  }) {
    return ScanState(
      scanning: scanning ?? this.scanning,
      phase: phase ?? this.phase,
      devices: devices ?? this.devices,
      error: error ?? this.error,
      lastScan: lastScan ?? this.lastScan,
    );
  }
}

/// Orchestrates the combined scan:
/// 1+2. discover Art-Net and mDNS (concurrently),
/// 3.   probe each unique IP over HTTP (`/status`, then `/config`),
/// 4+5. combine into one list applying the keep/drop/disable rules,
/// 6.   expose the result for display.
class ScanController extends Notifier<ScanState> {
  @override
  ScanState build() => const ScanState();

  Future<void> scan() async {
    if (state.scanning) return;
    state = const ScanState(scanning: true, phase: 'Discovering devices…');

    try {
      final settings = ref.read(settingsProvider);
      final artnetService = ref.read(artnetServiceProvider);
      final probe = ref.read(deviceProbeProvider);

      List<String> broadcastTargets;
      try {
        broadcastTargets = await ref.read(artnetBroadcastTargetsProvider.future);
      } catch (_) {
        broadcastTargets = [settings.broadcastAddress];
      }

      // 1 + 2: Art-Net and mDNS in parallel.
      final artnetNodes = <ArtNetNode>[];
      final mdnsServices = <MdnsServiceRecord>[];
      await Future.wait<void>([
        artnetService
            .discover(
              broadcastTargets: broadcastTargets,
              timeout: settings.listenTimeout,
            )
            .then(artnetNodes.addAll),
        _browseMdnsOnce(settings.mdnsServiceTypes, settings.listenTimeout)
            .then(mdnsServices.addAll),
      ]);

      // Index sources by IP.
      final artnetByIp = <String, ArtNetNode>{};
      for (final node in artnetNodes) {
        if (node.ip.isNotEmpty) artnetByIp[node.ip] = node;
      }
      final mdnsByIp = <String, MdnsServiceRecord>{};
      final portByIp = <String, int>{};
      for (final service in mdnsServices) {
        if (service.addresses.isEmpty) continue;
        final ip = service.addresses.first;
        final isHttp = service.type.contains('_http._tcp');
        // Prefer an _http._tcp record (and its port) for the same IP.
        if (!mdnsByIp.containsKey(ip) || isHttp) {
          mdnsByIp[ip] = service;
          if (isHttp && service.port != null) portByIp[ip] = service.port!;
        }
      }

      final ips = <String>{...artnetByIp.keys, ...mdnsByIp.keys};
      state = state.copyWith(phase: 'Probing ${ips.length} device(s)…');

      // 3: probe each IP concurrently.
      final probed = await Future.wait(ips.map((ip) async {
        final info = await probe.probe(ip, port: portByIp[ip] ?? 80);
        return MapEntry(ip, info);
      }));
      final infoByIp = {for (final e in probed) e.key: e.value};

      // 4 + 5: combine and apply rules.
      final devices = <ScannedDevice>[];
      for (final ip in ips) {
        final info = infoByIp[ip];
        final artnet = artnetByIp[ip];
        final mdns = mdnsByIp[ip];
        if (info != null) {
          devices.add(ScannedDevice(
              ip: ip, info: info, artnet: artnet, mdns: mdns));
        } else if (artnet != null) {
          // Probe failed: keep Art-Net (disabled), drop mDNS.
          devices.add(ScannedDevice(
              ip: ip, info: null, artnet: artnet, mdns: null));
        }
        // else: mDNS-only and probe failed → dropped.
      }
      devices.sort((a, b) {
        if (a.good != b.good) return a.good ? -1 : 1;
        return a.ip.compareTo(b.ip);
      });

      state = ScanState(
        scanning: false,
        devices: devices,
        lastScan: DateTime.now(),
      );
    } catch (e) {
      state = state.copyWith(
        scanning: false,
        error: e.toString(),
        lastScan: DateTime.now(),
      );
    }
  }

  /// Browses mDNS for one [timeout] window and returns the accumulated records.
  Future<List<MdnsServiceRecord>> _browseMdnsOnce(
    List<String> types,
    Duration timeout,
  ) async {
    final discovery = ref.read(mdnsDiscoveryProvider);
    final active =
        types.map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    var latest = <MdnsServiceRecord>[];
    final sub = discovery.browse(active).listen((records) => latest = records);
    await Future<void>.delayed(timeout);
    await sub.cancel();
    return latest;
  }
}

final scanControllerProvider =
    NotifierProvider<ScanController, ScanState>(ScanController.new);

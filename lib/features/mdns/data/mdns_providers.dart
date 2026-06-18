import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/logging_providers.dart';
import '../../../core/settings/settings_providers.dart';
import '../domain/mdns_service_record.dart';
import 'mdns_discovery.dart';
import 'nsd_mdns_discovery.dart';

final mdnsDiscoveryProvider = Provider<MdnsDiscovery>(
  (ref) => NsdMdnsDiscovery(ref.watch(appLoggerProvider)),
);

class MdnsState {
  const MdnsState({
    this.browsing = false,
    this.services = const [],
    this.serviceTypes = const [],
    this.error = '',
    this.lastScan,
  });

  final bool browsing;
  final List<MdnsServiceRecord> services;
  final List<String> serviceTypes;
  final String error;
  final DateTime? lastScan;

  MdnsState copyWith({
    bool? browsing,
    List<MdnsServiceRecord>? services,
    List<String>? serviceTypes,
    String? error,
    DateTime? lastScan,
  }) {
    return MdnsState(
      browsing: browsing ?? this.browsing,
      services: services ?? this.services,
      serviceTypes: serviceTypes ?? this.serviceTypes,
      error: error ?? this.error,
      lastScan: lastScan ?? this.lastScan,
    );
  }
}

class MdnsController extends Notifier<MdnsState> {
  StreamSubscription<List<MdnsServiceRecord>>? _sub;

  @override
  MdnsState build() {
    ref.onDispose(() => _sub?.cancel());
    return const MdnsState();
  }

  /// Starts (or restarts) browsing. Uses [types] if given, else the configured
  /// default service types from Settings.
  Future<void> start({List<String>? types}) async {
    await _sub?.cancel();
    final active = (types ?? ref.read(settingsProvider).mdnsServiceTypes)
        .where((t) => t.trim().isNotEmpty)
        .map((t) => t.trim())
        .toList();
    state = MdnsState(
      browsing: true,
      serviceTypes: active,
      lastScan: DateTime.now(),
    );
    final discovery = ref.read(mdnsDiscoveryProvider);
    _sub = discovery.browse(active).listen(
      (services) {
        state = state.copyWith(services: services, lastScan: DateTime.now());
      },
      onError: (Object e) {
        state = state.copyWith(browsing: false, error: e.toString());
      },
    );
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    state = state.copyWith(browsing: false);
  }
}

final mdnsControllerProvider =
    NotifierProvider<MdnsController, MdnsState>(MdnsController.new);

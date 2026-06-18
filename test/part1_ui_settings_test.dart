import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:artnet_app/core/network/network_info.dart';
import 'package:artnet_app/core/network/network_providers.dart';
import 'package:artnet_app/core/network/multicast_lock.dart';
import 'package:artnet_app/core/network/udp_transport.dart';
import 'package:artnet_app/core/logging/app_logger.dart';
import 'package:artnet_app/core/settings/app_settings.dart';
import 'package:artnet_app/core/settings/settings_providers.dart';
import 'package:artnet_app/core/settings/shared_prefs_settings_repository.dart';
import 'package:artnet_app/features/artnet/data/artnet_providers.dart';
import 'package:artnet_app/features/artnet/data/artnet_service.dart';
import 'package:artnet_app/features/artnet/domain/art_dmx.dart';
import 'package:artnet_app/features/dashboard/presentation/dashboard_screen.dart';
import 'package:artnet_app/shared/widgets/log_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake transport whose incoming-datagram stream the test drives directly.
class _FakeTransport implements UdpTransport {
  final StreamController<UdpDatagram> _c =
      StreamController<UdpDatagram>.broadcast();
  bool _bound = false;

  @override
  Future<void> bind(int port) async => _bound = true;
  @override
  bool get isBound => _bound;
  @override
  Stream<UdpDatagram> get datagrams => _c.stream;
  @override
  set broadcast(bool value) {}
  @override
  int send(Uint8List data, String address, int port) => data.length;
  @override
  void recycle() => _bound = false;
  @override
  Future<void> close() async {
    _bound = false;
    if (!_c.isClosed) await _c.close();
  }

  void emit(UdpDatagram d) {
    if (!_c.isClosed) _c.add(d);
  }
}

void main() {
  group('packetDisplayLimit setting', () {
    test('defaults to 500 and round-trips through SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPrefsSettingsRepository(prefs);

      expect((await repo.load()).packetDisplayLimit, 500);

      await repo.save(const AppSettings(packetDisplayLimit: 1234));
      expect((await repo.load()).packetDisplayLimit, 1234);
    });
  });

  testWidgets('Info activity log fills available space (LogView in Expanded)',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialSettingsProvider.overrideWithValue(const AppSettings()),
          localNetworkStatusProvider.overrideWith(
            (ref) async => const LocalNetworkStatus(ipAddress: '192.168.1.10'),
          ),
        ],
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await tester.pump();

    expect(find.byType(LogView), findsOneWidget);
    expect(
      find.ancestor(of: find.byType(LogView), matching: find.byType(Expanded)),
      findsOneWidget,
      reason: 'the activity log should expand to fill, not sit at a fixed 240',
    );
  });

  test('monitor caps the recent-packets log at packetDisplayLimit', () async {
    final fake = _FakeTransport();
    addTearDown(fake.close);
    final container = ProviderContainer(overrides: [
      initialSettingsProvider
          .overrideWithValue(const AppSettings(packetDisplayLimit: 5)),
      artnetServiceProvider.overrideWithValue(
        ArtnetService(
          transport: fake,
          multicastLock: const NoopMulticastLock(),
          logger: AppLogger(),
          port: 6454,
        ),
      ),
    ]);
    addTearDown(container.dispose);

    final monitor = container.read(monitorControllerProvider.notifier);
    container.listen(monitorControllerProvider, (_, _) {});
    monitor.start();
    // Let monitorUniverse's onListen finish (lock + bind + datagram listen).
    await Future<void>.delayed(const Duration(milliseconds: 60));

    final dg = UdpDatagram(
      InternetAddress('10.0.0.9'),
      6454,
      buildArtDmx(universe: 0, channels: List<int>.filled(512, 0)),
    );
    for (var i = 0; i < 20; i++) {
      fake.emit(dg);
    }

    // The controller publishes _log on a ~400 ms ticker; poll for a flush.
    var state = container.read(monitorControllerProvider);
    for (var i = 0; i < 40 && state.packetCount == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      state = container.read(monitorControllerProvider);
    }

    expect(state.packetCount, 20, reason: 'all 20 packets are counted');
    expect(state.log.length, lessThanOrEqualTo(5),
        reason: 'recent-packets log is capped at the configured limit');
    await monitor.stop();
  });
}

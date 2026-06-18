import 'dart:async';
import 'dart:typed_data';

import 'package:artnet_app/app.dart';
import 'package:artnet_app/core/logging/app_logger.dart';
import 'package:artnet_app/core/logging/logging_providers.dart';
import 'package:artnet_app/core/network/multicast_lock.dart';
import 'package:artnet_app/core/network/network_change_providers.dart';
import 'package:artnet_app/core/network/network_info.dart';
import 'package:artnet_app/core/network/network_providers.dart';
import 'package:artnet_app/core/network/udp_transport.dart';
import 'package:artnet_app/core/settings/app_settings.dart';
import 'package:artnet_app/core/settings/settings_providers.dart';
import 'package:artnet_app/features/artnet/data/artnet_providers.dart';
import 'package:artnet_app/features/artnet/data/artnet_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records recycle() calls; everything else is a no-op stub.
class _FakeUdpTransport implements UdpTransport {
  int recycleCount = 0;
  bool _bound = false;
  final StreamController<UdpDatagram> _controller =
      StreamController<UdpDatagram>.broadcast();

  @override
  Future<void> bind(int port) async => _bound = true;
  @override
  bool get isBound => _bound;
  @override
  Stream<UdpDatagram> get datagrams => _controller.stream;
  @override
  set broadcast(bool value) {}
  @override
  int send(Uint8List data, String address, int port) => data.length;
  @override
  void recycle() {
    recycleCount++;
    _bound = false;
  }

  @override
  Future<void> close() async {
    _bound = false;
    if (!_controller.isClosed) await _controller.close();
  }
}

Future<void> _pump() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('networkChangeReactor', () {
    test('on a network change: re-reads Info status and recycles the socket',
        () async {
      final detector = StreamController<LocalNetworkStatus>.broadcast();
      addTearDown(detector.close);
      final fakeTransport = _FakeUdpTransport();
      addTearDown(fakeTransport.close);
      final logger = AppLogger();
      addTearDown(logger.dispose);
      var statusReads = 0;

      final container = ProviderContainer(overrides: [
        networkChangeDetectorProvider.overrideWith((ref) => detector.stream),
        appLoggerProvider.overrideWithValue(logger),
        localNetworkStatusProvider.overrideWith((ref) async {
          statusReads++;
          return const LocalNetworkStatus(ipAddress: '192.168.1.10');
        }),
        artnetServiceProvider.overrideWithValue(
          ArtnetService(
            transport: fakeTransport,
            multicastLock: const NoopMulticastLock(),
            logger: AppLogger(),
            port: 6454,
          ),
        ),
      ]);
      addTearDown(container.dispose);

      // Activate the reactor; keep the Info status live so invalidation forces
      // an immediate re-read.
      container.listen(networkChangeReactorProvider, (_, _) {});
      container.listen(localNetworkStatusProvider, (_, _) {});
      // Prove the detector itself delivers events in this container.
      var directHits = 0;
      container.listen(networkChangeDetectorProvider, (_, next) {
        if (next.hasValue) directHits++;
      });
      await container.read(localNetworkStatusProvider.future);
      expect(statusReads, 1);
      expect(fakeTransport.recycleCount, 0);

      // A change is detected.
      detector.add(const LocalNetworkStatus(ipAddress: '10.0.0.5'));
      await _pump();
      await container.read(localNetworkStatusProvider.future);
      await _pump();

      expect(directHits, 1, reason: 'detector must deliver the change event');
      expect(fakeTransport.recycleCount, 1,
          reason: 'the Art-Net socket must be recycled on a change');
      expect(statusReads, 2, reason: 'Info network status must be re-read');
      expect(
        logger.entries.where(
            (e) => e.tag == 'network' && e.message.contains('Network changed')),
        isNotEmpty,
        reason: 'the change must be written to the activity log',
      );
    });

    test('ignores the detector loading state (no spurious refresh at startup)',
        () async {
      final detector = StreamController<LocalNetworkStatus>.broadcast();
      addTearDown(detector.close);
      final fakeTransport = _FakeUdpTransport();
      addTearDown(fakeTransport.close);
      var statusReads = 0;

      final container = ProviderContainer(overrides: [
        networkChangeDetectorProvider.overrideWith((ref) => detector.stream),
        localNetworkStatusProvider.overrideWith((ref) async {
          statusReads++;
          return const LocalNetworkStatus(ipAddress: '192.168.1.10');
        }),
        artnetServiceProvider.overrideWithValue(
          ArtnetService(
            transport: fakeTransport,
            multicastLock: const NoopMulticastLock(),
            logger: AppLogger(),
            port: 6454,
          ),
        ),
      ]);
      addTearDown(container.dispose);

      container.read(networkChangeReactorProvider);
      container.listen(localNetworkStatusProvider, (_, _) {});
      await container.read(localNetworkStatusProvider.future);
      await _pump();

      // No event emitted yet → no extra read, no recycle.
      expect(statusReads, 1);
      expect(fakeTransport.recycleCount, 0);
    });
  });

  testWidgets(
      'RootShell reacts to a network change: recycles the socket + SnackBar',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final detector = StreamController<LocalNetworkStatus>.broadcast();
    addTearDown(detector.close);
    final fakeTransport = _FakeUdpTransport();
    addTearDown(fakeTransport.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          initialSettingsProvider.overrideWithValue(const AppSettings()),
          localNetworkStatusProvider.overrideWith(
            (ref) async => const LocalNetworkStatus(ipAddress: '192.168.1.10'),
          ),
          networkChangeDetectorProvider.overrideWith((ref) => detector.stream),
          // Real RootShell activation path (ref.watch) drives this service.
          artnetServiceProvider.overrideWithValue(
            ArtnetService(
              transport: fakeTransport,
              multicastLock: const NoopMulticastLock(),
              logger: AppLogger(),
              port: 6454,
            ),
          ),
        ],
        child: const ArtNetApp(),
      ),
    );
    await tester.pump();
    expect(find.text('Network changed — refreshed'), findsNothing);
    expect(fakeTransport.recycleCount, 0);

    detector.add(const LocalNetworkStatus(ipAddress: '10.0.0.5'));
    await tester.pump(); // deliver the stream event to the listeners
    await tester.pump(); // let the SnackBar animate in

    expect(find.text('Network changed — refreshed'), findsOneWidget);
    expect(fakeTransport.recycleCount, 1,
        reason: 'ref.watch(networkChangeReactorProvider) must fire the reactor');
  });
}

import 'package:artnet_app/features/device_config/data/device_config_client.dart';
import 'package:artnet_app/features/device_config/data/device_config_providers.dart';
import 'package:artnet_app/features/device_config/data/device_credentials_store.dart';
import 'package:artnet_app/features/device_config/domain/device_config_model.dart';
import 'package:artnet_app/features/device_config/presentation/device_config_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DeviceFullConfig _config({String host = 'OLD', bool ota = false}) =>
    DeviceFullConfig.fromJson({
      'host': host,
      'universe': 0,
      'hw': {'freq': 600},
      'dmx': [
        {'channel': 1, 'type': 'BINARY', 'pin': 2, 'level': 'HIGH'},
      ],
      'info': {
        'id': 'd6d8',
        'chip': 'ESP32',
        'version': '2026.2.0',
        'max_dmx_devices': 8,
        'ota': ota,
      },
    });

class _FakeClient extends DeviceConfigClient {
  _FakeClient(this._cfg);
  DeviceFullConfig _cfg;
  Map<String, dynamic>? lastPayload;

  @override
  Future<DeviceFullConfig> getConfig(String h, int p,
          {DeviceCredentials? creds}) async =>
      _cfg;
  @override
  Future<DeviceStatus> getStatus(String h, int p,
          {DeviceCredentials? creds}) async =>
      DeviceStatus(info: _cfg.info, needReboot: _cfg.needReboot);
  @override
  Future<DeviceFullConfig> postConfigSection(
      String h, int p, Map<String, dynamic> payload,
      {DeviceCredentials? creds}) async {
    lastPayload = payload;
    _cfg = _cfg.copyWith(
        host: payload['host'] as String? ?? _cfg.host, needReboot: true);
    return _cfg;
  }
}

class _FakeStore implements DeviceCredentialStore {
  _FakeStore({this.defaultCredentials});
  @override
  DeviceCredentials? defaultCredentials;
  final Map<String, DeviceCredentials> _hosts = {};
  @override
  DeviceCredentials? rememberedFor(String host) => _hosts[host];
  @override
  void setDefault(DeviceCredentials? creds) => defaultCredentials = creds;
  @override
  void remember(String host, DeviceCredentials creds) => _hosts[host] = creds;
}

/// Always answers 401 on a mutating call, so every credential candidate fails.
class _AuthRejectClient extends _FakeClient {
  _AuthRejectClient(super.cfg);
  @override
  Future<DeviceFullConfig> postConfigSection(
          String h, int p, Map<String, dynamic> payload,
          {DeviceCredentials? creds}) async =>
      throw const DeviceAuthException();
}

Future<void> _pumpLoaded(
  WidgetTester tester,
  _FakeClient fake, {
  DeviceCredentialStore? store,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deviceConfigClientProvider.overrideWithValue(fake),
        deviceCredentialStoreProvider.overrideWithValue(store ?? _FakeStore()),
      ],
      child: const MaterialApp(
        home: DeviceConfigScreen(target: (host: '10.0.0.5', port: 80)),
      ),
    ),
  );
  await tester.pump(); // flush load() microtasks
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  testWidgets('loads and shows the three tabs + general fields', (tester) async {
    await _pumpLoaded(tester, _FakeClient(_config()));

    expect(find.text('General'), findsOneWidget);
    expect(find.text('Devices'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Hostname'), findsOneWidget);
    // Not dirty yet → save button reads "Saved".
    expect(find.widgetWithText(FilledButton, 'Saved'), findsOneWidget);

    await tester.pumpWidget(const SizedBox()); // dispose → cancel poll timer
  });

  testWidgets('editing hostname + Save posts the general section and toasts',
      (tester) async {
    final fake = _FakeClient(_config());
    await _pumpLoaded(tester, fake);

    await tester.enterText(
        find.widgetWithText(TextField, 'Hostname'), 'NEW-NAME');
    await tester.pump();

    final save = find.widgetWithText(FilledButton, 'Save');
    expect(save, findsOneWidget); // dirty → enabled "Save"
    await tester.tap(save);
    await tester.pump(); // run the (fast) fake save
    await tester.pump(); // surface the SnackBar

    expect(fake.lastPayload?['host'], 'NEW-NAME');
    expect(find.text('Saved — reboot required'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a 401 reveals the auth banner prefilled from default creds',
      (tester) async {
    await _pumpLoaded(
      tester,
      _AuthRejectClient(_config()),
      store: _FakeStore(defaultCredentials: const DeviceCredentials('admin', 'pw')),
    );

    await tester.enterText(
        find.widgetWithText(TextField, 'Hostname'), 'NN');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump(); // run the failing save (tries default creds)
    await tester.pump(); // surface the banner

    expect(find.textContaining('default credentials were rejected'),
        findsOneWidget);
    // The banner's username field is seeded from the Settings default.
    expect(find.text('admin'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Devices tab renders a card with type-driven fields',
      (tester) async {
    await _pumpLoaded(tester, _FakeClient(_config()));

    await tester.tap(find.byType(Tab).at(1)); // Devices
    await tester.pump(); // process the tap → start the tab animation
    await tester.pump(const Duration(seconds: 1)); // finish the animation
    // (can't pumpAndSettle: the 5 s status poll keeps the scheduler busy.)

    expect(find.text('Device 1'), findsOneWidget);
    // BINARY shows threshold; pulse (DIMMER-only) is hidden.
    expect(find.widgetWithText(TextField, 'On/off threshold (0–255)'),
        findsOneWidget);
    expect(find.widgetWithText(TextField, 'Strobe pulse'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('System tab shows the OTA URL as a tappable hyperlink',
      (tester) async {
    await _pumpLoaded(tester, _FakeClient(_config(ota: true)));

    await tester.tap(find.byType(Tab).at(2)); // System
    await tester.pump(); // process the tap → start the tab animation
    await tester.pump(const Duration(seconds: 1)); // finish the animation

    // The firmware-updater tile is present and the whole tile is tappable.
    final tile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Firmware updater'),
    );
    expect(tile.onTap, isNotNull);
    // The OTA URL is rendered as part of the (linkified) subtitle.
    expect(
      find.textContaining('http://OLD.local/update', findRichText: true),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
  });
}

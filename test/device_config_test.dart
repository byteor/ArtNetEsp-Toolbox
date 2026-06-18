import 'dart:convert';
import 'dart:io';

import 'package:artnet_app/features/device_config/data/device_config_client.dart';
import 'package:artnet_app/features/device_config/data/device_config_providers.dart';
import 'package:artnet_app/features/device_config/data/device_credentials_store.dart';
import 'package:artnet_app/features/device_config/domain/device_config_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _sampleConfig({String host = 'Art-d6d8', int universe = 0}) =>
    {
      'configVersion': 1,
      '_needReboot': false,
      'host': host,
      'universe': universe,
      'hw': {
        'freq': 600,
        'ledPin': 2,
        'buttonPin': 0,
        'longPressDelay': 5000,
        'wifiPowerSave': false,
        'authEnabled': false,
        'authUser': '',
        'authPass': '',
      },
      'dmx': [
        {'channel': 1, 'type': 'BINARY', 'pin': 2, 'level': 'HIGH', 'threshold': 127},
        {'channel': 5, 'type': 'DIMMER', 'pin': 4, 'level': 'low', 'pulse': 8, 'multiplier': 2},
      ],
      'info': {
        'id': 'd6d8',
        'chip': 'ESP32',
        'version': '2026.2.0',
        'built': '2026-06-14 13:48:53',
        'max_dmx_devices': 8,
        'ssid': 'home',
        'rssi': -55,
        'uptime': 12345,
        'free_heap': 100000,
        'ota': true,
      },
    };

Future<void> _until(bool Function() cond,
    {Duration timeout = const Duration(seconds: 3)}) async {
  final sw = Stopwatch()..start();
  while (!cond() && sw.elapsed < timeout) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  group('DmxType wire mapping (§6.4)', () {
    test('canonical, RELAY alias, and unknown → disabled', () {
      expect(DmxType.fromWire('DIMMER'), DmxType.dimmer);
      expect(DmxType.fromWire('RELAY'), DmxType.binary); // legacy alias
      expect(DmxType.fromWire('binary'), DmxType.binary); // case-insensitive
      expect(DmxType.fromWire('nonsense'), DmxType.disabled);
      expect(DmxType.fromWire(null), DmxType.disabled);
    });

    test('field visibility per type (§7.3)', () {
      expect(DmxType.binary.showsThreshold, isTrue);
      expect(DmxType.binary.showsPulse, isFalse);
      expect(DmxType.dimmer.showsPulse, isTrue);
      expect(DmxType.dimmer.showsMultiplier, isTrue);
      expect(DmxType.servo.showsPin, isTrue);
      expect(DmxType.servo.showsLevel, isFalse);
      expect(DmxType.repeater.showsPin, isFalse);
      expect(DmxType.repeater.showsBlackout, isTrue);
      expect(DmxType.disabled.showsBlackout, isFalse);
    });
  });

  group('DeviceFullConfig JSON', () {
    test('parses the envelope and normalizes device fields', () {
      final cfg = DeviceFullConfig.fromJson(_sampleConfig(host: 'GREEN'));
      expect(cfg.host, 'GREEN');
      expect(cfg.hw.freq, 600);
      expect(cfg.info.maxDmxDevices, 8);
      expect(cfg.info.ota, isTrue);
      expect(cfg.dmx, hasLength(2));
      expect(cfg.dmx[0].type, DmxType.binary);
      expect(cfg.dmx[1].type, DmxType.dimmer);
      expect(cfg.dmx[1].level, 'LOW'); // 'low' normalized
    });

    test('section payloads contain only their own keys', () {
      final cfg = DeviceFullConfig.fromJson(_sampleConfig());
      expect(cfg.generalPayload().keys, unorderedEquals(['host', 'universe']));
      expect(cfg.hwPayload().keys, ['hw']);
      expect(cfg.devicesPayload().keys, ['dmx']);
      final dmx = cfg.devicesPayload()['dmx'] as List;
      expect(dmx.first, containsPair('type', 'BINARY'));
    });

    test('tolerates missing keys with safe defaults', () {
      final cfg = DeviceFullConfig.fromJson({'host': 'x'});
      expect(cfg.universe, 0);
      expect(cfg.dmx, isEmpty);
      expect(cfg.hw.authEnabled, isFalse);
      expect(cfg.needReboot, isFalse);
    });
  });

  group('DeviceConfigClient (real loopback HttpServer)', () {
    late HttpServer server;
    String host = '';
    int port = 0;

    tearDown(() async => server.close(force: true));

    Future<void> start(Future<void> Function(HttpRequest) handler) async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      host = InternetAddress.loopbackIPv4.address;
      port = server.port;
      server.listen(handler);
    }

    test('POST /config → 202 then re-GET returns the applied config (§5.4)',
        () async {
      String? postedHost;
      await start((req) async {
        if (req.method == 'POST' && req.uri.path == '/config') {
          final body = await utf8.decoder.bind(req).join();
          postedHost = (jsonDecode(body) as Map)['host'] as String?;
          req.response.statusCode = 202;
          req.response.write('{"status":"pending"}');
          await req.response.close();
        } else if (req.method == 'GET' && req.uri.path == '/config') {
          req.response.statusCode = 200;
          req.response.write(jsonEncode(_sampleConfig(host: postedHost ?? '?')));
          await req.response.close();
        }
      });

      final client = DeviceConfigClient();
      final result = await client
          .postConfigSection(host, port, {'host': 'RENAMED', 'universe': 3});
      expect(postedHost, 'RENAMED');
      expect(result.host, 'RENAMED');
    });

    test('401 on POST surfaces DeviceAuthException', () async {
      await start((req) async {
        req.response.statusCode = 401;
        await req.response.close();
      });
      final client = DeviceConfigClient();
      expect(
        () => client.postConfigSection(host, port, {'universe': 1}),
        throwsA(isA<DeviceAuthException>()),
      );
    });

    test('500 "update too large" surfaces a clear DeviceConfigException',
        () async {
      await start((req) async {
        req.response.statusCode = 500;
        req.response.write('{"error":"update too large"}');
        await req.response.close();
      });
      final client = DeviceConfigClient();
      expect(
        () => client.postConfigSection(host, port, {'universe': 1}),
        throwsA(isA<DeviceConfigException>().having(
            (e) => e.message, 'message', contains('too large'))),
      );
    });
  });

  group('DeviceConfigController', () {
    const target = (host: '10.0.0.5', port: 80);

    ProviderContainer containerWith(
        DeviceConfigClient client, DeviceCredentialStore store) {
      final c = ProviderContainer(overrides: [
        deviceConfigClientProvider.overrideWithValue(client),
        deviceCredentialStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(c.dispose);
      c.listen(deviceConfigControllerProvider(target), (_, _) {});
      return c;
    }

    test('loads, tracks general dirty, and saves a section', () async {
      final fake = _FakeClient(DeviceFullConfig.fromJson(_sampleConfig(host: 'OLD')));
      final container = containerWith(fake, _FakeStore());

      final ctrl =
          container.read(deviceConfigControllerProvider(target).notifier);
      await _until(
          () => container.read(deviceConfigControllerProvider(target)).hasData);

      DeviceConfigState read() =>
          container.read(deviceConfigControllerProvider(target));

      expect(read().isDirty(ConfigSection.general), isFalse);
      ctrl.setHost('NEW-NAME');
      expect(read().isDirty(ConfigSection.general), isTrue);

      await ctrl.saveSection(ConfigSection.general);
      final s = read();
      expect(fake.lastPayload?['host'], 'NEW-NAME');
      expect(s.saved!.host, 'NEW-NAME');
      expect(s.isDirty(ConfigSection.general), isFalse);
      expect(s.needReboot, isTrue);
      expect(s.toastMessage, 'Saved — reboot required');
    });

    test('a no-auth device never sends or remembers credentials', () async {
      final fake = _FakeClient(DeviceFullConfig.fromJson(_sampleConfig()));
      final store = _FakeStore();
      final container = containerWith(fake, store);
      final ctrl =
          container.read(deviceConfigControllerProvider(target).notifier);
      await _until(
          () => container.read(deviceConfigControllerProvider(target)).hasData);

      ctrl.setHost('X');
      await ctrl.saveSection(ConfigSection.general);

      expect(container.read(deviceConfigControllerProvider(target)).needsAuth,
          isFalse);
      expect(store.remembered, isEmpty); // null creds aren't cached
    });

    test('default credentials are tried automatically and then remembered',
        () async {
      final fake = _AuthClient(DeviceFullConfig.fromJson(_sampleConfig()),
          user: 'admin', pass: 'secret');
      final store = _FakeStore(
          defaultCredentials: const DeviceCredentials('admin', 'secret'));
      final container = containerWith(fake, store);
      final ctrl =
          container.read(deviceConfigControllerProvider(target).notifier);
      await _until(
          () => container.read(deviceConfigControllerProvider(target)).hasData);

      ctrl.setUniverse(7);
      await ctrl.saveSection(ConfigSection.general);

      final s = container.read(deviceConfigControllerProvider(target));
      expect(s.needsAuth, isFalse);
      expect(s.saved!.universe, 7);
      expect(s.creds?.user, 'admin'); // adopted the working creds
      expect(store.remembered[target.host]?.pass, 'secret'); // and cached them
    });

    test('wrong default credentials surface the auth prompt', () async {
      final fake = _AuthClient(DeviceFullConfig.fromJson(_sampleConfig()),
          user: 'admin', pass: 'secret');
      final store = _FakeStore(
          defaultCredentials: const DeviceCredentials('admin', 'WRONG'));
      final container = containerWith(fake, store);
      final ctrl =
          container.read(deviceConfigControllerProvider(target).notifier);
      await _until(
          () => container.read(deviceConfigControllerProvider(target)).hasData);

      ctrl.setUniverse(7);
      await ctrl.saveSection(ConfigSection.general);

      final s = container.read(deviceConfigControllerProvider(target));
      expect(s.needsAuth, isTrue);
      expect(s.toastMessage, contains('Unauthorized'));
      expect(store.remembered, isEmpty);
    });

    test('prompted credentials are used and remembered on the next save',
        () async {
      final fake = _AuthClient(DeviceFullConfig.fromJson(_sampleConfig()),
          user: 'admin', pass: 'secret');
      final store = _FakeStore(); // no default → straight to the prompt
      final container = containerWith(fake, store);
      final ctrl =
          container.read(deviceConfigControllerProvider(target).notifier);
      await _until(
          () => container.read(deviceConfigControllerProvider(target)).hasData);

      ctrl.setUniverse(7);
      await ctrl.saveSection(ConfigSection.general);
      expect(container.read(deviceConfigControllerProvider(target)).needsAuth,
          isTrue);

      ctrl.setCredentials('admin', 'secret'); // user types them in the banner
      await ctrl.saveSection(ConfigSection.general);

      final s = container.read(deviceConfigControllerProvider(target));
      expect(s.needsAuth, isFalse);
      expect(s.saved!.universe, 7);
      expect(store.remembered[target.host]?.user, 'admin');
    });

    test('credentials remembered for a host are seeded on load', () async {
      final fake = _AuthClient(DeviceFullConfig.fromJson(_sampleConfig()),
          user: 'admin', pass: 'secret');
      final store = _FakeStore(hosts: {
        target.host: const DeviceCredentials('admin', 'secret'),
      });
      final container = containerWith(fake, store);
      final ctrl =
          container.read(deviceConfigControllerProvider(target).notifier);
      await _until(
          () => container.read(deviceConfigControllerProvider(target)).hasData);

      // Seeded from the per-host cache, no prompt needed.
      expect(container.read(deviceConfigControllerProvider(target)).creds?.user,
          'admin');

      ctrl.setUniverse(3);
      await ctrl.saveSection(ConfigSection.general);
      expect(fake.lastCreds?.pass, 'secret'); // first attempt already authed
      expect(container.read(deviceConfigControllerProvider(target)).needsAuth,
          isFalse);
    });
  });

  group('SecureDeviceCredentialStore', () {
    test('CredentialSnapshot decode tolerates missing/garbage blobs', () {
      expect(CredentialSnapshot.decode(null).defaultCredentials, isNull);
      expect(CredentialSnapshot.decode('').hosts, isEmpty);
      expect(CredentialSnapshot.decode('not json').hosts, isEmpty);
    });

    test('write-through encodes a round-trippable blob; setDefault clears on empty',
        () {
      String? written; // capture the (encrypted-at-rest) payload
      final store = SecureDeviceCredentialStore(
        const CredentialSnapshot(),
        (json) async => written = json,
      );

      store.setDefault(const DeviceCredentials('admin', 'pw'));
      store.remember('node-a', const DeviceCredentials('u', 'p'));

      // A reload from the persisted blob restores both pieces.
      final restored = CredentialSnapshot.decode(written);
      expect(restored.defaultCredentials?.user, 'admin');
      expect(restored.defaultCredentials?.pass, 'pw');
      expect(restored.hosts['node-a']?.pass, 'p');

      // Empty default clears it (and is reflected in the next write).
      store.setDefault(const DeviceCredentials('', ''));
      expect(store.defaultCredentials, isNull);
      expect(CredentialSnapshot.decode(written).defaultCredentials, isNull);
    });

    test('seeds in-memory state from the startup snapshot', () {
      final store = SecureDeviceCredentialStore(
        const CredentialSnapshot(
          defaultCredentials: DeviceCredentials('d', 'd'),
          hosts: {'h': DeviceCredentials('u', 'p')},
        ),
        (_) async {},
      );
      expect(store.defaultCredentials?.user, 'd');
      expect(store.rememberedFor('h')?.pass, 'p');
    });
  });
}

/// In-memory [DeviceCredentialStore] for controller tests.
class _FakeStore implements DeviceCredentialStore {
  _FakeStore({this.defaultCredentials, Map<String, DeviceCredentials>? hosts})
      : remembered = {...?hosts};

  @override
  DeviceCredentials? defaultCredentials;

  /// Doubles as the per-host seed and the record of what got cached.
  final Map<String, DeviceCredentials> remembered;

  @override
  DeviceCredentials? rememberedFor(String host) => remembered[host];

  @override
  void setDefault(DeviceCredentials? creds) => defaultCredentials = creds;

  @override
  void remember(String host, DeviceCredentials creds) =>
      remembered[host] = creds;
}

/// Fake client that rejects mutating calls unless the right Basic creds arrive.
class _AuthClient extends DeviceConfigClient {
  _AuthClient(this._config, {required this.user, required this.pass});

  DeviceFullConfig _config;
  final String user;
  final String pass;
  DeviceCredentials? lastCreds;

  bool _ok(DeviceCredentials? c) =>
      c != null && c.user == user && c.pass == pass;

  @override
  Future<DeviceFullConfig> getConfig(String host, int port,
          {DeviceCredentials? creds}) async =>
      _config;

  @override
  Future<DeviceStatus> getStatus(String host, int port,
          {DeviceCredentials? creds}) async =>
      DeviceStatus(info: _config.info, needReboot: _config.needReboot);

  @override
  Future<DeviceFullConfig> postConfigSection(
      String host, int port, Map<String, dynamic> payload,
      {DeviceCredentials? creds}) async {
    lastCreds = creds;
    if (!_ok(creds)) throw const DeviceAuthException();
    _config = _config.copyWith(
      host: payload['host'] as String? ?? _config.host,
      universe: payload['universe'] as int? ?? _config.universe,
      needReboot: true,
    );
    return _config;
  }
}

/// Fake client: serves an in-memory config and applies POSTed sections.
class _FakeClient extends DeviceConfigClient {
  _FakeClient(this._config);

  DeviceFullConfig _config;
  Map<String, dynamic>? lastPayload;

  @override
  Future<DeviceFullConfig> getConfig(String host, int port,
          {DeviceCredentials? creds}) async =>
      _config;

  @override
  Future<DeviceStatus> getStatus(String host, int port,
          {DeviceCredentials? creds}) async =>
      DeviceStatus(info: _config.info, needReboot: _config.needReboot);

  @override
  Future<DeviceFullConfig> postConfigSection(
      String host, int port, Map<String, dynamic> payload,
      {DeviceCredentials? creds}) async {
    lastPayload = payload;
    _config = _config.copyWith(
      host: payload['host'] as String? ?? _config.host,
      universe: payload['universe'] as int? ?? _config.universe,
      needReboot: true, // simulate a change that requires reboot
    );
    return _config;
  }
}
